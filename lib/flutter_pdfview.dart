// pdf_view.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

export './get_pdf_thumbnail.dart';
export './pdf_to_Image.dart';

typedef PDFViewCreatedCallback = void Function(PDFViewController controller);
typedef RenderCallback = void Function(int? pages);
typedef PageChangedCallback = void Function(int? page, int? total);
typedef ErrorCallback = void Function(dynamic error);
typedef PageErrorCallback = void Function(int? page, dynamic error);
typedef LinkHandlerCallback = void Function(String? uri);

// NEW: zoom callbacks (absolute zoom value on update)
typedef ZoomStartCallback = void Function();
typedef ZoomUpdateCallback = void Function(double zoom);
typedef ZoomEndCallback = void Function();

enum FitPolicy { WIDTH, HEIGHT, BOTH }

class PDFView extends StatefulWidget {
  const PDFView({
    Key? key,
    this.filePath,
    this.pdfData,
    this.onViewCreated,
    this.onRender,
    this.onPageChanged,
    this.onError,
    this.onPageError,
    this.onLinkHandler,
    this.gestureRecognizers,
    this.enableSwipe = true,
    this.swipeHorizontal = false,
    this.password,
    this.nightMode = false,
    this.autoSpacing = true,
    this.pageFling = true,
    this.pageSnap = true,
    this.fitEachPage = true,
    this.defaultPage = 0,
    this.fitPolicy = FitPolicy.WIDTH,
    this.preventLinkNavigation = false,
    this.backgroundColor,
    this.onTap,

    // NEW: zoom events
    this.onZoomStart,
    this.onZoomUpdate, // absolute zoom estimate, 1.0 at rest
    this.onZoomEnd,
    this.zoomGestureThreshold = 1.01, // 1% delta to start zoom

    // NEW: initial zoom to apply when PDF is rendered
    this.initialZoom,

    // NEW: whether setZoom is allowed (Dart + native will honor)
    this.enableSetZoom = true,
  })  : assert(filePath != null || pdfData != null),
        super(key: key);

  @override
  _PDFViewState createState() => _PDFViewState();

  // Core callbacks
  final PDFViewCreatedCallback? onViewCreated;
  final RenderCallback? onRender;
  final PageChangedCallback? onPageChanged;
  final Function? onTap;
  final ErrorCallback? onError;
  final PageErrorCallback? onPageError;
  final LinkHandlerCallback? onLinkHandler;

  // Gestures
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  // Source
  final String? filePath;
  final Uint8List? pdfData;

  // Settings
  final bool enableSwipe;
  final bool swipeHorizontal;
  final String? password;
  final bool nightMode;
  final bool autoSpacing;
  final bool pageFling;
  final bool pageSnap;
  final int defaultPage;
  final FitPolicy fitPolicy;
  @Deprecated("will be removed next version")
  final bool fitEachPage;
  final bool preventLinkNavigation;
  final Color? backgroundColor;

  // NEW: zoom callbacks
  final ZoomStartCallback? onZoomStart;
  final ZoomUpdateCallback? onZoomUpdate; // absolute zoom value
  final ZoomEndCallback? onZoomEnd;
  final double zoomGestureThreshold;

  // NEW: initial zoom to apply after render. 1.0 == fit.
  // If null, no zoom is forced.
  final double? initialZoom;

  // NEW: enable/disable setZoom behavior
  final bool enableSetZoom;
}

class _PDFViewState extends State<PDFView> {
  final Completer<PDFViewController> _controller = Completer<PDFViewController>();
  static const double _normBase = 1.0; // "fit"
  static const double _normMax = 4.0; // treat 4x as 1.0 in normalized scale

  // ====== Pinch detection overlay (pure Flutter; doesn't block the platform view) ======
  final Map<int, Offset> _pointers = <int, Offset>{};
  double? _pinchStartDistance;
  bool _pinchActive = false;

  // Absolute zoom estimate (since the native viewer doesn't expose zoom)
  double _estimatedZoom = 1.0; // running estimate; 1.0 = fit
  double _zoomAtPinchStart = 1.0; // baseline when second finger touches
  static const double _zoomEps = 0.02; // ±2% tolerance considered "at 1.0"

  double _dist(Offset a, Offset b) => (a - b).distance;

  double _toUnit(double z) {
    // distance from "fit" divided by range, absolute value, clamped 0..1
    final v = ((z - _normBase).abs()) / (_normMax - _normBase);
    return v.clamp(0.0, 1.0);
  }

  void _maybeHandlePinchUpdate() {
    if (_pointers.length < 2) return;

    // first two pointers
    final it = _pointers.values.iterator;
    it..moveNext();
    final p1 = it.current;
    it..moveNext();
    final p2 = it.current;

    final current = _dist(p1, p2);
    _pinchStartDistance ??= current;
    final base = _pinchStartDistance!;
    if (base <= 0.001) return;

    final scaleFromStart = current / base;

    // Trigger start once threshold exceeded
    final over = scaleFromStart > widget.zoomGestureThreshold ||
        scaleFromStart < (1.0 / widget.zoomGestureThreshold);

    if (!_pinchActive && over) {
      _pinchActive = true;
      _zoomAtPinchStart = _estimatedZoom; // capture baseline at pinch start
      widget.onZoomStart?.call();
    }

    if (_pinchActive) {
      // absolute zoom estimate
      final estimatedNow = _zoomAtPinchStart * scaleFromStart;
      _estimatedZoom = estimatedNow;
      widget.onZoomUpdate?.call(_estimatedZoom);
    }
  }

