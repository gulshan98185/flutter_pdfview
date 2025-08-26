import 'dart:io';

import 'package:flutter/services.dart';

Future<bool?> getPdfThumbNail(
    {required String pdfPath,
    required String destThumbPath,
    required int pageIndex,
    required int maxPixelDimension,
    required double quality,
    required bool useCropBox,
    required bool overwrite,
    required bool forceUpRight}) async {
  MethodChannel _channel = MethodChannel(Platform.isAndroid ? "Pdf_To_Image" : 'native_pdf_tools');
  return await _channel.invokeMethod('getPdfThumbNail', {
    'src': pdfPath,
    'pageIndex': pageIndex,
    'maxPixelDimension': maxPixelDimension,
    'destPath': destThumbPath,
    'quality': quality,
    'useCropBox': useCropBox,
    'overwrite': overwrite,
    'forceUpright': forceUpRight,
  });
}
