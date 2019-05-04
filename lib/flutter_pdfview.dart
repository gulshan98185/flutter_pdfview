import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef void PDFViewCreatedCallback(PDFViewController controller);

//class FlutterNativePdfReader {
//  static const MethodChannel _channel =
//      const MethodChannel('flutter_native_pdf_reader');
//
//  static Future<String> get platformVersion async {
//    final String version = await _channel.invokeMethod('getPlatformVersion');
//    return version;
//  }
//}

class PDFView extends StatefulWidget {
  const PDFView({
    Key key,
    this.onWebViewCreated,
    this.gestureRecognizers,
    @required this.filePath,
    this.enableSwipe = true,
    this.swipeHorizontal = false,
    this.password,
    this.nightMode = false,
    this.autoSpacing = true,
    this.pageFling = true,
    this.pageSnap = true,
  }) : super(key: key);

  @override
  _PDFViewState createState() => _PDFViewState();

  /// If not null invoked once the web view is created.
  final PDFViewCreatedCallback onWebViewCreated;

  /// Which gestures should be consumed by the web view.
  ///
  /// It is possible for other gesture recognizers to be competing with the web view on pointer
  /// events, e.g if the web view is inside a [ListView] the [ListView] will want to handle
  /// vertical drags. The web view will claim gestures that are recognized by any of the
  /// recognizers on this list.
  ///
  /// When this set is empty or null, the web view will only handle pointer events for gestures that
  /// were not claimed by any other gesture recognizer.
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;

  /// The initial URL to load.
  final String filePath;

  final bool enableSwipe;
  final bool swipeHorizontal;
  final bool password;
  final bool nightMode;
  final bool autoSpacing;
  final bool pageFling;
  final bool pageSnap;
}

class _PDFViewState extends State<PDFView> {
  final Completer<PDFViewController> _controller =
      Completer<PDFViewController>();
  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: 'plugins.endigo.io/pdfview',
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: widget.gestureRecognizers,
        creationParams: _CreationParams.fromWidget(widget).toMap(),
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: 'plugins.endigo.io/pdfview',
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: widget.gestureRecognizers,
        creationParams: _CreationParams.fromWidget(widget).toMap(),
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return Text(
        '$defaultTargetPlatform is not yet supported by the webview_flutter plugin');
  }

  void _onPlatformViewCreated(int id) {
    final PDFViewController controller = PDFViewController._(id, widget);
    _controller.complete(controller);
    if (widget.onWebViewCreated != null) {
      widget.onWebViewCreated(controller);
    }
  }

  @override
  void didUpdateWidget(PDFView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.future.then(
            (PDFViewController controller) => controller._updateWidget(widget));
  }
}

class _CreationParams {
  _CreationParams({
    this.filePath,
    this.settings,
  });

  static _CreationParams fromWidget(PDFView widget) {
    return _CreationParams(
      filePath: widget.filePath,
      settings: _PDFViewSettings.fromWidget(widget),
    );
  }

  final String filePath;

  final _PDFViewSettings settings;

  Map<String, dynamic> toMap() {
    Map<String, dynamic> params = {
      'filePath': filePath,
    };

    params.addAll(settings.toMap());

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
    );
  }

  final bool enableSwipe;
  final bool swipeHorizontal;
  final bool password;
  final bool nightMode;
  final bool autoSpacing;
  final bool pageFling;
  final bool pageSnap;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'enableSwipe': enableSwipe,
      'swipeHorizontal': swipeHorizontal,
      'password': password,
      'nightMode': nightMode,
      'autoSpacing': autoSpacing,
      'pageFling': pageFling,
      'pageSnap': pageSnap,
    };
  }

  Map<String, dynamic> updatesMap(_PDFViewSettings newSettings) {
    final Map<String, dynamic> updates = <String, dynamic>{};
    if (enableSwipe != newSettings.enableSwipe) {
      updates['enableSwipe'] = newSettings.enableSwipe;
    }
//    if (swipeHorizontal != newSettings.swipeHorizontal) {
//      updates['swipeHorizontal'] = newSettings.swipeHorizontal;
//    }
//    if (password != newSettings.password) {
//      updates['password'] = newSettings.password;
//    }
//    if (autoSpacing != newSettings.autoSpacing) {
//      updates['autoSpacing'] = newSettings.autoSpacing;
//    }
    if (pageFling != newSettings.pageFling) {
      updates['pageFling'] = newSettings.pageFling;
    }
    if (pageSnap != newSettings.pageSnap) {
      updates['pageSnap'] = newSettings.pageSnap;
    }

    return updates;
  }
}

class PDFViewController {
  PDFViewController._(
    int id,
    this._widget,
  ) : _channel = MethodChannel('plugins.endigo.io/pdfview_$id') {
    _settings = _PDFViewSettings.fromWidget(_widget);
    _channel.setMethodCallHandler(_onMethodCall);
  }

  final MethodChannel _channel;

  _PDFViewSettings _settings;

  PDFView _widget;

  Future<bool> _onMethodCall(MethodCall call) async {
//    switch (call.method) {
//      case 'pageCount':
//        final String channel = call.arguments['channel'];
//        final String message = call.arguments['message'];
//        _javascriptChannels[channel]
//            .onMessageReceived(JavascriptMessage(message));
//        return true;
//      case 'navigationRequest':
//        final NavigationRequest request = NavigationRequest._(
//          url: call.arguments['url'],
//          isForMainFrame: call.arguments['isForMainFrame'],
//        );
//        // _navigationDelegate can be null if the widget was rebuilt with no
//        // navigation delegate after a navigation happened and just before we
//        // got the navigationRequest message.
//        final bool allowNavigation = _widget.navigationDelegate == null ||
//            _widget.navigationDelegate(request) == NavigationDecision.navigate;
//        return allowNavigation;
//      case 'onPageFinished':
//        if (_widget.onPageFinished != null) {
//          _widget.onPageFinished(call.arguments['url']);
//        }
//
//        return null;
//    }
    throw MissingPluginException(
        '${call.method} was invoked but has no handler');
  }

  Future<int> getPageCount() async {
    final int pageCount = await _channel.invokeMethod('pageCount');
    return pageCount;
  }

  Future<int> getCurrentPage() async {
    final int currentPage = await _channel.invokeMethod('currentPage');
    return currentPage;
  }

  Future<bool> setPage(int page) async {
    final bool isSet = await _channel.invokeMethod('setPage', <String, dynamic>{
      'page': page,
    });
    return isSet;
  }

  Future<void> _updateWidget(PDFView widget) async {
    _widget = widget;
    await _updateSettings(_PDFViewSettings.fromWidget(widget));
  }

  Future<void> _updateSettings(_PDFViewSettings setting) async {
    final Map<String, dynamic> updateMap = _settings.updatesMap(setting);
    if (updateMap == null || updateMap.isEmpty) {
      return null;
    }
    _settings = setting;
    return _channel.invokeMethod('updateSettings', updateMap);
  }
}
