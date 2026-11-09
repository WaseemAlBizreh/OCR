import 'dart:math' as math;

/// A point in photo pixels.
typedef FramePoint = ({double x, double y});

/// The document's bright area, as found against a darker background.
class FrameRegion {
  const FrameRegion({
    required this.share,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.contact,
  });

  /// Share (0..1) of the photo the area itself covers.
  final double share;

  /// Its bounding box, in photo pixels.
  final double left, top, right, bottom;

  /// How many pixels of each photo edge it lies on, in [FrameSide] order.
  final List<double> contact;
}

/// The edges of a photo, in the order [FrameRegion.contact] uses.
enum FrameSide { left, top, right, bottom }

/// How the framing was judged, from the most to the least reliable.
enum FrameMethod {
  /// The document's 4 corners were found.
  outline,

  /// The document stood out from the background as one bright area.
  region,

  /// Neither was found, so only printed text near the edges was used.
  text,
}

/// Whether the document is cut off by the edges of the photo.
class FrameVerdict {
  /// A verdict from the photo, which knows the [cutSides].
  FrameVerdict(this.method, List<FrameSide> this.cutSides, {this.gaps})
    : cutEdges = cutSides.length;

  /// A verdict from printed text, which only counts the edges.
  const FrameVerdict.text(this.cutEdges)
    : method = FrameMethod.text,
      cutSides = null,
      gaps = null;

  final FrameMethod method;

  /// How many edges the document runs past; 0 when it is fully inside.
  final int cutEdges;

  /// Which edges, when the photo shows it; null for [FrameMethod.text].
  final List<FrameSide>? cutSides;

  /// How much background is left between the document and each edge of the
  /// photo, as a fraction of the photo's width (left, right) or height (top,
  /// bottom), in [FrameSide] order; negative is not possible, 0 is touching.
  /// Null when the photo can't tell ([FrameMethod.text]). A document placed in
  /// the box has about 0.054; in practice 0.025 to 0.06 (see
  /// [DocumentFraming.edgeMargin]).
  final List<double>? gaps;

  bool get cutOff => cutEdges > 0;

  Map<String, dynamic> toJson() => {
    'method': method.name,
    'cutEdges': cutEdges,
    if (cutSides != null) 'cutSides': [for (final s in cutSides!) s.name],
    if (gaps != null)
      'edgeGaps': {
        for (final side in FrameSide.values)
          side.name: double.parse(gaps![side.index].toStringAsFixed(3)),
      },
  };
}

/// What [DocumentFraming] needs from a photo: its size, and the outline and
/// bright area that `DocumentFrameChecker` found in it.
class FrameMeasure {
  const FrameMeasure({
    required this.width,
    required this.height,
    this.outline,
    this.region,
  });

  final double width;
  final double height;

  /// The largest 4-corner shape found, in any order; null when none.
  final List<FramePoint>? outline;

  /// The largest bright area; null when none.
  final FrameRegion? region;

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    'outline': outline == null
        ? null
        : [
            for (final p in outline!) [p.x.round(), p.y.round()],
          ],
    if (region != null)
      'region': {
        'share': region!.share,
        'box': [region!.left, region!.top, region!.right, region!.bottom],
        'contact': region!.contact,
      },
  };
}

/// How much of the photo the document takes, which is low when it is far
/// from the camera.
class FrameCoverage {
  const FrameCoverage(this.share, this.method);

  /// Nothing measured the document, so it is not judged far.
  static const unknown = FrameCoverage(1, null);

  /// Share (0..1) of the photo.
  final double share;

  /// What it was measured from: [FrameMethod.outline] or
  /// [FrameMethod.region]; null for [unknown].
  final FrameMethod? method;

  Map<String, dynamic> toJson() => {
    'share': share,
    'from': method?.name ?? 'none',
  };
}

/// Decides whether a document is cut off by the edges of its photo.
///
/// The camera keeps a margin of background around the frame, so a document
/// placed in the frame never reaches the photo's edges. One edge is enough:
/// a document moved to one side is cut on one side only.
///
/// Three checks, each used only when the one before it can't decide:
/// 1. the document's outline: a corner at an edge means it is cut off;
/// 2. its bright area against the background: lying along an edge means it
///    runs past it;
/// 3. printed text running up to an edge.
class DocumentFraming {
  DocumentFraming._();

  /// A corner or area this close to an edge (fraction of the photo) is at it,
  /// and the document is cut off.
  ///
  /// Kept small on purpose. A photo is the guide box plus a 6% strip, so a
  /// card placed exactly in the box lies about 0.054 inside each edge, but
  /// real users fit it loosely: on devices a good ID back was about 1% past the
  /// box and a good passport page 2-3% past it (gaps of 0.025 to 0.033). A
  /// limit of 0.035 rejected that passport. A card held low enough to cut its
  /// MRZ lies in the same range, so no edge limit separates the two; that
  /// needs the MRZ lines' own positions.
  static const edgeMargin = 0.015;

