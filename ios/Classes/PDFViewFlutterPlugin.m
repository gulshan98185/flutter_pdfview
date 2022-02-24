#import "PDFViewFlutterPlugin.h"
#import "FlutterPDFView.h"
#import <flutter_pdfview/flutter_pdfview-Swift.h>

 
@implementation FLTPDFViewFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FLTPDFViewFactory* pdfViewFactory = [[FLTPDFViewFactory alloc] initWithMessenger:registrar.messenger];
    [registrar registerViewFactory:pdfViewFactory withId:@"plugins.endigo.io/pdfview"];
   
}
@end
