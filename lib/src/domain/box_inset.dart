/// Where the guide box sits inside a camera crop, as fractions of the crop's
/// width (left, right) and height (top, bottom).
///
/// The crop is the box plus a strip of background (`CardFrame.captureMargin`),
/// and the app's preview shows only the box. What lies outside the box is not
/// what the user framed, so the checks that must match the user's view (the
/// MRZ lines) are made against it.
class BoxInset {
  const BoxInset({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// The box inside a crop made [margin] wider than it on every side and not
  /// cut short anywhere: `margin / (1 + 2 * margin)` from each edge.
  factory BoxInset.uniform(double margin) {
    final inset = margin / (1 + 2 * margin);
    return BoxInset(left: inset, top: inset, right: inset, bottom: inset);
  }

  final double left, top, right, bottom;

  Map<String, dynamic> toJson() => {
    'left': _round(left),
    'top': _round(top),
    'right': _round(right),
    'bottom': _round(bottom),
  };

  static double _round(double v) => double.parse(v.toStringAsFixed(4));
}