  /// An outline smaller than this share of the photo isn't trusted to say
  /// whether the document is cut off.
  static const minOutlineShare = 0.3;

  /// An outline down to this share still measures how far the document is.
  /// A far card is smaller than [minOutlineShare] (60% of the box is about
  /// 0.29), so distance needs a lower limit. Below it, a printed box on the
  /// document could be taken for the document.
  static const minFarOutlineShare = 0.15;

  /// How far (as a fraction) an outline's shape may differ from the
  /// document's and still be it.
  static const aspectTolerance = 0.2;

  /// How far (as a fraction) a bright area's box may differ from the
  /// document's shape before the document counts as cut off. Two limits,
  /// because a tilted card's box is wider than the card and the area fills
  /// little of it (a card turned 15 degrees fills about 64%), while an
  /// upright card fills nearly all of its box and so must match the shape
  /// closely. A half card, with its dark remainder, is such an upright box.
  static const regionAspectTolerance = 0.25;
  static const uprightRegionTolerance = 0.10;

  /// An area filling at least this share of its own box is upright.
  static const uprightFill = 0.9;

  /// A bright area outside this range of shares isn't clearly the document:
  /// too small is noise, too large is a light background.
  static const minRegionShare = 0.15;
  static const maxRegionShare = 0.92;

  /// An area runs past an edge only when it lies along that edge for at least
  /// this share of its own side. A finger or a hand holding the document
  /// touches the edge over a much shorter stretch.
  static const minContact = 0.5;

  /// The verdict from the photo itself (checks 1 and 2), or null when neither
  /// the outline nor the bright area can tell. [aspectRatio] is the
  /// document's width / height.
  static FrameVerdict? fromPhoto(
    FrameMeasure measure, {
    required double aspectRatio,
  }) {
    if (measure.width <= 0 || measure.height <= 0) return null;
    final outline = measure.outline;
    if (outline != null &&
        _outlineShare(outline, measure, aspectRatio) >= minOutlineShare) {
      return FrameVerdict(
        FrameMethod.outline,
        _cornersAtEdges(outline, measure),
        gaps: _outlineGaps(outline, measure),
      );
    }
    final region = measure.region;
    if (region == null ||
        region.share < minRegionShare ||
        region.share > maxRegionShare) {
      return null;
    }
    final sides = _regionAtEdges(region, measure);
    // An area along three or four edges is the background, not the document.
    if (sides.length >= 3) return null;
    if (sides.isEmpty) {
      // Touching no edge is not enough: half a card in the middle of the
      // photo (the rest dark, or out of the crop) has the wrong shape.
      final short = _shortSide(region, measure, aspectRatio);
      if (short != null) {
        return FrameVerdict(FrameMethod.region, [
          short,
        ], gaps: _regionGaps(region, measure));
      }
    }
    return FrameVerdict(
      FrameMethod.region,
      sides,
      gaps: _regionGaps(region, measure),
    );
  }

  /// The verdict from printed text (check 3): [touchedSides] edges that text
  /// runs up to.
  static FrameVerdict fromText(int touchedSides) =>
      FrameVerdict.text(touchedSides.clamp(0, 4));

  /// How much of the photo the document takes (the "too far" measure):
  ///
  /// 1. its outline, when one with the document's shape covers at least
  ///    [minFarOutlineShare]: the document's own size, whatever is around it;
  /// 2. otherwise the bright area's bounding box, unless that area is the
  ///    background (a light table: larger than [maxRegionShare] or along 3 or
  ///    4 edges), which says nothing about the document;
  /// 3. otherwise [FrameCoverage.unknown], so an unusual background never
  ///    makes a good photo look like a far one.
  static FrameCoverage coverage(
    FrameMeasure measure, {
    required double aspectRatio,
  }) {
    final photo = measure.width * measure.height;
    if (photo <= 0) return FrameCoverage.unknown;
    final outline = measure.outline;
    if (outline != null) {
      final share = _outlineShare(outline, measure, aspectRatio);
      if (share >= minFarOutlineShare) {
        return FrameCoverage(share.clamp(0.0, 1.0), FrameMethod.outline);
      }
    }
    final r = measure.region;
    if (r == null ||
        r.share > maxRegionShare ||
        _regionAtEdges(r, measure).length >= 3) {
      return FrameCoverage.unknown;
    }
    final box = (r.right - r.left) * (r.bottom - r.top) / photo;
    return FrameCoverage(box.clamp(0.0, 1.0), FrameMethod.region);
  }