  void _endPinchIfNeeded() {
    if (_pointers.length < 2) {
      if (_pinchActive) {
        _pinchActive = false;

        // Keep last zoom instead of letting it collapse
        if ((_estimatedZoom - 1.0).abs() <= _zoomEps) {
          _estimatedZoom = 1.0; // snap to fit
        }

        widget.onZoomEnd?.call();
      }

      // DO NOT reset zoom to 0
      _pinchStartDistance = null;
    }
  }
  // =================================================================

  @override
  Widget build(BuildContext context) {
    Widget platformView;

    if (defaultTargetPlatform == TargetPlatform.android) {
      platformView = PlatformViewLink(
        viewType: 'plugins.endigo.io/pdfview',
        surfaceFactory: (BuildContext context, PlatformViewController controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: widget.gestureRecognizers ?? const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (PlatformViewCreationParams params) {
          return PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: 'plugins.endigo.io/pdfview',
            layoutDirection: TextDirection.rtl,
            creationParams: _CreationParams.fromWidget(widget).toMap(),
            creationParamsCodec: const StandardMessageCodec(),
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..addOnPlatformViewCreatedListener((int id) {
              _onPlatformViewCreated(id);
            })
            ..create();
        },
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      platformView = UiKitView(
        viewType: 'plugins.endigo.io/pdfview',
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: widget.gestureRecognizers,
        creationParams: _CreationParams.fromWidget(widget).toMap(),
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else {
      platformView = Text('$defaultTargetPlatform is not yet supported by the pdfview_flutter plugin');
    }

    // Wrap with a transparent Listener to observe two-finger pinch without intercepting it.
    return Stack(
      children: [
        platformView,
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent, // don't block the native view
            onPointerDown: (e) {
              _pointers[e.pointer] = e.position;
              if (_pointers.length == 2) {
                _pinchStartDistance = null; // reset baseline when second finger touches
              }
            },
            onPointerMove: (e) {
              if (_pointers.containsKey(e.pointer)) {
                _pointers[e.pointer] = e.position;
                _maybeHandlePinchUpdate();
              }
            },
            onPointerUp: (e) {
              _pointers.remove(e.pointer);
              _endPinchIfNeeded();
            },
            onPointerCancel: (e) {
              _pointers.remove(e.pointer);
              _endPinchIfNeeded();
            },
          ),
        ),
      ],
    );
  }

  void _onPlatformViewCreated(int id) {
    final PDFViewController controller = PDFViewController._(id, widget);
    _controller.complete(controller);
    widget.onViewCreated?.call(controller);
    // No direct call to setZoom here — we rely on the native 'onRender' event to
    // apply initialZoom (see PDFViewController._onMethodCall below).
  }

  @override
  void didUpdateWidget(PDFView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.future.then((PDFViewController controller) => controller._updateWidget(widget));
  }

  @override
  void dispose() {
    _controller.future.then((PDFViewController controller) => controller.dispose());
    super.dispose();
  }
}

class _CreationParams {
  _CreationParams({
    this.filePath,
    this.pdfData,
    this.settings,
    this.enableSetZoom,
  });

  static _CreationParams fromWidget(PDFView widget) {
    return _CreationParams(
      filePath: widget.filePath,
      pdfData: widget.pdfData,
      settings: _PDFViewSettings.fromWidget(widget),
      enableSetZoom: widget.enableSetZoom,
    );
  }

  final String? filePath;
  final Uint8List? pdfData;
  final _PDFViewSettings? settings;
  final bool? enableSetZoom;

  Map<String, dynamic> toMap() {
    final params = <String, dynamic>{
      'filePath': filePath,
      'pdfData': pdfData,
      'enableSetZoom': enableSetZoom,
    };
    params.addAll(settings!.toMap());
    return params;
  }
}

class _PDFViewSettings {
  _PDFViewSettings({
    this.enableSwipe,
    this.swipeHorizontal,
    this.password,
    this.nightMode,
    this.autoSpacing,
    this.pageFling,
    this.pageSnap,
    this.defaultPage,
    this.fitPolicy,
    this.preventLinkNavigation,
    this.backgroundColor,
    this.enableSetZoom,
  });

  static _PDFViewSettings fromWidget(PDFView widget) {
    return _PDFViewSettings(
      enableSwipe: widget.enableSwipe,
      swipeHorizontal: widget.swipeHorizontal,
      password: widget.password,
      nightMode: widget.nightMode,
      autoSpacing: widget.autoSpacing,
      pageFling: widget.pageFling,
      pageSnap: widget.pageSnap,
      defaultPage: widget.defaultPage,
      fitPolicy: widget.fitPolicy,
      preventLinkNavigation: widget.preventLinkNavigation,
      backgroundColor: widget.backgroundColor,
      enableSetZoom: widget.enableSetZoom,
    );
  }

  final bool? enableSwipe;
  final bool? swipeHorizontal;
  final String? password;
  final bool? nightMode;
  final bool? autoSpacing;
  final bool? pageFling;
  final bool? pageSnap;
  final int? defaultPage;
  final FitPolicy? fitPolicy;
  final bool? preventLinkNavigation;
  final Color? backgroundColor;

  // NEW: include enableSetZoom so we can update it at runtime
  final bool? enableSetZoom;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'enableSwipe': enableSwipe,
      'swipeHorizontal': swipeHorizontal,
      'password': password,
      'nightMode': nightMode,
      'autoSpacing': autoSpacing,
      'pageFling': pageFling,
      'pageSnap': pageSnap,
      'defaultPage': defaultPage,
      'fitPolicy': fitPolicy.toString(),
      'preventLinkNavigation': preventLinkNavigation,
      'backgroundColor': backgroundColor?.value,
      'enableSetZoom': enableSetZoom,
    };
  }

