// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#import "./include/flutter_pdfview/FlutterPDFView.h"
#import <math.h>

@implementation FLTPDFViewFactory {
    NSObject <FlutterBinaryMessenger> *_messenger;
}

- (instancetype)initWithMessenger:(NSObject <FlutterBinaryMessenger> *)messenger {
    self = [super init];
    if (self) {
        _messenger = messenger;
    }
    return self;
}

- (NSObject <FlutterMessageCodec> *)createArgsCodec {
    return [FlutterStandardMessageCodec sharedInstance];
}

- (NSObject <FlutterPlatformView> *)createWithFrame:(CGRect)frame
                                     viewIdentifier:(int64_t)viewId
                                          arguments:(id _Nullable)args {
    FLTPDFViewController *pdfviewController = [[FLTPDFViewController alloc] initWithFrame:frame
                                                                           viewIdentifier:viewId
                                                                                arguments:args
                                                                          binaryMessenger:_messenger];
    return pdfviewController;
}

@end

@implementation FLTPDFViewController {
    FLTPDFView *_pdfView;
    UIView *_containerView;
    NSDictionary *_creationArguments;
    NSMutableDictionary<NSString *, FLTPDFView *> *_documentViews;
    NSMutableDictionary<NSString *, NSDictionary *> *_documentVersions;
    // Rapid tab changes previously replaced PDFView.document repeatedly.
    // The crash dump stopped in CFRelease -> PDFTileSurface.releaseSurface
    // during a Core Animation transaction. Keep each open document attached
    // to its own viewer, and switch visibility without tearing down its tiles.
    // Release retained viewers on close; recreate only when the file changes.
    BOOL _retainDocumentViews;
    int64_t _viewId;
    FlutterMethodChannel *_channel;
}

- (instancetype)initWithFrame:(CGRect)frame
               viewIdentifier:(int64_t)viewId
                    arguments:(id _Nullable)args
              binaryMessenger:(NSObject <FlutterBinaryMessenger> *)messenger {
    self = [super init];
    _creationArguments = [args copy];
    _retainDocumentViews = [args[@"retainDocumentViews"] boolValue];
    _pdfView = [[FLTPDFView alloc] initWithFrame:frame arguments:args controller:self];
    if (_retainDocumentViews) {
        _containerView = [[UIView alloc] initWithFrame:frame];
        _containerView.clipsToBounds = YES;
        _pdfView.frame = _containerView.bounds;
        _pdfView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_containerView addSubview:_pdfView];
        _documentViews = [NSMutableDictionary dictionary];
        _documentVersions = [NSMutableDictionary dictionary];
        NSString *path = args[@"filePath"];
        if ([path isKindOfClass:[NSString class]]) {
            _documentViews[path] = _pdfView;
            _documentVersions[path] = [self documentVersionAtPath:path];
        }
    }
    _viewId = viewId;

    @try {
        NSNumber *backgroundColor = args[@"backgroundColor"];
        if ([backgroundColor isKindOfClass:[NSNumber class]]) {
            unsigned int argb = [backgroundColor unsignedIntValue];
            CGFloat a = ((argb & 0xFF000000) >> 24) / 255.0;
            CGFloat r = ((argb & 0x00FF0000) >> 16) / 255.0;
            CGFloat g = ((argb & 0x0000FF00) >> 8) / 255.0;
            CGFloat b = (argb & 0x000000FF) / 255.0;
            _pdfView.view.backgroundColor = [UIColor colorWithRed:r green:g blue:b alpha:a];
        }
    } @catch (NSException *exception) {
        NSLog(@"Exception while setting background color: %@", exception);
    }

    NSString *channelName = [NSString stringWithFormat:@"plugins.endigo.io/pdfview_%lld", viewId];
    _channel = [FlutterMethodChannel methodChannelWithName:channelName binaryMessenger:messenger];
    __weak __typeof__(self) weakSelf = self;
    [_channel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
        [weakSelf onMethodCall:call result:result];
    }];

    return self;
}

