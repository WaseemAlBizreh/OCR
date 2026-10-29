import 'dart:math' as math;

/// One OCR text line with its position in the photo (pixels).
///
/// Both ML Kit and Paddle are converted to this type, so the passport parser
/// does not depend on either engine.
class PassportLine {
  const PassportLine(
    this.text,
    this.left,
    this.top,
    this.right,
    this.bottom, {
    this.confidence = 1,
    this.alts = const [],
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double confidence;

  /// Other engines' readings of the same spot. Used only to recognise a label
  /// whose main reading is garbled (Paddle may mangle an English title that
  /// ML Kit reads well, and the other way round for Arabic); never as a value.
  final List<String> alts;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  static final _arabic = RegExp(r'[؀-ۿ]');
  bool get hasArabic => _arabic.hasMatch(text);

  PassportLine withText(String value) => PassportLine(
        value,
        left,
        top,
        right,
        bottom,
        confidence: confidence,
        alts: alts,
      );

  PassportLine withAlts(List<String> value) => PassportLine(
        text,
        left,
        top,
        right,
        bottom,
        confidence: confidence,
        alts: value,
      );

  /// Overlapping area as a fraction of the smaller line's area; 1 means one
  /// line sits entirely inside the other. Used to drop duplicate reads.
  double overlapRatio(PassportLine other) {
    final w = math.min(right, other.right) - math.max(left, other.left);
    final h = math.min(bottom, other.bottom) - math.max(top, other.top);
    if (w <= 0 || h <= 0) return 0;
    final smaller = math.min(width * height, other.width * other.height);
    return smaller <= 0 ? 0 : (w * h) / smaller;
  }

  /// Shared width as a fraction of the narrower line (0 when they do not
  /// overlap horizontally).
  double columnOverlap(PassportLine other) {
    final w = math.min(right, other.right) - math.max(left, other.left);
    final narrower = math.min(width, other.width);
    return w <= 0 || narrower <= 0 ? 0 : w / narrower;
  }

  @override
  String toString() => 'PassportLine("$text", $left, $top, $right, $bottom)';
}
