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

  // Moved from the MTN app's document_frame_test.dart with the camera.

  test('a card frame is 86% of the preview width and centred', () {
    const preview = Size(400, 800);
    final rect = CardFrame.centered(
      previewSize: preview,
      aspectRatio: DocumentKind.sudanId.aspectRatio,
    ).toRect(preview);
    expect(rect.width, closeTo(344, 1e-6));
    expect(rect.height, closeTo(344 * 54 / 85.6, 1e-6));
    expect(rect.center.dx, closeTo(200, 1e-6));
    expect(rect.center.dy, closeTo(400, 1e-6));
  });

  test('an A4 frame on a short preview is limited by height', () {
    // A short screen leaves a short, wide preview.
    const preview = Size(400, 300);
    final rect = CardFrame.centered(
      previewSize: preview,
      aspectRatio: DocumentKind.civilRegistryCertificate.aspectRatio,
    ).toRect(preview);
    expect(rect.height, closeTo(300 * 0.86, 1e-6));
    expect(rect.width / rect.height, closeTo(210 / 297, 1e-6));
  });

  test('the frame is the same fraction of the preview at any size', () {
    final small = CardFrame.centered(
      previewSize: const Size(9 / 16, 1),
      aspectRatio: DocumentKind.passport.aspectRatio,
    );
    final large = CardFrame.centered(
      previewSize: const Size(1080, 1920),
      aspectRatio: DocumentKind.passport.aspectRatio,
    );
    expect(small.left, closeTo(large.left, 1e-9));
    expect(small.top, closeTo(large.top, 1e-9));
    expect(small.right, closeTo(large.right, 1e-9));
    expect(small.bottom, closeTo(large.bottom, 1e-9));
  });

  test('the MRZ guide sits along the bottom of the frame', () {
    const frame = Rect.fromLTWH(10, 100, 200, 100);
    final guide = CardFrame.mrzGuideRect(
      frame,
      DocumentKind.sudanId.mrzGuideFraction,
    );
    expect(guide.left, 18);
    expect(guide.right, 202);
    expect(guide.top, closeTo(166, 1e-9));
    expect(guide.bottom, 192);
    expect(DocumentKind.passport.mrzGuideFraction, 0.25);
    expect(DocumentKind.civilRegistryCertificate.hasMrz, isFalse);
  });

  test(
    'marginClipped is false for the guide boxes and true for a huge box',
    () {
      const preview = Size(400, 800);
      for (final kind in DocumentKind.values) {
        final frame = CardFrame.centered(
          previewSize: preview,
          aspectRatio: kind.aspectRatio,
        );
        expect(frame.marginClipped, isFalse, reason: kind.name);
      }
      // MTN's old 92% box does not leave room for the 6% strip.
      final big = CardFrame.centered(
        previewSize: preview,
        aspectRatio: DocumentKind.sudanId.aspectRatio,
        widthFactor: 0.92,
      );
      expect(big.marginClipped, isTrue);
    },
  );

  test('frames with the same numbers are equal', () {
    const a = CardFrame(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
    const b = CardFrame(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  group('boxInCrop', () {
    test('a crop 6% wider puts the box 0.054 inside every edge', () {
      final frame = CardFrame.centered(
        previewSize: const Size(390, 520),
        aspectRatio: DocumentKind.passport.aspectRatio,
      );
      final inset = frame.boxInCrop;
      for (final v in [inset.left, inset.top, inset.right, inset.bottom]) {
        expect(v, closeTo(0.06 / 1.12, 1e-9));
      }
    });

    test(
      'a strip cut short at the preview edge moves the box closer to it',
      () {
        // The frame touches the preview's left edge, so no strip fits there.
        const frame = CardFrame(left: 0, top: 0.2, right: 0.8, bottom: 0.6);
        final inset = frame.boxInCrop;
        expect(inset.left, 0);
        expect(inset.right, greaterThan(0));
      },
    );
  });
}