  Map<String, dynamic> updatesMap(_PDFViewSettings newSettings) {
    final Map<String, dynamic> updates = <String, dynamic>{};
    if (enableSwipe != newSettings.enableSwipe) updates['enableSwipe'] = newSettings.enableSwipe;
    if (pageFling != newSettings.pageFling) updates['pageFling'] = newSettings.pageFling;
    if (pageSnap != newSettings.pageSnap) updates['pageSnap'] = newSettings.pageSnap;
    if (preventLinkNavigation != newSettings.preventLinkNavigation) {
      updates['preventLinkNavigation'] = newSettings.preventLinkNavigation;
    }
    if (enableSetZoom != newSettings.enableSetZoom) updates['enableSetZoom'] = newSettings.enableSetZoom;
    return updates;
  }
}

class PDFViewController {
  PDFViewController._(
      int id,
      PDFView widget,
      )   : _channel = MethodChannel('plugins.endigo.io/pdfview_$id'),
        _widget = widget {
    _settings = _PDFViewSettings.fromWidget(widget);
    _channel.setMethodCallHandler(_onMethodCall);
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _widget = null;
  }

  MethodChannel _channel;
  late _PDFViewSettings _settings;
  PDFView? _widget;

  /// Handle incoming platform method calls from native
  Future<bool?> _onMethodCall(MethodCall call) async {
    final widget = _widget;
    if (widget == null) return null;

    switch (call.method) {
      case 'onRender':
      // Native view finished rendering pages. First, forward to user callback:
        widget.onRender?.call(call.arguments['pages']);

        // THEN: if widget.initialZoom is provided and setZoom is enabled, apply it now (only once).
        // This ensures native page metrics are available so native code can compute
        // the correct "fitScale".
        final double? initialZoom = widget.initialZoom;
        if (initialZoom != null && widget.enableSetZoom) {
          // attempt to set zoom on native viewer
          try {
            await setZoom(initialZoom);
          } catch (e) {
            // swallow — if native can't set zoom now, native side can also apply it
            // when ready; at least we attempted.
          }
          // Null out initialZoom in the widget isn't possible — user may rebuild widget.
          // If you want to only apply once, pass a distinct "applyInitialZoomOnce" flag
          // via creationParams or store state in your app-level code.
        }
        return null;

      case 'onPageChanged':
        widget.onPageChanged?.call(call.arguments['page'], call.arguments['total']);
        return null;
      case 'onError':
        widget.onError?.call(call.arguments['error']);
        return null;
      case 'onPageError':
        widget.onPageError?.call(call.arguments['page'], call.arguments['error']);
        return null;
      case 'onLinkHandler':
        widget.onLinkHandler?.call(call.arguments);
        return null;
      case 'onTap':
        widget.onTap?.call();
        return null;
    }
    throw MissingPluginException('${call.method} was invoked but has no handler');
  }

  Future<int?> getPageCount() async => _channel.invokeMethod<int>('pageCount');
  Future<int?> getCurrentPage() async => _channel.invokeMethod<int>('currentPage');

  Future<bool?> setPage(int page) async {
    return _channel.invokeMethod<bool>('setPage', <String, dynamic>{'page': page});
  }

  /// New: set absolute zoom. Convention: `zoom = 1.0` is "fit".
  /// Native side should interpret this as scaleFactor = fitScale * zoom.
  Future<void> setZoom(double zoom) async {
    assert(zoom > 0.0);
    // Respect widget-level flag: do not call native setZoom if disabled
    if (_widget != null && !_widget!.enableSetZoom) return;
    await _channel.invokeMethod('setZoom', <String, dynamic>{'zoom': zoom});
  }

  Future<void> _updateWidget(PDFView widget) async {
    _widget = widget;
    await _updateSettings(_PDFViewSettings.fromWidget(widget));
  }

  Future<void> _updateSettings(_PDFViewSettings setting) async {
    final updates = _settings.updatesMap(setting);
    if (updates.isEmpty) return;
    _settings = setting;
    await _channel.invokeMethod('updateSettings', updates);
  }
}
