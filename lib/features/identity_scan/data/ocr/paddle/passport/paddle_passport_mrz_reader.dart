import 'package:injectable/injectable.dart';
import 'package:mrz/features/identity_scan/data/image/image_ops.dart';
import 'package:mrz/features/identity_scan/data/mrz/mrz_parser.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/paddle_ocr_engine.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/mlkit_latin_reader.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_line.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_ocr_lines.dart';
import 'package:mrz/features/identity_scan/domain/document_kind.dart';
import 'package:mrz/features/identity_scan/domain/mrz_data.dart';
import 'package:opencv_dart/opencv.dart' as cv;

class PassportMrzRead {
  const PassportMrzRead({this.data, required this.attempts});

  final MrzData? data;

  /// One entry per OCR attempt, for debugging bad reads.
  final List<Map<String, dynamic>> attempts;
}

/// Finds and validates the passport MRZ without Tesseract.
///
/// Same strategy as the classic reader: progressively more focused reads,
/// stopping at the first whose check digits all pass, otherwise keeping the
/// one with the most passing checks. ML Kit goes first (it reads Latin text
/// reliably); Paddle is the last resort.
@lazySingleton
class PaddlePassportMrzReader {
  PaddlePassportMrzReader(this._mlkit, this._paddle, this._imageOps);

  static const _parser = MrzParser();
  static const _formats = [MrzFormat.td3];

  final MlKitLatinReader _mlkit;
  final PaddleOcrEngine _paddle;
  final ImageOps _imageOps;

  /// [page] is the already-read ML Kit result for [imagePath], to avoid
  /// running ML Kit on the full page twice.
  Future<PassportMrzRead> read(String imagePath, {MlKitPage? page}) async {
    final attempts = <Map<String, dynamic>>[];
    MrzData? best;

    bool consider(String source, String? text) {
      final parsed = text == null ? null : _parser.parseText(text, formats: _formats);
      attempts.add({
        'source': source,
        'text': text,
        'passedChecks': parsed?.passedChecks,
      });
      if (parsed != null && (best == null || parsed.passedChecks > best!.passedChecks)) {
        best = parsed;
      }
      return best?.isValid ?? false;
    }

    PassportMrzRead result() => PassportMrzRead(data: best, attempts: attempts);

    final fullPage = page ?? await _mlkit.read(imagePath);
    if (consider('mlkit/full', fullPage?.text)) return result();

    final bandPath = await _imageOps.crop(
      imagePath,
      top: 1 - DocumentKind.passport.mrzBandFraction,
      minWidth: 1800,
      label: 'passport_mrz_band',
    );
    String? enhancedPath;
    try {
      if (consider('mlkit/band', (await _mlkit.read(bandPath))?.text)) return result();

      enhancedPath = await _enhance(bandPath);
      if (enhancedPath != null &&
          consider('mlkit/band-enhanced', (await _mlkit.read(enhancedPath))?.text)) {
        return result();
      }

      if (consider('paddle/band', await _paddleText(bandPath))) return result();
      if (enhancedPath != null) {
        consider('paddle/band-enhanced', await _paddleText(enhancedPath));
      }
    } finally {
      await _imageOps.deleteTemp(bandPath);
      if (enhancedPath != null) await _imageOps.deleteTemp(enhancedPath);
    }
    return result();
  }

  /// Paddle's detector may split an MRZ line at its `<` runs, so the fragments
  /// are put back together left to right.
  Future<String?> _paddleText(String imagePath) async {
    try {
      final result = await _paddle.recognize(imagePath);
      final unique = PassportOcrLines.dropJoinedRows(result.lines, (l) => l.box);
      final lines = [
        for (final l in unique)
          PassportLine(
            l.text,
            l.box.left,
            l.box.top,
            l.box.right,
            l.box.bottom,
            confidence: l.confidence,
          ),
      ];
      final text = PassportOcrLines.mrzText(lines);
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// Greyscale + contrast-limited histogram equalisation, written next to the
  /// band. Returns null when the image cannot be processed.
  Future<String?> _enhance(String bandPath) async {
    final image = cv.imread(bandPath);
    if (image.isEmpty) {
      image.dispose();
      return null;
    }
    final outputPath = bandPath.replaceFirst(RegExp(r'\.png$'), '_enh.png');
    final gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
    final clahe = cv.CLAHE(2.0, (8, 8));
    final equalised = clahe.apply(gray);
    try {
      return await cv.imwriteAsync(outputPath, equalised) ? outputPath : null;
    } finally {
      for (final m in [image, gray, equalised]) {
        m.dispose();
      }
      clahe.dispose();
    }
  }
}
