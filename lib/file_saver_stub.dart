import 'dart:typed_data';

import 'package:printing/printing.dart';

Future<void> saveGeneratedFile(
  String fileName,
  Uint8List bytes,
  String mimeType,
) => Printing.sharePdf(bytes: bytes, filename: fileName);