- (void)onMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([[call method] isEqualToString:@"pageCount"]) {
        [_pdfView getPageCount:call result:result];
    } else if ([[call method] isEqualToString:@"getZoomState"]) {
        [_pdfView getZoomState:result];
    } else if ([[call method] isEqualToString:@"currentPage"]) {
        [_pdfView getCurrentPage:call result:result];
    } else if ([[call method] isEqualToString:@"setPage"]) {
        [_pdfView setPage:call result:result];
    } else if ([[call method] isEqualToString:@"updateSettings"]) {
        [_pdfView onUpdateSettings:call result:result];
    }
    else if ([[call method] isEqualToString:@"reload"]) {
        [_pdfView reloadPdf:result];
    } else if ([[call method] isEqualToString:@"loadDocument"]) {
        if (_retainDocumentViews) {
            [self showRetainedDocument:call result:result];
        } else {
            result(FlutterMethodNotImplemented);
        }
    } else if ([[call method] isEqualToString:@"retainDocumentPaths"]) {
        [self retainDocumentPaths:call.arguments[@"paths"]];
        result(nil);
    }else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)invokeChannelMethod:(NSString *)name arguments:(id)args {
    [_channel invokeMethod:name arguments:args];
}

// Size and modification time invalidate a viewer when edits rewrite its file.
- (NSDictionary *)documentVersionAtPath:(NSString *)path {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    return @{@"size": attributes[NSFileSize] ?: @0,
             @"modified": attributes[NSFileModificationDate] ?: [NSDate distantPast]};
}

- (void)retainDocumentPaths:(NSArray *)paths {
    if (!_retainDocumentViews || ![paths isKindOfClass:[NSArray class]]) return;
    NSSet *openPaths = [NSSet setWithArray:paths];
    for (NSString *path in [_documentViews.allKeys copy]) {
        FLTPDFView *view = _documentViews[path];
        // The outgoing view remains alive until the new one is active.
        if (![openPaths containsObject:path] && view != _pdfView) {
            [view removeFromSuperview];
            [_documentViews removeObjectForKey:path];
            [_documentVersions removeObjectForKey:path];
        }
    }
}

- (void)showRetainedDocument:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *path = call.arguments[@"filePath"];
    if (![path isKindOfClass:[NSString class]] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        result(@NO);
        return;
    }
    NSDictionary *version = [self documentVersionAtPath:path];
    FLTPDFView *nextView = _documentViews[path];
    BOOL cacheHit = nextView != nil && [_documentVersions[path] isEqual:version];
    if (!cacheHit) {
        // Validate before changing the visible viewer. No document is ever
        // reassigned on a cached tab switch, avoiding PDFKit tile teardown.
        PDFDocument *document = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:path]];
        if (document == nil || document.isLocked || document.pageCount == 0) {
            result(@NO);
            return;
        }
        NSMutableDictionary *args = [_creationArguments mutableCopy];
        args[@"filePath"] = path;
        args[@"defaultPage"] = call.arguments[@"defaultPage"] ?: @0;
        [args removeObjectForKey:@"pdfData"];
        nextView = [[FLTPDFView alloc] initWithFrame:_containerView.bounds arguments:args controller:self];
        nextView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        nextView.view.backgroundColor = _pdfView.view.backgroundColor;
        FLTPDFView *staleView = _documentViews[path];
        [staleView removeFromSuperview];
        _documentViews[path] = nextView;
        _documentVersions[path] = version;
        [_containerView addSubview:nextView];
    }
    _pdfView.hidden = YES;
    _pdfView = nextView;
    _pdfView.hidden = NO;
    [_containerView bringSubviewToFront:_pdfView];
    [_pdfView setNeedsLayout];
    [_pdfView layoutIfNeeded];
    [self retainDocumentPaths:call.arguments[@"openDocumentPaths"]];
    // The method response means the viewer is selected, not that asynchronous
    // PDFKit rendering has completed. Dart queries the retained page state.
    result(@YES);
}

- (void)invokeChannelMethodFromView:(FLTPDFView *)view name:(NSString *)name arguments:(id)args {
    // Hidden viewers can still finish rendering or analysing. Their callbacks
    // must never update the selected document's page/zoom state in Flutter.
    if (view == _pdfView) {
        [self invokeChannelMethod:name arguments:args];
    }
}

- (UIView *)view {
    return _retainDocumentViews ? _containerView : _pdfView;
}

@end

@implementation FLTPDFView {
    FLTPDFViewController *__weak _controller;
    PDFView *_pdfView;
    NSNumber *_pageCount;
    NSNumber *_currentPage;
    PDFDestination *_currentDestination;
    BOOL _preventLinkNavigation;
    BOOL _enableDataDetectors;
    BOOL _autoSpacing;
    BOOL _fitEachPage;
    PDFPage *_defaultPage;
    BOOL _defaultPageSet;
    BOOL _preserveZoomOnLayout;
    BOOL _didApplyInitialFit;
    CGRect _lastLayoutBounds;
    UIScrollView *_scrollView;

    UITapGestureRecognizer *_singleTapGR;
    UITapGestureRecognizer *_doubleTapGR;
}

