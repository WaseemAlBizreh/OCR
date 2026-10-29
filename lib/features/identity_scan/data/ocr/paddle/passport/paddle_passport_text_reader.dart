import 'package:injectable/injectable.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/paddle_ocr_engine.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/mlkit_latin_reader.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_line.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_ocr_lines.dart';

class PassportText {
  const PassportText(this.lines);

  final List<PassportLine> lines;

  /// Reading-order text of [lines]; a debug aid shown as the raw OCR.
  String get flat => PassportOcrLines.flat(lines);
}

/// Text lines of a passport data page with their positions.
///
/// Paddle reads everything (Arabic and Latin); ML Kit Latin lines are added
/// where Paddle missed Latin text or digits (it often drops values printed
/// next to an Arabic label). ML Kit lines with Arabic letters are ignored: it
/// cannot read Arabic.
@lazySingleton
class PaddlePassportTextReader {
  PaddlePassportTextReader(this._paddle, this._mlkit);

  final PaddleOcrEngine _paddle;
  final MlKitLatinReader _mlkit;

  /// [mlkit] is the already-read ML Kit result for [imagePath].
  Future<PassportText> read(String imagePath, {MlKitPage? mlkit}) async {
    final result = await _paddle.recognize(imagePath);
    final unique = PassportOcrLines.dropJoinedRows(result.lines, (l) => l.box);
    final paddle = [
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
    final page = mlkit ?? await _mlkit.read(imagePath);
    return PassportText(PassportOcrLines.mergeLatin(paddle, page?.lines ?? const []));
  }
}
