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

    // Keep PDFKit's active pinch scale when this platform view is laid out.
    this.preserveZoomOnLayout = false,
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

  // Opt-in because only the main PDF editor needs stable native pinch layout.
  final bool preserveZoomOnLayout;
}

class _PDFViewState extends State<PDFView> {
  final Completer<PDFViewController> _controller =
      Completer<PDFViewController>();
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

  // Defensive thresholds for normalization
  static const double _minReasonableZoom =
      0.2; // anything below treated as noise/fit
  static const double _maxReasonableZoom = 10.0; // clamp upper bound

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
    // if first time with two pointers, set baseline distance
    _pinchStartDistance ??= current;
    final base = _pinchStartDistance!;
    if (base <= 0.001) return;

    final scaleFromStart = current / base;

    // Trigger start once threshold exceeded
    final over = scaleFromStart > widget.zoomGestureThreshold ||
        scaleFromStart < (1.0 / widget.zoomGestureThreshold);

    if (!_pinchActive && over) {
      _pinchActive = true;

      // Use a sane baseline: prefer current estimate if reasonable, otherwise default to 1.0
      _zoomAtPinchStart =
          (_estimatedZoom.isFinite && _estimatedZoom >= _minReasonableZoom)
              ? _estimatedZoom
              : _normBase;

      widget.onZoomStart?.call();
      debugPrint(
          '🔹 onZoomStart (pinch) baseline=$_zoomAtPinchStart pinchBase=$base');
    }