- (instancetype)initWithFrame:(CGRect)frame
                    arguments:(id _Nullable)args
                   controller:(nonnull FLTPDFViewController*)controller {
    self = [super initWithFrame:frame];
    if (self == nil) return nil;
    _controller = controller;

    _pdfView = [[PDFView alloc] initWithFrame:frame];
    _pdfView.delegate = self;
    _pdfView.userInteractionEnabled = YES;

    _autoSpacing = [args[@"autoSpacing"] boolValue];
    _fitEachPage = [args[@"fitEachPage"] boolValue];
    _preserveZoomOnLayout = [args[@"preserveZoomOnLayout"] boolValue];
    BOOL pageFling = [args[@"pageFling"] boolValue];
    BOOL enableSwipe = [args[@"enableSwipe"] boolValue];
    _preventLinkNavigation = [args[@"preventLinkNavigation"] boolValue];
    NSNumber *dataDetectors = args[@"enableDataDetectors"];
    _enableDataDetectors = dataDetectors == nil ? YES : dataDetectors.boolValue;

    NSInteger defaultPage = [args[@"defaultPage"] integerValue];

    NSString *filePath = args[@"filePath"];
    FlutterStandardTypedData *pdfData = args[@"pdfData"];

    PDFDocument *document = nil;
    if ([filePath isKindOfClass:[NSString class]]) {
        @try {
            NSURL *sourcePDFUrl = [NSURL fileURLWithPath:filePath];
            document = [[PDFDocument alloc] initWithURL:sourcePDFUrl];
        } @catch (NSException *exception) {
            NSLog(@"[PDFView] initial_document_exception file=%@ name=%@ reason=%@",
                  filePath.lastPathComponent, exception.name, exception.reason);
        }
    } else if ([pdfData isKindOfClass:[FlutterStandardTypedData class]]) {
        NSData *sourcePDFdata = [pdfData data];
        @try {
            document = [[PDFDocument alloc] initWithData:sourcePDFdata];
        } @catch (NSException *exception) {
            NSLog(@"[PDFView] initial_data_exception name=%@ reason=%@",
                  exception.name, exception.reason);
        }
    }

    if (document == nil) {
        NSLog(@"[PDFView] Could not open PDF document.");
    } else {
        _pdfView.pageBreakMargins = UIEdgeInsetsMake(8, 16, 8, 16);
        _pdfView.autoresizesSubviews = YES;
        _pdfView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;;

        BOOL swipeHorizontal = [args[@"swipeHorizontal"] boolValue];
        _pdfView.displayDirection = swipeHorizontal ? kPDFDisplayDirectionHorizontal : kPDFDisplayDirectionVertical;

        _pdfView.autoScales = _autoSpacing;

        [_pdfView usePageViewController:pageFling withViewOptions:nil];
        _pdfView.displayMode = enableSwipe ? kPDFDisplaySinglePageContinuous : kPDFDisplaySinglePage;
        //Checking for locked document
        NSString *password = args[@"password"];
        if ([password isKindOfClass:[NSString class]] && document.isLocked) {
            [document unlockWithPassword:password];
        }
        //Encryption can show dialog on non-protected document
//        NSString *password = args[@"password"];
//        if ([password isKindOfClass:[NSString class]] && [_pdfView.document isEncrypted]) {
//            [_pdfView.document unlockWithPassword:password];
//        }
        _pdfView.document = document;
        // Generated image previews do not need automatic phone/date/address
        // scanning. iOS 26 PDFScannerResult can trap while scanning a tapped
        // image-only page, before Flutter receives its onTap callback.
        _pdfView.enableDataDetectors = _enableDataDetectors;

        if (_preserveZoomOnLayout) {
            CGFloat requestedMaxScale = [args[@"maxZoom"] doubleValue];
            if (!isfinite(requestedMaxScale) || requestedMaxScale <= 0.0) {
                requestedMaxScale = 4.0;
            }
            _pdfView.maxScaleFactor = requestedMaxScale;

            const CGFloat initialFit = _pdfView.scaleFactorForSizeToFit;
            if (isfinite(initialFit) && initialFit > 0.0) {
                _pdfView.minScaleFactor = initialFit;
            }
        } else {
            _pdfView.maxScaleFactor = [args[@"maxZoom"] doubleValue];
            _pdfView.minScaleFactor = _pdfView.scaleFactorForSizeToFit;
        }

        // --- Gestures (deterministic) ---
        _singleTapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        _singleTapGR.numberOfTapsRequired = 1;
        _singleTapGR.numberOfTouchesRequired = 1;
        _singleTapGR.cancelsTouchesInView = NO;   // don't swallow links
        _singleTapGR.delegate = self;

        _doubleTapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onDoubleTap:)];
        _doubleTapGR.numberOfTapsRequired = 2;
        _doubleTapGR.numberOfTouchesRequired = 1;
        _doubleTapGR.cancelsTouchesInView = NO;   // don't swallow links
        _doubleTapGR.delegate = self;

        // Single-tap should wait for double-tap failure (keeps zoom UX)
        [_singleTapGR requireGestureRecognizerToFail:_doubleTapGR];

        [_pdfView addGestureRecognizer:_singleTapGR];
        [_pdfView addGestureRecognizer:_doubleTapGR];

        // Force every other 2-tap recognizer (PDFKit / UIPageViewController) to defer to ours
        for (UIGestureRecognizer *gr in _pdfView.gestureRecognizers) {
            if (gr == _doubleTapGR || gr == _singleTapGR) continue;
            if ([gr isKindOfClass:[UITapGestureRecognizer class]]) {
                UITapGestureRecognizer *t = (UITapGestureRecognizer *)gr;
                if (t.numberOfTapsRequired == 2) {
                    [t requireGestureRecognizerToFail:_doubleTapGR];
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            for (UIGestureRecognizer *gr in self->_pdfView.gestureRecognizers) {
                if (gr == self->_doubleTapGR || gr == self->_singleTapGR) continue;
                if ([gr isKindOfClass:[UITapGestureRecognizer class]]) {
                    UITapGestureRecognizer *t = (UITapGestureRecognizer *)gr;
                    if (t.numberOfTapsRequired == 2) {
                        [t requireGestureRecognizerToFail:self->_doubleTapGR];
                    }
                }
            }
        });

        NSUInteger pageCount = [document pageCount];
        // A locked/empty document has no valid page index and is not rendered.
        if (!document.isLocked && pageCount > 0) {
            if (defaultPage < 0) defaultPage = 0;
            if ((NSUInteger)defaultPage >= pageCount) defaultPage = pageCount - 1;
            _defaultPage = [document pageAtIndex:defaultPage];
            __weak __typeof__(self) weakSelf = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf handleRenderCompleted:[NSNumber numberWithUnsignedLong:pageCount]];
            });
        }
    }

    if (@available(iOS 11.0, *)) {
        for (id subview in _pdfView.subviews) {
            if ([subview isKindOfClass:[UIScrollView class]]) {
                _scrollView = subview;
            }
        }
        _scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        if (@available(iOS 13.0, *)) {
            _scrollView.automaticallyAdjustsScrollIndicatorInsets = NO;
        }
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handlePageChanged:)
                                                 name:PDFViewPageChangedNotification
                                               object:_pdfView];

    [self addSubview:_pdfView];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _pdfView.delegate = nil;
    _pdfView.document = nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _pdfView.frame = self.bounds;

    if (_preserveZoomOnLayout) {
        const BOOL pinchInProgress = _scrollView != nil &&
            (_scrollView.pinchGestureRecognizer.state == UIGestureRecognizerStateBegan ||
             _scrollView.pinchGestureRecognizer.state == UIGestureRecognizerStateChanged);
        const BOOL boundsChanged = !CGRectEqualToRect(_lastLayoutBounds, self.bounds);
        const BOOL hasUsableBounds = self.bounds.size.width > 0.0 && self.bounds.size.height > 0.0;
        const CGFloat fit = hasUsableBounds ? _pdfView.scaleFactorForSizeToFit : 0.0;
        const BOOL validFit = isfinite(fit) && fit > 0.0;

        NSLog(@"[PDF_ZOOM_TRACE][HOME_PDF_EDITOR] bounds=%@ fit=%.6f scale=%.6f min=%.6f max=%.6f pinch=%d changed=%d",
              NSStringFromCGRect(self.bounds), fit, _pdfView.scaleFactor,
              _pdfView.minScaleFactor, _pdfView.maxScaleFactor,
              pinchInProgress, boundsChanged);

        if (validFit && !pinchInProgress) {
            _pdfView.minScaleFactor = fit;
            _pdfView.maxScaleFactor = MAX(4.0, fit);
            if (_autoSpacing && (!_didApplyInitialFit || boundsChanged)) {
                _pdfView.scaleFactor = fit;
                _didApplyInitialFit = true;
            }
        }
        _lastLayoutBounds = self.bounds;
    } else {
        _pdfView.minScaleFactor = _pdfView.scaleFactorForSizeToFit;
        _pdfView.maxScaleFactor = 4.0;
        if (_autoSpacing) {
            _pdfView.scaleFactor = _pdfView.scaleFactorForSizeToFit;
        }
    }

    if (!_defaultPageSet && _defaultPage != nil) {
        [_pdfView goToPage:_defaultPage];
        _defaultPageSet = true;
    }
}

