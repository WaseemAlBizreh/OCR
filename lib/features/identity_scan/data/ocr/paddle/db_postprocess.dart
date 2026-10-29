import 'dart:typed_data';

/// An axis-aligned text-line box, in the coordinates of whatever map or image
/// it was computed on.
class TextBox {
  const TextBox(this.left, this.top, this.right, this.bottom, this.score);

  final double left;
  final double top;
  final double right;
  final double bottom;
  final double score;

  double get width => right - left;
  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;

  TextBox scaled(double sx, double sy) =>
      TextBox(left * sx, top * sy, right * sx, bottom * sy, score);

  @override
  String toString() => 'TextBox($left, $top, $right, $bottom, score: $score)';
}

/// Turns the DB detector's probability map into text-line boxes.
///
/// Same steps as PaddleOCR's DBPostProcess, simplified to axis-aligned boxes
/// (the capture screen frames the card upright): threshold, connected
/// components, drop weak or tiny ones, then expand each box by the DB
/// "unclip" distance.
class DbPostProcess {
  const DbPostProcess({
    this.threshold = 0.3,
    this.boxThreshold = 0.6,
    this.unclipRatio = 0.7,
    this.minSize = 3,
    this.maxCandidates = 1000,
  });

  final double threshold;
  final double boxThreshold;
  /// PaddleOCR's default is 1.5, but at the text size of a phone photo of an ID
  /// card that makes the phone row's box twice the text height, spilling into
  /// the address line and costing digits. 0.7 read the whole number correctly.
  final double unclipRatio;
  final int minSize;
  final int maxCandidates;

  /// [map] is a row-major `height x width` probability map.
  List<TextBox> boxes(Float32List map, int width, int height) {
    assert(map.length == width * height);
    final visited = Uint8List(map.length);
    final stack = Int32List(map.length);
    final result = <TextBox>[];

    for (var start = 0; start < map.length; start++) {
      if (visited[start] == 1 || map[start] <= threshold) continue;

      var sp = 0;
      stack[sp++] = start;
      visited[start] = 1;
      var minX = width, minY = height, maxX = 0, maxY = 0;
      var sum = 0.0;
      var count = 0;

      while (sp > 0) {
        final p = stack[--sp];
        final x = p % width;
        final y = p ~/ width;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        sum += map[p];
        count++;

        // 4-connected neighbours.
        if (x > 0) sp = _push(map, visited, stack, sp, p - 1);
        if (x < width - 1) sp = _push(map, visited, stack, sp, p + 1);
        if (y > 0) sp = _push(map, visited, stack, sp, p - width);
        if (y < height - 1) sp = _push(map, visited, stack, sp, p + width);
      }

      final w = maxX - minX + 1;
      final h = maxY - minY + 1;
      if (w < minSize || h < minSize) continue;
      final score = sum / count;
      if (score < boxThreshold) continue;

      // DB unclip: distance = area * ratio / perimeter.
      final distance = (w * h * unclipRatio) / (2 * (w + h));
      result.add(TextBox(
        (minX - distance).clamp(0, width - 1).toDouble(),
        (minY - distance).clamp(0, height - 1).toDouble(),
        (maxX + 1 + distance).clamp(1, width).toDouble(),
        (maxY + 1 + distance).clamp(1, height).toDouble(),
        score,
      ));
      if (result.length >= maxCandidates) break;
    }
    return result;
  }

  int _push(Float32List map, Uint8List visited, Int32List stack, int sp, int p) {
    if (visited[p] == 0 && map[p] > threshold) {
      visited[p] = 1;
      stack[sp++] = p;
    }
    return sp;
  }
}
