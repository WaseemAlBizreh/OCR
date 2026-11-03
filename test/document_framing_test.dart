import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/domain/document_framing.dart';
import 'package:idlens/src/domain/image_quality.dart';

/// A 400 x 300 photo of an ID card (85.6 / 54), cropped with the camera's
/// margin: a well-placed card is about 357 x 225 pixels, 21 from the sides.
const idAspect = 85.6 / 54;

List<FramePoint> box(double l, double t, double r, double b) => [
  (x: l, y: t),
  (x: r, y: t),
  (x: r, y: b),
  (x: l, y: b),
];

FrameRegion region({
  required double share,
  required List<double> box,
  List<double> contact = const [0, 0, 0, 0],
}) => FrameRegion(
  share: share,
  left: box[0],
  top: box[1],
  right: box[2],
  bottom: box[3],
  contact: contact,
);

FrameVerdict? judge({List<FramePoint>? outline, FrameRegion? region}) =>
    DocumentFraming.fromPhoto(
      FrameMeasure(width: 400, height: 300, outline: outline, region: region),
      aspectRatio: idAspect,
    );

void main() {
  group('outline', () {
    test('a card inside the frame is not cut off', () {
      final verdict = judge(outline: box(21, 37, 378, 262))!;
      expect(verdict.method, FrameMethod.outline);
      expect(verdict.cutOff, isFalse);
    });

    test('a corner at the left edge is cut off on the left', () {
      final verdict = judge(outline: box(2, 37, 359, 262))!;
      expect(verdict.method, FrameMethod.outline);
      expect(verdict.cutSides, [FrameSide.left]);
    });

    test('the corners can come in any order', () {
      final verdict = judge(
        outline: [
          (x: 378.0, y: 262.0),
          (x: 21.0, y: 37.0),
          (x: 21.0, y: 262.0),
          (x: 378.0, y: 37.0),
        ],
      )!;
      expect(verdict.method, FrameMethod.outline);
      expect(verdict.cutOff, isFalse);
    });

    test('a card turned a quarter is still the document', () {
      // 142 x 225: the card upright in the photo.
      final verdict = judge(outline: box(129, 37, 271, 262));
      // Too small (27% of the photo) to be the document.
      expect(verdict, isNull);
      final bigger = DocumentFraming.fromPhoto(
        FrameMeasure(width: 300, height: 400, outline: box(37, 21, 262, 378)),
        aspectRatio: idAspect,
      )!;
      expect(bigger.method, FrameMethod.outline);
      expect(bigger.cutOff, isFalse);
    });

    test('a shape unlike the document is ignored', () {
      // Square: a printed box on the card, not the card.
      expect(judge(outline: box(50, 20, 330, 280)), isNull);
    });

    test('an outline too small to be the document is ignored', () {
      expect(judge(outline: box(150, 120, 250, 183)), isNull);
    });

    test('an ignored outline leaves the decision to the bright area', () {
      final verdict = judge(
        outline: box(50, 20, 330, 280),
        region: region(share: 0.67, box: [21, 37, 378, 262]),
      )!;
      expect(verdict.method, FrameMethod.region);
      expect(verdict.cutOff, isFalse);
    });
  });

  group('bright area', () {
    test('a card inside the frame is not cut off', () {
      final verdict = judge(
        region: region(share: 0.67, box: [21, 37, 378, 262]),
      )!;
      expect(verdict.method, FrameMethod.region);
      expect(verdict.cutOff, isFalse);
    });

    test('a card moved left, lying along the left edge, is cut off', () {
      final verdict = judge(
        region: region(
          share: 0.56,
          box: [0, 37, 300, 262],
          contact: [225, 0, 0, 0],
        ),
      )!;
      expect(verdict.cutSides, [FrameSide.left]);
    });

    test('a card cut at the top and right is cut on both', () {
      final verdict = judge(
        region: region(
          share: 0.6,
          box: [60, 0, 400, 220],
          contact: [0, 330, 210, 0],
        ),
      )!;
      expect(verdict.cutSides, [FrameSide.top, FrameSide.right]);
    });

    test('a hand holding the card from the side is not a cut', () {
      // The hand reaches the left edge over 40 pixels; the card is 225 high.
      final verdict = judge(
        region: region(
          share: 0.7,
          box: [0, 37, 378, 262],
          contact: [40, 0, 0, 0],
        ),
      )!;
      expect(verdict.cutOff, isFalse);
    });

    test('a light background covering the photo cannot tell', () {
      expect(
        judge(
          region: region(
            share: 0.97,
            box: [0, 0, 400, 300],
            contact: [300, 400, 300, 400],
          ),
        ),
        isNull,
      );
    });

    test('an area along three edges is the background and cannot tell', () {
      expect(
        judge(
          region: region(
            share: 0.8,
            box: [0, 0, 400, 260],
            contact: [260, 400, 260, 0],
          ),
        ),
        isNull,
      );
    });

    test('a tiny bright spot cannot tell', () {
      expect(judge(region: region(share: 0.05, box: [0, 0, 60, 60])), isNull);
    });
  });

  group('text', () {
    test('text at one edge is enough to be cut off', () {
      expect(DocumentFraming.fromText(1).cutOff, isTrue);
      expect(DocumentFraming.fromText(1).method, FrameMethod.text);
    });

    test('text away from every edge is not cut off', () {
      expect(DocumentFraming.fromText(0).cutOff, isFalse);
    });
  });

  group('coverage', () {
    FrameCoverage cover({List<FramePoint>? outline, FrameRegion? region}) =>
        DocumentFraming.coverage(
          FrameMeasure(
            width: 400,
            height: 300,
            outline: outline,
            region: region,
          ),
          aspectRatio: idAspect,
        );

    // A light table: one bright area over the whole photo.
    final lightTable = region(
      share: 0.97,
      box: [0, 0, 400, 300],
      contact: [300, 400, 300, 400],
    );

    test('a well-placed card measured by its outline is not far', () {
      final c = cover(outline: box(21, 37, 378, 262));
      expect(c.method, FrameMethod.outline);
      expect(c.share, closeTo(0.67, 0.01));
      expect(c.share, greaterThan(ImageQuality.minDocumentCoverage));
    });

    test('a far card is measured by its outline, below the cut-off limit', () {
      // 60% of the box: 214 x 135, 0.24 of the photo.
      final c = cover(outline: box(93, 82, 307, 217));
      expect(c.method, FrameMethod.outline);
      expect(c.share, lessThan(DocumentFraming.minOutlineShare));
      expect(c.share, lessThan(ImageQuality.minDocumentCoverage));
    });

    test('a far card on a light table is far, not hidden by the table', () {
      final c = cover(outline: box(93, 82, 307, 217), region: lightTable);
      expect(c.method, FrameMethod.outline);
      expect(c.share, lessThan(ImageQuality.minDocumentCoverage));
    });

    test('a bright object in a corner does not make a far card look near', () {
      // The bright area's box runs from the card to a paper in the corner.
      final c = cover(
        outline: box(93, 82, 307, 217),
        region: region(share: 0.3, box: [93, 0, 400, 217]),
      );
      expect(c.method, FrameMethod.outline);
      expect(c.share, lessThan(ImageQuality.minDocumentCoverage));
    });

    test('without an outline, the bright area box is used', () {
      final c = cover(region: region(share: 0.2, box: [100, 75, 300, 225]));
      expect(c.method, FrameMethod.region);
      expect(c.share, closeTo(0.25, 1e-9));
    });

    test('an outline unlike the document falls back to the bright area', () {
      final c = cover(
        outline: box(50, 20, 330, 280),
        region: region(share: 0.2, box: [100, 75, 300, 225]),
      );
      expect(c.method, FrameMethod.region);
    });

    test('an outline smaller than the far limit is not the document', () {
      // 0.1 of the photo: a printed box, not the card.
      final c = cover(outline: box(150, 120, 245, 180));
      expect(c, same(FrameCoverage.unknown));
    });

    test('a light table with no outline cannot tell', () {
      expect(cover(region: lightTable).share, 1);
      expect(cover(region: lightTable).method, isNull);
    });

    test('a bright area along three edges cannot tell', () {
      final c = cover(
        region: region(
          share: 0.8,
          box: [0, 0, 400, 260],
          contact: [260, 400, 260, 0],
        ),
      );
      expect(c, same(FrameCoverage.unknown));
    });

    test('nothing found cannot tell', () {
      expect(cover(), same(FrameCoverage.unknown));
    });

    test('a far outline is not trusted for the cut-off check', () {
      // Its corners are inside, but at 0.24 the region decides instead.
      expect(judge(outline: box(93, 82, 307, 217)), isNull);
    });
  });

  test('nothing found cannot tell', () {
    expect(judge(), isNull);
  });
}