- (UIView *)view {
    return _pdfView;
}
- (void)reloadPdf:(FlutterResult)result {

    NSURL *url = _pdfView.document.documentURL;
    if (!url) {
        result(@(NO));
        return;
    }

    NSUInteger currentIndex = [_pdfView.document indexForPage:_pdfView.currentPage];

    // 🔥 Completely destroy old document
    _pdfView.document = nil;

    // 🔥 Create brand new document from disk
    PDFDocument *newDocument = [[PDFDocument alloc] initWithURL:url];

    if (!newDocument) {
        result(@(NO));
        return;
    }

    _pdfView.document = newDocument;
    _pdfView.enableDataDetectors = _enableDataDetectors;

    // 🔥 Reset scaling properly
    if (_preserveZoomOnLayout) {
        const CGFloat fit = _pdfView.scaleFactorForSizeToFit;
        if (isfinite(fit) && fit > 0.0) {
            _pdfView.minScaleFactor = fit;
            _pdfView.scaleFactor = fit;
            _didApplyInitialFit = true;
        }
    } else {
        _pdfView.minScaleFactor = _pdfView.scaleFactorForSizeToFit;
        _pdfView.scaleFactor = _pdfView.scaleFactorForSizeToFit;
    }

    // 🔥 Restore page safely
    if (currentIndex < [newDocument pageCount]) {
        [_pdfView goToPage:[newDocument pageAtIndex:currentIndex]];
    }

    result(@(YES));
}

