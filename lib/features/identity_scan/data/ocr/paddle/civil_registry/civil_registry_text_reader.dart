import 'package:injectable/injectable.dart';
import 'package:mrz/features/identity_scan/data/front/parser_utils.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/paddle_ocr_engine.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/mlkit_latin_reader.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_line.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_ocr_lines.dart';

class CertificateText {
  const CertificateText(this.lines, {this.mlkitText = ''});

  final List<PassportLine> lines;

  /// What ML Kit read on its own, to tell which engine missed a value.
  final String mlkitText;

  /// Reading-order text of [lines]; a debug aid shown as the raw OCR.
  String get flat => PassportOcrLines.flat(lines);
}

/// Text lines of a certificate page with their positions.
///
/// Paddle reads everything at a higher detector resolution than a card needs,
/// because a full A4 page has small print. ML Kit Latin lines are added where
/// Paddle missed digits, and its reading of an Arabic label is kept as an
/// alternative so a garbled label can still be recognised.
@lazySingleton
class CivilRegistryTextReader {
  CivilRegistryTextReader(this._paddle, this._mlkit);

  /// Longest side the detector sees for an A4 page (cards use 960).
  static const detMaxSide = 1600;

  final PaddleOcrEngine _paddle;
  final MlKitLatinReader _mlkit;

  Future<CertificateText> read(String imagePath, {int maxSide = detMaxSide}) async {
    final result = await _paddle.recognize(imagePath, detMaxSide: maxSide);
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
    final page = await _mlkit.read(imagePath);
    final extra = page?.lines ?? const <PassportLine>[];
    return CertificateText(
      _addMissedDigits(PassportOcrLines.mergeLatin(paddle, extra), extra),
      mlkitText: page?.text ?? '',
    );
  }

  /// ML Kit's own text for [imagePath] (empty when it read nothing); used on
  /// small crops of one row.
  Future<String> readMlKitText(String imagePath) async =>
      (await _mlkit.read(imagePath))?.text ?? '';

  static final _nonDigit = RegExp(r'\D');

  static String _digitsOf(String text) =>
      ParserUtils.normalizeDigits(text).replaceAll(_nonDigit, '');

  /// Paddle drops digits printed next to Arabic text, often inside a box that
  /// also covers the label, and the shared merge discards an ML Kit line that
  /// overlaps a Paddle line. Keep every ML Kit line with digits that no line
  /// already holds; the parser reads it as the value of the label it sits in
  /// or beside.
  static List<PassportLine> _addMissedDigits(
    List<PassportLine> lines,
    List<PassportLine> mlkit,
  ) {
    final held = lines.map((l) => _digitsOf(l.text)).toList();
    final out = [...lines];
    for (final line in mlkit) {
      final digits = _digitsOf(line.text);
      if (digits.length < 4 || line.hasArabic) continue;
      if (held.any((h) => h.contains(digits))) continue;
      held.add(digits);
      out.add(line);
    }
    return out;
  }
}
