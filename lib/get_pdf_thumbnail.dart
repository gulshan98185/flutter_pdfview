import 'package:flutter/services.dart';

Future<bool?> getPdfThumbNail(String pdfFilePath, String destThumbPath) async {
  MethodChannel _channel = const MethodChannel('Pdf_To_Image');
  return await _channel.invokeMethod('getPdfThumbNail', {
    'pdfFilePath': pdfFilePath,
    'destThumbPath': destThumbPath,
  });
}
