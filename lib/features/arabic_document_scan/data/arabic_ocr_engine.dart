import 'dart:io';

import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:injectable/injectable.dart';
import 'package:mrz/features/arabic_document_scan/data/parsers/parser_utils.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';

/// On-device OCR for Arabic documents.
///
/// Uses Tesseract (ara+eng) as the primary engine for Arabic script and ML Kit
/// Latin as a supplement for English names, numbers, and MRZ-like text.
///
@lazySingleton
class ArabicOcrEngine {
  TextRecognizer? _latinRecognizer;

  Future<OcrEngineComparison> compareEngines(String imagePath) async {
    final mlKitStopwatch = Stopwatch()..start();
    final mlKitText = await _recognizeWithMlKit(imagePath);
    mlKitStopwatch.stop();

    final tesseractStopwatch = Stopwatch()..start();
    final tesseractText = await _recognizeWithTesseract(imagePath);
    tesseractStopwatch.stop();

    return OcrEngineComparison(
      mlKitText: mlKitText,
      tesseractText: tesseractText,
      mlKitDurationMs: mlKitStopwatch.elapsedMilliseconds,
      tesseractDurationMs: tesseractStopwatch.elapsedMilliseconds,
    );
  }

  /// Best-effort merged OCR text for Arabic ID parsing.
  String? mergeForArabicParsing(OcrEngineComparison comparison) {
    final tesseract = comparison.tesseractText?.trim();
    final cleanedTesseract =
        tesseract != null ? _cleanupTesseractText(tesseract) : null;
    final mlKit = comparison.mlKitText?.trim();

    if (cleanedTesseract != null && cleanedTesseract.isNotEmpty) {
      if (mlKit == null || mlKit.isEmpty) return cleanedTesseract;
      return _mergeUniqueLines(cleanedTesseract, mlKit);
    }
    return mlKit;
  }

  Future<String?> _recognizeWithMlKit(String imagePath) async {
    try {
      _latinRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(imagePath);
      final result = await _latinRecognizer!.processImage(inputImage);
      final text = result.text.trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _recognizeWithTesseract(String imagePath) async {
    try {
      if (!await File(imagePath).exists()) return null;

      final merged = <String>[];
      for (final psm in const ['6', '11', '3']) {
        final text = await _recognizeWithTesseractPsm(imagePath, psm);
        if (text != null && text.isNotEmpty) {
          merged.add(text);
        }
      }

      if (merged.isEmpty) return null;

      var result = merged.first;
      for (var i = 1; i < merged.length; i++) {
        result = _mergeUniqueLines(result, merged[i]);
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Fast Tesseract-only check to compare preprocessing variants.
  Future<int> estimateOcrQuality(String imagePath) async {
    final text = await _recognizeWithTesseractPsm(imagePath, '6');
    if (text == null || text.isEmpty) return 0;
    return _cleanupTesseractText(text).length;
  }

  Future<String?> _recognizeWithTesseractPsm(String imagePath, String psm) async {
    try {
      final text = await FlutterTesseractOcr.extractText(
        imagePath,
        language: 'ara+eng',
        args: {
          'psm': psm,
          'oem': '1',
          'preserve_interword_spaces': '1',
        },
      );
      final trimmed = text.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  String _cleanupTesseractText(String text) {
    return ParserUtils.rawLines(text)
        .map(ParserUtils.normalizeArabic)
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  String _mergeUniqueLines(String primary, String secondary) {
    final lines = <String>{
      ...primary
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty),
      ...secondary
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty),
    };
    return lines.join('\n');
  }

  Future<void> dispose() async {
    await _latinRecognizer?.close();
    _latinRecognizer = null;
  }
}
