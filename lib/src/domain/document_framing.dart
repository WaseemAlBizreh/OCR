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
  FrameVerdict(this.method, List<FrameSide> this.cutSides)
    : cutEdges = cutSides.length;

  /// A verdict from printed text, which only counts the edges.
  const FrameVerdict.text(this.cutEdges)
    : method = FrameMethod.text,
      cutSides = null;

  final FrameMethod method;

  /// How many edges the document runs past; 0 when it is fully inside.
  final int cutEdges;

  /// Which edges, when the photo shows it; null for [FrameMethod.text].
  final List<FrameSide>? cutSides;

  bool get cutOff => cutEdges > 0;

  Map<String, dynamic> toJson() => {
    'method': method.name,
    'cutEdges': cutEdges,
    if (cutSides != null) 'cutSides': [for (final s in cutSides!) s.name],
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

  /// Share (0..1) of the photo taken by the bright area's bounding box. Low
  /// when the document is far away. 1 when no area was found, so an unusual
  /// background never makes a good photo look like a far one.
  double get coverage {
    final r = region;
    if (r == null || width <= 0 || height <= 0) return 1;
    return ((r.right - r.left) * (r.bottom - r.top) / (width * height)).clamp(
      0.0,
      1.0,
    );
  }

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
    'coverage': coverage,
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

  /// A corner or area this close to an edge (fraction of the photo) is at it.
  static const edgeMargin = 0.015;

  /// An outline smaller than this share of the photo isn't the document.
  static const minOutlineShare = 0.3;

  /// How far (as a fraction) an outline's shape may differ from the
  /// document's and still be it.
  static const aspectTolerance = 0.2;

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
    if (outline != null && _isDocument(outline, measure, aspectRatio)) {
      return FrameVerdict(
        FrameMethod.outline,
        _cornersAtEdges(outline, measure),
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
    return FrameVerdict(FrameMethod.region, sides);
  }

  /// The verdict from printed text (check 3): [touchedSides] edges that text
  /// runs up to.
  static FrameVerdict fromText(int touchedSides) =>
      FrameVerdict.text(touchedSides.clamp(0, 4));

  static bool _isDocument(
    List<FramePoint> outline,
    FrameMeasure measure,
    double aspectRatio,
  ) {
    if (outline.length != 4) return false;
    // In order first: corners in a crossed order give a wrong area.
    final c = _ordered(outline);
    final share = _area(c) / (measure.width * measure.height);
    if (share < minOutlineShare) return false;
    final width = (_distance(c[0], c[1]) + _distance(c[3], c[2])) / 2;
    final height = (_distance(c[0], c[3]) + _distance(c[1], c[2])) / 2;
    if (width <= 0 || height <= 0) return false;
    final ratio = width / height;
    // A photo taken with the document turned a quarter is fine too.
    bool near(double expected) =>
        (ratio - expected).abs() <= expected * aspectTolerance;
    return near(aspectRatio) || near(1 / aspectRatio);
  }

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
