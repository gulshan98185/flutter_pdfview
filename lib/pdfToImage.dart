import 'package:flutter/services.dart';

Future<List<String>> pdfToImage(
  String pdfFilePath,
  String destFolderPath,
  String password,
  int maxSize,
  int compressValue,
) async {
  MethodChannel _channel = const MethodChannel('Pdf_To_Image');
  return await _channel.invokeListMethod('PdfToImage', {
    'pdfFilePath': pdfFilePath,
    'destFolderPath': destFolderPath,
    'password': password,
    'maxSize': maxSize,
    'compressValue': compressValue,
  });
}
