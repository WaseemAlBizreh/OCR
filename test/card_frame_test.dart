import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/presentation/widgets/card_frame_overlay.dart';

void main() {
  // Portrait previews: 3:4 (most phones' photo shape) and 9:16.
  const previews = [Size(390, 520), Size(390, 693)];

  for (final preview in previews) {
    for (final kind in DocumentKind.values) {
      test('${kind.name} in $preview leaves the capture margin inside', () {
        final frame = CardFrame.centered(
          previewSize: preview,
          aspectRatio: kind.aspectRatio,
        );
        // The frame keeps the document's shape.
        final rect = frame.toRect(preview);
        expect(rect.width / rect.height, closeTo(kind.aspectRatio, 1e-6));

        // The wider crop is never clamped, so every side keeps its margin.
        final crop = frame.expanded(CardFrame.captureMargin);
        final dx = (frame.right - frame.left) * CardFrame.captureMargin;
        final dy = (frame.bottom - frame.top) * CardFrame.captureMargin;
        expect(crop.left, closeTo(frame.left - dx, 1e-9));
        expect(crop.right, closeTo(frame.right + dx, 1e-9));
        expect(crop.top, closeTo(frame.top - dy, 1e-9));
        expect(crop.bottom, closeTo(frame.bottom + dy, 1e-9));
        expect(crop.left, greaterThan(0));
        expect(crop.top, greaterThan(0));
        expect(crop.right, lessThan(1));
        expect(crop.bottom, lessThan(1));
      });
    }
  }
}
