// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#import "./include/flutter_pdfview/FlutterPDFView.h"

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
    int64_t _viewId;
    FlutterMethodChannel *_channel;
}

- (instancetype)initWithFrame:(CGRect)frame
               viewIdentifier:(int64_t)viewId
                    arguments:(id _Nullable)args
              binaryMessenger:(NSObject <FlutterBinaryMessenger> *)messenger {
    self = [super init];
    _pdfView = [[FLTPDFView new] initWithFrame:frame arguments:args controller:self];
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
    } else if ([[call method] isEqualToString:@"currentPage"]) {
        [_pdfView getCurrentPage:call result:result];
    } else if ([[call method] isEqualToString:@"setPage"]) {
        [_pdfView setPage:call result:result];
    } else if ([[call method] isEqualToString:@"updateSettings"]) {
        [_pdfView onUpdateSettings:call result:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)invokeChannelMethod:(NSString *)name arguments:(id)args {
    [_channel invokeMethod:name arguments:args];
}

- (UIView *)view {
    return _pdfView;
}

@end

@implementation FLTPDFView {
    FLTPDFViewController *__weak _controller;
    PDFView *_pdfView;
    NSNumber *_pageCount;
    NSNumber *_currentPage;
    PDFDestination *_currentDestination;
    BOOL _preventLinkNavigation;
    BOOL _autoSpacing;
    PDFPage *_defaultPage;
    BOOL _defaultPageSet;

    UITapGestureRecognizer *_singleTapGR;
    UITapGestureRecognizer *_doubleTapGR;
}

- (instancetype)initWithFrame:(CGRect)frame
                    arguments:(id _Nullable)args
                   controller:(nonnull FLTPDFViewController*)controller {
    _controller = controller;

    _pdfView = [[PDFView alloc] initWithFrame:frame];
    _pdfView.delegate = self;
    _pdfView.userInteractionEnabled = YES;

    _autoSpacing = [args[@"autoSpacing"] boolValue];
    BOOL pageFling = [args[@"pageFling"] boolValue];
    BOOL enableSwipe = [args[@"enableSwipe"] boolValue];
    _preventLinkNavigation = [args[@"preventLinkNavigation"] boolValue];

    NSInteger defaultPage = [args[@"defaultPage"] integerValue];

    NSString *filePath = args[@"filePath"];
    FlutterStandardTypedData *pdfData = args[@"pdfData"];

    PDFDocument *document;
    if ([filePath isKindOfClass:[NSString class]]) {
        NSURL *sourcePDFUrl = [NSURL fileURLWithPath:filePath];
        document = [[PDFDocument alloc] initWithURL:sourcePDFUrl];
    } else if ([pdfData isKindOfClass:[FlutterStandardTypedData class]]) {
        NSData *sourcePDFdata = [pdfData data];
        document = [[PDFDocument alloc] initWithData:sourcePDFdata];
    }

    if (document == nil) {
        [_controller invokeChannelMethod:@"onError" arguments:@{
                @"error": @"cannot create document: File not in PDF format or corrupted."}];
    } else {
        _pdfView.pageBreakMargins = UIEdgeInsetsMake(8, 16, 8, 16);
        _pdfView.autoresizesSubviews = YES;
        _pdfView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;;

        BOOL swipeHorizontal = [args[@"swipeHorizontal"] boolValue];
        _pdfView.displayDirection = swipeHorizontal ? kPDFDisplayDirectionHorizontal : kPDFDisplayDirectionVertical;

        _pdfView.autoScales = _autoSpacing;

        [_pdfView usePageViewController:pageFling withViewOptions:nil];
        _pdfView.displayMode = enableSwipe ? kPDFDisplaySinglePageContinuous : kPDFDisplaySinglePage;
        _pdfView.document = document;

        _pdfView.maxScaleFactor = [args[@"maxZoom"] doubleValue];
        _pdfView.minScaleFactor = _pdfView.scaleFactorForSizeToFit;

        NSString *password = args[@"password"];
        if ([password isKindOfClass:[NSString class]] && [_pdfView.document isEncrypted]) {
            [_pdfView.document unlockWithPassword:password];
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
        if (pageCount <= defaultPage) defaultPage = pageCount - 1;

        _defaultPage = [document pageAtIndex:defaultPage];
        __weak __typeof__(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handleRenderCompleted:[NSNumber numberWithUnsignedLong:[document pageCount]]];
        });
    }

    if (@available(iOS 11.0, *)) {
        UIScrollView *_scrollView;
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

- (void)layoutSubviews {
    [super layoutSubviews];
    _pdfView.frame = self.bounds;
    _pdfView.minScaleFactor = _pdfView.scaleFactorForSizeToFit;
    _pdfView.maxScaleFactor = 4.0;
    if (_autoSpacing) {
        _pdfView.scaleFactor = _pdfView.scaleFactorForSizeToFit;
    }

    if (!_defaultPageSet && _defaultPage != nil) {
        [_pdfView goToPage:_defaultPage];
        _defaultPageSet = true;
    }
}

- (UIView *)view {
    return _pdfView;
}

- (void)getPageCount:(FlutterMethodCall *)call result:(FlutterResult)result {
    _pageCount = [NSNumber numberWithUnsignedLong:[[_pdfView document] pageCount]];
    result(_pageCount);
}

- (void)getCurrentPage:(FlutterMethodCall *)call result:(FlutterResult)result {
    _currentPage = [NSNumber numberWithUnsignedLong:[_pdfView.document indexForPage:_pdfView.currentPage]];
    result(_currentPage);
}

- (void)setPage:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSDictionary < NSString * , NSNumber * > *arguments = [call arguments];
    NSNumber *page = arguments[@"page"];
    [_pdfView goToPage:[_pdfView.document pageAtIndex:page.unsignedLongValue]];
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
    [_controller invokeChannelMethod:@"onPageChanged" arguments:@{
            @"page": [NSNumber numberWithUnsignedLong:[_pdfView.document indexForPage:_pdfView.currentPage]],
            @"total": [NSNumber numberWithUnsignedLong:[_pdfView.document pageCount]]}];
}

- (void)handleRenderCompleted:(NSNumber *)pages {
    [_controller invokeChannelMethod:@"onRender" arguments:@{@"pages": pages}];
}

// iOS 11+ (PDFKit)
- (void)pdfViewWillClickOnLink:(PDFView *)sender withURL:(NSURL *)url {
    if (!url) return;

    // Optional debug
    NSLog(@"[PDFKit] link tapped: %@", url.absoluteString);

    // If Flutter wants to handle it, forward and stop here.
    if (_preventLinkNavigation) {
        [_controller invokeChannelMethod:@"onLinkHandler" arguments:url.absoluteString];
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
    [_controller invokeChannelMethod:@"onTap" arguments:@{}];
}

@end