  /// The share of the photo inside [outline], or 0 when it doesn't have the
  /// document's shape.
  static double _outlineShare(
    List<FramePoint> outline,
    FrameMeasure measure,
    double aspectRatio,
  ) {
    if (outline.length != 4) return 0;
    // In order first: corners in a crossed order give a wrong area.
    final c = _ordered(outline);
    final width = (_distance(c[0], c[1]) + _distance(c[3], c[2])) / 2;
    final height = (_distance(c[0], c[3]) + _distance(c[1], c[2])) / 2;
    if (width <= 0 || height <= 0) return 0;
    final ratio = width / height;
    // A photo taken with the document turned a quarter is fine too.
    bool near(double expected) =>
        (ratio - expected).abs() <= expected * aspectTolerance;
    if (!near(aspectRatio) && !near(1 / aspectRatio)) return 0;
    return _area(c) / (measure.width * measure.height);
  }

  /// The edge the document most likely continues past, when the bright
  /// area's box is too narrow or too wide to be the whole document: the edge
  /// of the photo nearest to it, on the axis that is short. Null when the box
  /// has the document's shape (or a quarter turn of it).
  static FrameSide? _shortSide(
    FrameRegion region,
    FrameMeasure measure,
    double aspectRatio,
  ) {
    final width = region.right - region.left;
    final height = region.bottom - region.top;
    if (width <= 0 || height <= 0) return null;
    final ratio = width / height;
    final fill =
        region.share * measure.width * measure.height / (width * height);
    final tolerance = fill >= uprightFill
        ? uprightRegionTolerance
        : regionAspectTolerance;
    bool near(double expected) =>
        (ratio - expected).abs() <= expected * tolerance;
    if (near(aspectRatio) || near(1 / aspectRatio)) return null;
    // Short axis: the box is narrower than the document (portrait document
    // shown as landscape included) when its ratio is under the nearest one.
    final target =
        (ratio - aspectRatio).abs() <= (ratio - 1 / aspectRatio).abs()
        ? aspectRatio
        : 1 / aspectRatio;
    if (ratio < target) {
      final left = region.left;
      final right = measure.width - region.right;
      return left <= right ? FrameSide.left : FrameSide.right;
    }
    final top = region.top;
    final bottom = measure.height - region.bottom;
    return top <= bottom ? FrameSide.top : FrameSide.bottom;
  }

  static List<double> _outlineGaps(
    List<FramePoint> outline,
    FrameMeasure measure,
  ) {
    final xs = [for (final p in outline) p.x];
    final ys = [for (final p in outline) p.y];
    return [
      xs.reduce(math.min) / measure.width,
      ys.reduce(math.min) / measure.height,
      (measure.width - xs.reduce(math.max)) / measure.width,
      (measure.height - ys.reduce(math.max)) / measure.height,
    ].map((g) => math.max(0.0, g)).toList();
  }

  static List<double> _regionGaps(FrameRegion region, FrameMeasure measure) => [
    region.left / measure.width,
    region.top / measure.height,
    (measure.width - region.right) / measure.width,
    (measure.height - region.bottom) / measure.height,
  ].map((g) => math.max(0.0, g)).toList();

  static List<FrameSide> _cornersAtEdges(
    List<FramePoint> outline,
    FrameMeasure measure,
  ) {
    final dx = measure.width * edgeMargin;
    final dy = measure.height * edgeMargin;
    return [
      if (outline.any((p) => p.x <= dx)) FrameSide.left,
      if (outline.any((p) => p.y <= dy)) FrameSide.top,
      if (outline.any((p) => p.x >= measure.width - dx)) FrameSide.right,
      if (outline.any((p) => p.y >= measure.height - dy)) FrameSide.bottom,
    ];
  }

  static List<FrameSide> _regionAtEdges(
    FrameRegion region,
    FrameMeasure measure,
  ) {
    final dx = measure.width * edgeMargin;
    final dy = measure.height * edgeMargin;
    final boxWidth = region.right - region.left;
    final boxHeight = region.bottom - region.top;
    bool along(FrameSide side, double length) =>
        region.contact[side.index] >= length * minContact;
    return [
      if (region.left <= dx && along(FrameSide.left, boxHeight)) FrameSide.left,
      if (region.top <= dy && along(FrameSide.top, boxWidth)) FrameSide.top,
      if (region.right >= measure.width - dx &&
          along(FrameSide.right, boxHeight))
        FrameSide.right,
      if (region.bottom >= measure.height - dy &&
          along(FrameSide.bottom, boxWidth))
        FrameSide.bottom,
    ];
  }

  /// Top-left, top-right, bottom-right, bottom-left.
  static List<FramePoint> _ordered(List<FramePoint> p) {
    double sum(FramePoint a) => a.x + a.y;
    double diff(FramePoint a) => a.y - a.x;
    FramePoint pick(double Function(FramePoint) key, bool smallest) =>
        p.reduce((a, b) => (key(a) <= key(b)) == smallest ? a : b);
    return [
      pick(sum, true),
      pick(diff, true),
      pick(sum, false),
      pick(diff, false),
    ];
  }

  static double _distance(FramePoint a, FramePoint b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  /// Shoelace formula.
  static double _area(List<FramePoint> p) {
    var sum = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i];
      final b = p[(i + 1) % p.length];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum.abs() / 2;
  }
}
