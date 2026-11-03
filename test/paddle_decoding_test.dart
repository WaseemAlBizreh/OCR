import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/data/ocr/paddle/ctc_decoder.dart';
import 'package:idlens/src/data/ocr/paddle/rtl_reorder.dart';

List<double> _step(int classes, int hot, [double p = 0.9]) => [
  for (var i = 0; i < classes; i++) i == hot ? p : 0.01,
];

/// The steps flattened the way the recognizer returns them.
Float32List _flat(List<List<double>> steps) =>
    Float32List.fromList([for (final step in steps) ...step]);

void main() {
  group('CtcDecoder', () {
    const decoder = CtcDecoder(['a', 'b', 'c']);

    test('collapses repeats and drops blanks', () {
      // blank, a, a, blank, a, b, b, c
      final logits = [
        _step(4, 0),
        _step(4, 1),
        _step(4, 1),
        _step(4, 0),
        _step(4, 1),
        _step(4, 2),
        _step(4, 2),
        _step(4, 3),
      ];
      final r = decoder.greedy(_flat(logits), classes: 4);
      expect(r.text, 'aabc');
      // 0.9 stored as a 32-bit float, as the recognizer returns it.
      expect(r.confidence, closeTo(0.9, 1e-6));
    });

    test('all blanks decode to empty text with zero confidence', () {
      final r = decoder.greedy(_flat([_step(4, 0), _step(4, 0)]), classes: 4);
      expect(r.text, '');
      expect(r.confidence, 0);
    });

    test('ignores class indexes outside the dictionary', () {
      expect(decoder.greedy(_flat([_step(6, 5)]), classes: 6).text, '');
    });
  });

  group('RtlReorder', () {
    test('leaves Latin-only lines alone', () {
      expect(RtlReorder.fix('OSMAN MERGHANI'), 'OSMAN MERGHANI');
    });

    test('reverses a visual Arabic word into logical order', () {
      // Visual (left to right on the image): مالس  ->  logical: سلام
      expect(RtlReorder.fix('مالس'), 'سلام');
    });

    test('keeps digit runs readable inside Arabic text', () {
      // Visual order of "تاريخ 1992-09-23" laid out right-to-left.
      const visual = '1992-09-23 خيرات';
      expect(RtlReorder.fix(visual), 'تاريخ 1992-09-23');
    });

    test('keeps an Arabic mark attached to its letter', () {
      // "بَ" visual order is the same single cluster.
      expect(RtlReorder.fix('بَا'), 'ابَ');
    });
  });
}
