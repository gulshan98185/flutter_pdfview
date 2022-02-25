import 'dart:io';

import 'package:flutter/services.dart';

Future<bool?> getPdfThumbNail(String pdfFilePath, String destThumbPath) async {
  MethodChannel _channel = MethodChannel(Platform.isAndroid ? "Pdf_To_Image" : 'native_pdf_tools');
  return await _channel.invokeMethod('getPdfThumbNail', {
    'pdfFilePath': pdfFilePath,
    'destThumbPath': destThumbPath,
  });
}