- (void)clearTextSelection:(FlutterResult)result {
    // PDFKit keeps the long-press selection until it is explicitly cleared.
    // Clear it before the Flutter layer toggles fullscreen/app-bar chrome.
    _pdfView.currentSelection = nil;
    result(nil);
}

- (void)getZoomState:(FlutterResult)result {
    result(@{@"zoom": @(_pdfView.scaleFactor),
             @"minZoom": @(_pdfView.minScaleFactor),
             @"maxZoom": @(_pdfView.maxScaleFactor)});
}

- (void)getPageCount:(FlutterMethodCall *)call result:(FlutterResult)result {
    _pageCount = [NSNumber numberWithUnsignedLong:[[_pdfView document] pageCount]];
    result(_pageCount);
}

- (void)getCurrentPage:(FlutterMethodCall *)call result:(FlutterResult)result {
    PDFDocument *document = _pdfView.document;
    PDFPage *page = _pdfView.currentPage;
    const NSUInteger index = document != nil && page != nil
        ? [document indexForPage:page] : NSNotFound;
    if (index == NSNotFound || index >= document.pageCount) {
        result(nil);
        return;
    }
    _currentPage = @(index);
    result(_currentPage);
}

- (void)setPage:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSDictionary < NSString * , NSNumber * > *arguments = [call arguments];
    NSNumber *page = arguments[@"page"];
    PDFDocument *document = _pdfView.document;
    if (![page isKindOfClass:[NSNumber class]] || document == nil ||
        page.integerValue < 0 || (NSUInteger)page.integerValue >= document.pageCount) {
        NSLog(@"[PDF_PAGE] rejected index=%@ count=%lu", page, (unsigned long)document.pageCount);
        result(@(NO));
        return;
    }
    PDFPage *destination = [document pageAtIndex:(NSUInteger)page.integerValue];
    if (destination == nil) {
        result(@(NO));
        return;
    }
    [_pdfView goToPage:destination];
    result(@(YES));
}

