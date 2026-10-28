import 'package:injectable/injectable.dart';
import 'package:mrz/features/identity_scan/data/image/image_ops.dart';
import 'package:mrz/features/identity_scan/data/mrz/mrz_parser.dart';
import 'package:mrz/features/identity_scan/data/ocr/ocr_engine.dart';
import 'package:mrz/features/identity_scan/domain/document_kind.dart';
import 'package:mrz/features/identity_scan/domain/mrz_data.dart';

class MrzReadResult {
  const MrzReadResult({this.data, required this.attempts});

  final MrzData? data;

  /// One entry per OCR attempt, for debugging bad reads.
  final List<Map<String, dynamic>> attempts;
}

/// Finds and validates the MRZ in a document image.
///
/// Tries progressively more focused reads and stops at the first one whose
/// check digits all pass; otherwise it returns the read with the most passing
/// checks, so a near miss is still visible to the caller.
@lazySingleton
class MrzReader {
  MrzReader(this._ocr, this._imageOps);

  static const _parser = MrzParser();

  final OcrEngine _ocr;
  final ImageOps _imageOps;

  Future<MrzReadResult> read(String imagePath, DocumentKind kind) async {
    final formats = switch (kind) {
      DocumentKind.sudanId => [MrzFormat.td1],
      DocumentKind.passport => [MrzFormat.td3],
    };
    final attempts = <Map<String, dynamic>>[];
    MrzData? best;

    bool consider(String source, String? text) {
      final parsed = text == null
          ? null
          : _parser.parseText(text, formats: formats);
      attempts.add({
        'source': source,
        'text': text,
        'passedChecks': parsed?.passedChecks,
      });
      if (parsed != null &&
          (best == null || parsed.passedChecks > best!.passedChecks)) {
        best = parsed;
      }
      return best?.isValid ?? false;
    }

    if (consider('mlkit/full', await _ocr.recognizeLatin(imagePath))) {
      return MrzReadResult(data: best, attempts: attempts);
    }

    final bandPath = await _imageOps.crop(
      imagePath,
      top: 1 - kind.mrzBandFraction,
      minWidth: 1800,
      label: 'mrz_band',
    );
    try {
      if (consider('mlkit/band', await _ocr.recognizeLatin(bandPath)) ||
          consider(
            'tesseract/band',
            await _ocr.recognizeMrzWithTesseract(bandPath),
          )) {
        return MrzReadResult(data: best, attempts: attempts);
      }
    } finally {
      await _imageOps.deleteTemp(bandPath);
    }

    consider(
      'tesseract/full',
      await _ocr.recognizeMrzWithTesseract(imagePath),
    );
    return MrzReadResult(data: best, attempts: attempts);
  }
}
