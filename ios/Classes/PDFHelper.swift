//
//  PDFHelper.swift
//  flutter_pdfview
//
//  Created by Rajat verma on 29/11/21.
//

import Foundation
@objc
class PDFHelper: NSObject{
    let call: FlutterMethodCall;
    let result: FlutterResult;
    
    init(call: FlutterMethodCall,result: @escaping FlutterResult){
        self.call=call;
        self.result=result;
        
        switch(call.method) {
        case "copy"  :
            
              break;
           
        default:
            self.result(FlutterMethodNotImplemented);
        }
     }
}
