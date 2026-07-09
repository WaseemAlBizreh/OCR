import 'package:flutter/foundation.dart';

void logRawOcrBeforeParsing({
  required String context,
  String? mergedText,
  String? tesseractText,
  String? mlKitText,
}) {
  debugPrint('');
  debugPrint('========== OCR RAW [$context] ==========');
  debugPrint('Tesseract (${tesseractText?.length ?? 0} chars):');
  debugPrint(tesseractText?.isNotEmpty == true ? tesseractText! : '(empty)');
  debugPrint('ML Kit (${mlKitText?.length ?? 0} chars):');
  debugPrint(mlKitText?.isNotEmpty == true ? mlKitText! : '(empty)');
  debugPrint('--- Merged text sent to parser (${mergedText?.length ?? 0} chars) ---');
  debugPrint(mergedText?.isNotEmpty == true ? mergedText! : '(empty)');
  debugPrint('========================================');
  debugPrint('');
}