- (void)onUpdateSettings:(FlutterMethodCall *)call result:(FlutterResult)result {
    // ✅ allow runtime updates of preventLinkNavigation
    NSDictionary *args = [call arguments];
    NSNumber *pln = args[@"preventLinkNavigation"];
    if ([pln isKindOfClass:[NSNumber class]]) {
        _preventLinkNavigation = [pln boolValue];
    }
    result(nil);
}

- (void)handlePageChanged:(NSNotification *)notification {
    PDFDocument *document = _pdfView.document;
    PDFPage *currentPage = _pdfView.currentPage;
    if (document == nil || currentPage == nil) return;

    if (_fitEachPage && _autoSpacing) {
        // PDFKit uses one scale for a continuous document. Recalculate the
        // fit scale when mixed-size merged pages become current, but only when
        // the user was already at the normal fit scale so manual zoom is kept.
        const CGFloat previousFit = _pdfView.minScaleFactor;
        const BOOL wasAtFit = _pdfView.scaleFactor <= previousFit * 1.05;
        dispatch_async(dispatch_get_main_queue(), ^{
            const CGFloat pageFit = self->_pdfView.scaleFactorForSizeToFit;
            if (pageFit <= 0) return;
            if (wasAtFit) {
                self->_pdfView.minScaleFactor = pageFit;
                self->_pdfView.scaleFactor = pageFit;
            }
        });
    }

    [_controller invokeChannelMethodFromView:self name:@"onPageChanged" arguments:@{
            @"page": [NSNumber numberWithUnsignedLong:[document indexForPage:currentPage]],
            @"total": [NSNumber numberWithUnsignedLong:[document pageCount]]}];
}

- (void)handleRenderCompleted:(NSNumber *)pages {
    [_controller invokeChannelMethodFromView:self name:@"onRender" arguments:@{@"pages": pages}];
}

// iOS 11+ (PDFKit)
- (void)pdfViewWillClickOnLink:(PDFView *)sender withURL:(NSURL *)url {
    if (!url) return;

    // Optional debug
    NSLog(@"[PDFKit] link tapped: %@", url.absoluteString);

    // If Flutter wants to handle it, forward and stop here.
    if (_preventLinkNavigation) {
        [_controller invokeChannelMethodFromView:self name:@"onLinkHandler" arguments:url.absoluteString];
        return;
    }

    // Otherwise let iOS open it (Safari / universal link target)
    if (@available(iOS 10.0, *)) {
        [[UIApplication sharedApplication] openURL:url
                                           options:@{}
                                 completionHandler:nil];
    } else {
        [[UIApplication sharedApplication] openURL:url];
    }
}


// Allow PDFKit's own recognizers + ours to both win
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    // Allow links / scroll / single-tap to coexist,
    // but keep double-tap exclusive to avoid "dueling zooms".
    if (g == _doubleTapGR || other == _doubleTapGR) return NO;
    return YES;
}


- (void)onDoubleTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded) return;

    const CGFloat fit = _pdfView.scaleFactorForSizeToFit;
    const CGFloat maxZ = _pdfView.maxScaleFactor;
    const CGFloat target = (_pdfView.scaleFactor < fit * 1.5) ? MIN(fit * 2.0, maxZ) : fit;

    CGPoint viewPt = [recognizer locationInView:_pdfView];
    PDFPage *page = [_pdfView pageForPoint:viewPt nearest:YES];
    if (!page) return;

    CGPoint pagePt = [_pdfView convertPoint:viewPt toPage:page];
    CGRect rect = [page boundsForBox:kPDFDisplayBoxMediaBox];
    CGFloat dx = rect.size.width  * 0.25f;
    CGFloat dy = rect.size.height * 0.25f;

    PDFDestination *dest = [[PDFDestination alloc] initWithPage:page
                                                        atPoint:CGPointMake(pagePt.x - dx, pagePt.y + dy)];

    [UIView animateWithDuration:0.2
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         self->_pdfView.scaleFactor = target;
                         [self->_pdfView goToDestination:dest];
                     } completion:nil];

}


- (void)handleTap:(UITapGestureRecognizer *)recognizer {
    // A tap dismisses an active PDFKit text selection before doing anything
    // else. Only a subsequent tap changes the editor's fullscreen state.
    if (_pdfView.currentSelection != nil) {
        [self clearTextSelection:^(id value) {}];
        return;
    }
    [_controller invokeChannelMethodFromView:self name:@"onTap" arguments:@{}];
}

@end
