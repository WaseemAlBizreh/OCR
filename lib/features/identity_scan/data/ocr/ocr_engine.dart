import 'dart:io';

import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:injectable/injectable.dart';
import 'package:mrz/features/identity_scan/data/front/parser_utils.dart';
import 'package:mrz/features/identity_scan/data/ocr/card_text_recognizer.dart';

/// On-device OCR.
///
/// * ML Kit (Latin) reads Latin text, digits and MRZ lines.
/// * Tesseract `ara+eng` reads the Arabic fields on the card.
/// * Tesseract `eng` with an MRZ character whitelist is the MRZ fallback.
@lazySingleton
class OcrEngine implements CardTextRecognizer {
  static const _mrzWhitelist = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<';

  TextRecognizer? _latin;

  Future<String?> recognizeLatin(String imagePath) async {
    try {
      _latin ??= TextRecognizer(script: TextRecognitionScript.latin);
      final result =
          await _latin!.processImage(InputImage.fromFilePath(imagePath));
      final text = result.text.trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  Future<String?> recognizeMrzWithTesseract(String imagePath) {
    return _tesseract(
      imagePath,
      language: 'eng',
      psm: '6',
      extraArgs: {'tessedit_char_whitelist': _mrzWhitelist},
    );
  }

  /// Arabic + Latin text for the card fields: Tesseract (three page
  /// segmentation modes, merged) supplemented with ML Kit lines.
  @override
  Future<String> recognizeCardText(String imagePath) async {
    final tesseractParts = <String>[];
    for (final psm in const ['6', '11', '3']) {
      final text = await _tesseract(imagePath, language: 'ara+eng', psm: psm);
      if (text != null) tesseractParts.add(text);
    }
    final mlKit = await recognizeLatin(imagePath);

    final tesseract = tesseractParts.fold<String?>(
      null,
      (merged, text) => merged == null ? text : _mergeLines(merged, text),
    );
    final cleaned = tesseract == null
        ? null
        : ParserUtils.rawLines(tesseract)
            .map(ParserUtils.normalizeArabic)
            .where((line) => line.isNotEmpty)
            .join('\n');

    if (cleaned == null || cleaned.isEmpty) return mlKit ?? '';
    if (mlKit == null) return cleaned;
    return _mergeLines(cleaned, mlKit);
  }

  Future<String?> _tesseract(
    String imagePath, {
    required String language,
    required String psm,
    Map<String, String> extraArgs = const {},
  }) async {
    try {
      if (!await File(imagePath).exists()) return null;
      final text = await FlutterTesseractOcr.extractText(
        imagePath,
        language: language,
        args: {
          'psm': psm,
          'oem': '1',
          'preserve_interword_spaces': '1',
          ...extraArgs,
        },
      );
      final trimmed = text.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  String _mergeLines(String primary, String secondary) {
    final lines = <String>{
      for (final line in [...primary.split('\n'), ...secondary.split('\n')])
        if (line.trim().isNotEmpty) line.trim(),
    };
    return lines.join('\n');
  }

  Future<void> dispose() async {
    await _latin?.close();
    _latin = null;
  }
}
