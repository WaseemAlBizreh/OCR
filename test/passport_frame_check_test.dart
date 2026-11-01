import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/data/ocr/paddle/passport/passport_frame_check.dart';
import 'package:idlens/src/data/ocr/paddle/passport/passport_line.dart';

PassportLine line(double l, double t, double r, double b) =>
    PassportLine('SOME TEXT', l, t, r, b);

void main() {
  // A 1000 x 700 photo.
  int sides(List<PassportLine> lines) =>
      PassportFrameCheck.touchedSides(lines, width: 1000, height: 700);

  test('a well-placed document leaves its text away from every edge', () {
    expect(sides([line(100, 80, 600, 110), line(90, 560, 900, 600)]), 0);
  });

  test('text clipped at the top and right edges touches two sides', () {
    expect(sides([line(300, 0, 600, 30), line(200, 560, 1000, 600)]), 2);
  });

  test('a document held slightly low touches only the bottom', () {
    expect(sides([line(100, 80, 600, 110), line(90, 670, 900, 700)]), 1);
  });

  test('tiny noise at an edge is ignored', () {
    expect(
      sides([
        PassportLine('ab', 0, 0, 5, 4),
        PassportLine('x', 995, 690, 1000, 700),
      ]),
      0,
    );
  });
}
