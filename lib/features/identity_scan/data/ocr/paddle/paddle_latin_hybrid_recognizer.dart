import 'package:mrz/features/identity_scan/data/ocr/card_text_recognizer.dart';
import 'package:mrz/features/identity_scan/data/ocr/ocr_engine.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/paddle_ocr_engine.dart';

/// Paddle reads the Arabic; ML Kit (Latin) reads the Latin text and digits.
///
/// The Arabic recognizer often drops values printed in Latin digits next to an
/// Arabic label (dates, blood type), while ML Kit reads them reliably. Only
/// ML Kit lines with no Arabic letters are added, so its garbled attempts at
/// Arabic never reach the parser.
class PaddleLatinHybridRecognizer implements CardTextRecognizer {
  PaddleLatinHybridRecognizer(this._paddle, this._latin);

  final PaddleOcrEngine _paddle;
  final OcrEngine _latin;

  static final _arabic = RegExp(r'[؀-ۿ]');
  static final _latinOrDigit = RegExp(r'[A-Za-z0-9]');

  @override
  Future<String> recognizeCardText(String imagePath) async {
    final paddle = await _paddle.recognizeCardText(imagePath);
    final latin = await _latin.recognizeLatin(imagePath) ?? '';

    final lines = paddle.split('\n');
    final seen = lines.map((l) => l.trim()).toSet();
    for (final line in latin.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          _arabic.hasMatch(trimmed) ||
          !_latinOrDigit.hasMatch(trimmed) ||
          !seen.add(trimmed)) {
        continue;
      }
      lines.add(trimmed);
    }
    return lines.join('\n');
  }
}
