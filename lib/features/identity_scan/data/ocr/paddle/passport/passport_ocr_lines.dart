import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_line.dart';

/// Pure helpers that turn raw engine output into [PassportLine]s.
///
/// Kept free of engine imports so they can be unit tested without ONNX or
/// OpenCV.
class PassportOcrLines {
  PassportOcrLines._();

  /// The Paddle engine emits each row's boxes right to left, then a joined
  /// copy of the row that reuses the first box object. Dropping every item
  /// whose box object was already seen removes those joined copies.
  static List<T> dropJoinedRows<T>(List<T> items, Object Function(T) boxOf) {
    final seen = <Object>[];
    final kept = <T>[];
    for (final item in items) {
      final box = boxOf(item);
      if (seen.any((b) => identical(b, box))) continue;
      seen.add(box);
      kept.add(item);
    }
    return kept;
  }

  /// MRZ text from detector fragments: rows top to bottom, each row left to
  /// right, fragments joined without a separator (an MRZ line has no spaces).
  static String mrzText(List<PassportLine> fragments) {
    final sorted = [...fragments]..sort((a, b) => a.centerY.compareTo(b.centerY));
    final rows = <List<PassportLine>>[];
    for (final line in sorted) {
      final row = rows.isEmpty ? null : rows.last;
      if (row != null &&
          (line.centerY - row.first.centerY).abs() < row.first.height * 0.6) {
        row.add(line);
      } else {
        rows.add([line]);
      }
    }
    return rows
        .map((row) => (row..sort((a, b) => a.left.compareTo(b.left)))
            .map((l) => l.text.replaceAll(RegExp(r'\s+'), ''))
            .join())
        .join('\n');
  }

  static final _latinOrDigit = RegExp(r'[A-Za-z0-9]');

  static final _latinLetter = RegExp(r'[A-Za-z]');

  /// [primary] lines plus those [extra] lines that add something: no Arabic
  /// letters (the Latin engine garbles Arabic), some Latin text or digits,
  /// and not a duplicate of a primary line.
  ///
  /// An extra line that sits on top of a primary line with different letters
  /// is usually the same title read by the other engine; it is kept as an
  /// alternative reading ([PassportLine.alts]) of that primary line so a
  /// garbled title can still be recognised, but it never becomes a value.
  static List<PassportLine> mergeLatin(
    List<PassportLine> primary,
    List<PassportLine> extra,
  ) {
    String key(String s) => s.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final merged = [...primary];
    final alts = <int, List<String>>{};
    final texts = primary.map((l) => key(l.text)).toSet();
    for (final line in extra) {
      if (line.text.trim().isEmpty ||
          line.hasArabic ||
          !_latinOrDigit.hasMatch(line.text) ||
          texts.contains(key(line.text))) {
        continue;
      }

      var overlapped = -1;
      var best = 0.6;
      for (var i = 0; i < primary.length; i++) {
        final ratio = primary[i].overlapRatio(line);
        if (ratio > best) {
          best = ratio;
          overlapped = i;
        }
      }
      if (overlapped == -1) {
        texts.add(key(line.text));
        merged.add(line);
      } else if (_latinLetter.hasMatch(line.text)) {
        alts.putIfAbsent(overlapped, () => []).add(line.text.trim());
      }
    }
    for (final entry in alts.entries) {
      final original = merged[entry.key];
      merged[entry.key] = original.withAlts([...original.alts, ...entry.value]);
    }
    return merged;
  }

  /// Lines in reading order (top to bottom), as plain text. Debug aid.
  static String flat(List<PassportLine> lines) {
    final sorted = [...lines]
      ..sort((a, b) {
        final byRow = (a.centerY - b.centerY).abs() < a.height * 0.6
            ? 0
            : a.centerY.compareTo(b.centerY);
        return byRow != 0 ? byRow : b.right.compareTo(a.right);
      });
    return sorted.map((l) => l.text).join('\n');
  }
}
