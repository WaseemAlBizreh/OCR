import 'dart:math' as math;

import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_labels.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_line.dart';

/// Finds where the value of a label sits, from line positions alone.
///
/// Data pages differ a lot: `label  value` on one row, a label row with the
/// values in the row below, mirrored Arabic rows with the value to the left of
/// its label. The geometry covers all of them without knowing the layout.
class PassportLayout {
  PassportLayout._();

  /// Two lines are on one row when their centres differ by less than this
  /// fraction of the taller line.
  static const _rowTolerance = 0.6;

  /// A value below its label starts within this many label heights.
  static const _maxBelowGap = 2.5;

  /// Minimum shared width (fraction of the narrower line) for "same column".
  static const _minColumnOverlap = 0.3;

  /// Candidate value lines for [label], best first:
  /// 1. same row, on the side values normally sit (right of a Latin label, left
  ///    of an Arabic one), nearest first;
  /// 2. same row, the other side;
  /// 3. below the label in the same column, nearest first.
  ///
  /// [labelLines] are lines that are labels themselves; they are never values
  /// and they block a candidate that lies behind them.
  ///
  /// [labelFields] says which field each label line is for. In a stacked
  /// layout (a row of titles with the values in the row below) the next title
  /// along the row follows this one directly, with no value between them; the
  /// same-row neighbours are then not values and only the row below is used.
  /// A title's twin in the other language (same field) does not count.
  static List<PassportLine> valueCandidates(
    PassportLine label,
    Iterable<PassportLine> all,
    Set<PassportLine> labelLines, {
    Map<PassportLine, PassportField> labelFields = const {},
  }) {
    final preferRight = !label.hasArabic;
    final stacked = _stackedAhead(label, preferRight, all, labelLines, labelFields);
    final preferred = <PassportLine>[];
    final otherSide = <PassportLine>[];
    final below = <PassportLine>[];

    for (final other in all) {
      if (identical(other, label) || labelLines.contains(other)) continue;
      if (_sameRow(label, other)) {
        if (stacked) continue;
        if (label.columnOverlap(other) > 0.6) continue; // a duplicate read
        if (_blockedOnRow(label, other, all, labelLines)) continue;
        final isRight = other.centerX > label.centerX;
        (isRight == preferRight ? preferred : otherSide).add(other);
      } else if (_isBelow(label, other) && !_blockedBelow(label, other, all, labelLines)) {
        below.add(other);
      }
    }

    int byGap(PassportLine a, PassportLine b) =>
        _gap(label, a).compareTo(_gap(label, b));
    int byDrop(PassportLine a, PassportLine b) =>
        (a.top - label.bottom).compareTo(b.top - label.bottom);
    return [
      ...preferred..sort(byGap),
      ...otherSide..sort(byGap),
      ...below..sort(byDrop),
    ];
  }

  /// The next title (of another field) in the direction values are expected
  /// follows [label] directly, with no non-title line between them.
  static bool _stackedAhead(
    PassportLine label,
    bool toRight,
    Iterable<PassportLine> all,
    Set<PassportLine> labelLines,
    Map<PassportLine, PassportField> labelFields,
  ) {
    PassportLine? next;
    for (final m in all) {
      if (identical(m, label) || !labelLines.contains(m) || !_sameRow(label, m)) continue;
      final field = labelFields[m];
      if (field != null && field == labelFields[label]) continue; // twin
      final ahead = toRight ? m.centerX > label.centerX : m.centerX < label.centerX;
      if (!ahead) continue;
      if (next == null || (m.centerX - label.centerX).abs() < (next.centerX - label.centerX).abs()) {
        next = m;
      }
    }
    if (next == null) return false;
    final low = math.min(label.centerX, next.centerX);
    final high = math.max(label.centerX, next.centerX);
    return !all.any((v) =>
        !identical(v, label) &&
        !identical(v, next) &&
        !labelLines.contains(v) &&
        _sameRow(label, v) &&
        v.centerX > low &&
        v.centerX < high);
  }

  static bool _sameRow(PassportLine a, PassportLine b) =>
      (a.centerY - b.centerY).abs() < _rowTolerance * math.max(a.height, b.height);

  static double _gap(PassportLine a, PassportLine b) {
    if (b.left >= a.right) return b.left - a.right;
    if (a.left >= b.right) return a.left - b.right;
    return 0;
  }

  /// Another label sits between [label] and [other] on the same row.
  static bool _blockedOnRow(
    PassportLine label,
    PassportLine other,
    Iterable<PassportLine> all,
    Set<PassportLine> labelLines,
  ) {
    final low = math.min(label.centerX, other.centerX);
    final high = math.max(label.centerX, other.centerX);
    return all.any((m) =>
        !identical(m, label) &&
        labelLines.contains(m) &&
        _sameRow(label, m) &&
        m.centerX > low &&
        m.centerX < high);
  }

  static bool _isBelow(PassportLine label, PassportLine other) =>
      other.top >= label.bottom - 0.3 * label.height &&
      other.top - label.bottom <= _maxBelowGap * label.height &&
      !_sameRow(label, other) &&
      label.columnOverlap(other) >= _minColumnOverlap;

  /// Another label sits between [label] and [other] in the same column.
  static bool _blockedBelow(
    PassportLine label,
    PassportLine other,
    Iterable<PassportLine> all,
    Set<PassportLine> labelLines,
  ) {
    return all.any((m) =>
        !identical(m, label) &&
        labelLines.contains(m) &&
        m.top >= label.bottom - 0.3 * label.height &&
        m.bottom <= other.top + 0.3 * other.height &&
        label.columnOverlap(m) >= _minColumnOverlap);
  }
}