    if (_pinchActive) {
      // absolute zoom estimate before normalization
      double estimatedNow = _zoomAtPinchStart * scaleFromStart;

      // Defensive normalization:
      if (estimatedNow.isNaN || estimatedNow.isInfinite) {
        estimatedNow = _normBase;
      }
      // If extremely small, treat as fit (noise)
      if (estimatedNow < _minReasonableZoom) {
        debugPrint(
            '⚠️ pinch estimate very small ($estimatedNow) -> snapping to fit (1.0)');
        estimatedNow = _normBase;
      }

      // Clamp to a sane maximum
      estimatedNow = estimatedNow.clamp(_minReasonableZoom, _maxReasonableZoom);

      // Round to avoid floating jitter
      _estimatedZoom = double.parse(estimatedNow.toStringAsFixed(3));

      // Emit normalized zoom (1.0 == fit)
      widget.onZoomUpdate?.call(_estimatedZoom);

      debugPrint(
          '🔸 onZoomUpdate rawScale=$scaleFromStart estimatedNow=$_estimatedZoom');
    }
  }

  void _endPinchIfNeeded() {
    if (_pointers.length < 2) {
      if (_pinchActive) {
        _pinchActive = false;

        // Snap small values to fit
        if ((_estimatedZoom - 1.0).abs() <= _zoomEps ||
            _estimatedZoom < _minReasonableZoom) {
          _estimatedZoom = 1.0; // snap to fit
        }

        widget.onZoomEnd?.call();
        debugPrint('🔹 onZoomEnd finalZoom=$_estimatedZoom');
      }

      // Reset pinch baseline; next two-finger touch will re-establish it
      _pinchStartDistance = null;
    }
  }
  // =================================================================

  @override
  Widget build(BuildContext context) {
    Widget platformView;

    // Build a mutable set of recognizers starting from any provided by the user.
    final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers =
        (widget.gestureRecognizers != null)
            ? Set<Factory<OneSequenceGestureRecognizer>>.from(
                widget.gestureRecognizers!)
            : <Factory<OneSequenceGestureRecognizer>>{};

    // Add a no-op HorizontalDrag recognizer to consume horizontal drags when
    // swipeHorizontal is false (prevents native horizontal panning).
    if (!widget.swipeHorizontal) {
      gestureRecognizers.add(
        Factory<OneSequenceGestureRecognizer>(() {
          final recognizer = HorizontalDragGestureRecognizer();
          // no-op handlers just to claim the gesture
          recognizer.onStart = (_) {};
          recognizer.onUpdate = (_) {};
          recognizer.onEnd = (_) {};
          recognizer.onCancel = () {};
          return recognizer;
        }),
      );
    }

    // Create the platform view for Android / iOS. We pass our recognizers.
    if (defaultTargetPlatform == TargetPlatform.android) {
      platformView = PlatformViewLink(
        viewType: 'plugins.endigo.io/pdfview',
        surfaceFactory:
            (BuildContext context, PlatformViewController controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: gestureRecognizers,
            // OPAQUE is fine — we will clip the rendered surface below.
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
        gestureRecognizers: gestureRecognizers,
        creationParams: _CreationParams.fromWidget(widget).toMap(),
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else {
      platformView = Text(
          '$defaultTargetPlatform is not yet supported by the pdfview_flutter plugin');
    }

    // Wrap the platform view in ClipRect + Align so any native overflow is hidden.
    // Align.center will keep the PDF centered inside the widget bounds.
    final Widget clippedPlatformView = ClipRect(
      child: Align(
        alignment: Alignment.center,
        widthFactor: 1.0,
        heightFactor: 1.0,
        child: SizedBox.expand(child: platformView),
      ),
    );

    // Listener remains to observe pointer positions for pinch detection.
    return Stack(
      children: [
        clippedPlatformView,
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior
                .translucent, // observe pointers without blocking events required for pinch
            onPointerDown: (e) {
              _pointers[e.pointer] = e.position;
              if (_pointers.length == 2) {
                // reset baseline distance so new pinch starts from fresh baseline
                _pinchStartDistance = null;
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
    _controller.future.then(
        (PDFViewController controller) => controller._updateWidget(widget));
  }

  @override
  void dispose() {
    _controller.future
        .then((PDFViewController controller) => controller.dispose());
    super.dispose();
  }
}

class _CreationParams {
  _CreationParams(
      {this.filePath,
      this.pdfData,
      this.settings,
      this.enableSetZoom,
      this.initialZoom,
      this.preserveZoomOnLayout});

  static _CreationParams fromWidget(PDFView widget) {
    return _CreationParams(
        filePath: widget.filePath,
        pdfData: widget.pdfData,
        settings: _PDFViewSettings.fromWidget(widget),
        enableSetZoom: widget.enableSetZoom,
        initialZoom: widget.initialZoom,
        preserveZoomOnLayout: widget.preserveZoomOnLayout);
  }

  final String? filePath;
  final Uint8List? pdfData;
  final _PDFViewSettings? settings;
  final bool? enableSetZoom;
  final double? initialZoom;
  final bool? preserveZoomOnLayout;

  Map<String, dynamic> toMap() {
    final params = <String, dynamic>{
      'filePath': filePath,
      'pdfData': pdfData,
      'enableSetZoom': enableSetZoom,
      'initialZoom': initialZoom,
      'preserveZoomOnLayout': preserveZoomOnLayout,
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
    this.fitEachPage,
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
      fitEachPage: widget.fitEachPage,
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
  final bool? fitEachPage;
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
      'fitEachPage': fitEachPage,
      'preventLinkNavigation': preventLinkNavigation,
      'backgroundColor': backgroundColor?.value,
      'enableSetZoom': enableSetZoom,
    };
  }

  Map<String, dynamic> updatesMap(_PDFViewSettings newSettings) {
    final Map<String, dynamic> updates = <String, dynamic>{};
    if (enableSwipe != newSettings.enableSwipe)
      updates['enableSwipe'] = newSettings.enableSwipe;
    if (pageFling != newSettings.pageFling)
      updates['pageFling'] = newSettings.pageFling;
    if (pageSnap != newSettings.pageSnap)
      updates['pageSnap'] = newSettings.pageSnap;
    if (preventLinkNavigation != newSettings.preventLinkNavigation) {
      updates['preventLinkNavigation'] = newSettings.preventLinkNavigation;
    }
    if (enableSetZoom != newSettings.enableSetZoom)
      updates['enableSetZoom'] = newSettings.enableSetZoom;
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
  Future<void> reload() async {
    try {
      await _channel.invokeMethod('reload');
    } catch (e) {
      debugPrint('Reload not implemented: $e');
    }
  }

  Future<void> animateToTop({
    Duration duration = const Duration(milliseconds: 400),
  }) async {
    await _channel.invokeMethod('animateToTop', {
      'duration': duration.inMilliseconds,
    });
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
        widget.onRender?.call(call.arguments['pages']);
        return null;

      case 'onPageChanged':
        widget.onPageChanged
            ?.call(call.arguments['page'], call.arguments['total']);
        return null;
      case 'onError':
        widget.onError?.call(call.arguments['error']);
        return null;
      case 'onPageError':
        widget.onPageError
            ?.call(call.arguments['page'], call.arguments['error']);
        return null;
      case 'onLinkHandler':
        widget.onLinkHandler?.call(call.arguments);
        return null;
      case 'onTap':
        widget.onTap?.call();
        return null;
    }
    throw MissingPluginException(
        '${call.method} was invoked but has no handler');
  }

  /// Actual native scale and its limits, in the same platform-specific units.
  Future<Map<String, double>?> getZoomState() async {
    final state = await _channel.invokeMapMethod<String, num>('getZoomState');
    return state?.map((key, value) => MapEntry(key, value.toDouble()));
  }

  Future<int?> getPageCount() async => _channel.invokeMethod<int>('pageCount');
  Future<int?> getCurrentPage() async =>
      _channel.invokeMethod<int>('currentPage');

  Future<bool?> setPage(int page) async {
    return _channel
        .invokeMethod<bool>('setPage', <String, dynamic>{'page': page});
  }

  /// New: set absolute zoom. Convention: `zoom = 1.0` is "fit".
  /// Native side should interpret this as scaleFactor = fitScale * zoom.
  Future<void> setZoom(double zoom) async {
    assert(zoom > 0.0);
    // Respect widget-level flag: do not call native setZoom if disabled
    if (_widget != null && !_widget!.enableSetZoom) return;

    try {
      await _channel.invokeMethod('setZoom', <String, dynamic>{'zoom': zoom});
    } on MissingPluginException catch (e) {
      // Native side does not implement setZoom — swallow but log for debugging
      debugPrint('setZoom not implemented on native side: $e');
    } on PlatformException catch (e) {
      debugPrint('PlatformException while calling setZoom: ${e.message}');
      rethrow; // rethrow only if you want callers to see it
    } catch (e) {
      debugPrint('Unexpected error calling setZoom: $e');
    }
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
