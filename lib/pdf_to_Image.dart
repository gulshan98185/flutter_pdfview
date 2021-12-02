import 'dart:io';

import 'package:flutter/services.dart';

Future<List<String>> convertPdfToImageUsingNative(
  String pdfFilePath,
  String destFolderPath,
  String password,
  int maxSize,
  int compressValue,
) async {
   MethodChannel _channel =   MethodChannel(Platform.isAndroid?"Pdf_To_Image":'native_pdf_tools');

  return await _channel.invokeListMethod('PdfToImage', {
    'pdfFilePath': pdfFilePath,
    'destFolderPath': destFolderPath,
    'password': password,
    'maxSize': maxSize,
    'compressValue': compressValue,
  });
}
