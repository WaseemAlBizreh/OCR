import 'package:flutter/material.dart';

/// Where the capture frame sits inside the camera preview, as fractions of the
/// preview box. The same numbers drive the painted border and the crop of the
/// photo, so what the user sees inside the border is what gets scanned.
class CardFrame {
  const CardFrame({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// A frame as wide as [widthFactor] of the preview, centred, with the given
  /// document [aspectRatio] (width / height).
  factory CardFrame.centered({
    required Size previewSize,
    required double aspectRatio,
    double widthFactor = 0.92,
  }) {
    final width = previewSize.width * widthFactor;
    final height = width / aspectRatio;
    final left = (previewSize.width - width) / 2;
    final top = (previewSize.height - height) / 2;
    return CardFrame(
      left: left / previewSize.width,
      top: top / previewSize.height,
      right: (left + width) / previewSize.width,
      bottom: (top + height) / previewSize.height,
    );
  }

  final double left;
  final double top;
  final double right;
  final double bottom;

  /// This frame grown by [fraction] of its own width and height on every
  /// side, kept inside the preview.
  CardFrame expanded(double fraction) {
    final dx = (right - left) * fraction;
    final dy = (bottom - top) * fraction;
    double unit(double v) => v.clamp(0.0, 1.0).toDouble();
    return CardFrame(
      left: unit(left - dx),
      top: unit(top - dy),
      right: unit(right + dx),
      bottom: unit(bottom + dy),
    );
  }

  Rect toRect(Size size) => Rect.fromLTRB(
        left * size.width,
        top * size.height,
        right * size.width,
        bottom * size.height,
      );
}

class CardFrameOverlay extends StatelessWidget {
  const CardFrameOverlay({
    super.key,
    required this.frame,
    this.mrzBandFraction,
  });

  final CardFrame frame;

  /// When set, a guide for the MRZ band is drawn along the bottom of the frame.
  final double? mrzBandFraction;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _CardFramePainter(frame, mrzBandFraction),
    );
  }
}

class _CardFramePainter extends CustomPainter {
  _CardFramePainter(this.frame, this.mrzBandFraction);

  final CardFrame frame;
  final double? mrzBandFraction;

  static const _radius = Radius.circular(14);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = frame.toRect(size);
    final hole = RRect.fromRectAndRadius(rect, _radius);

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(hole),
      ),
      Paint()..color = Colors.black54,
    );

    canvas.drawRRect(
      hole,
      Paint()
        ..color = Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const arm = 28.0;
    for (final (origin, dx, dy) in [
      (rect.topLeft, 1.0, 1.0),
      (rect.topRight, -1.0, 1.0),
      (rect.bottomLeft, 1.0, -1.0),
      (rect.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(origin, origin.translate(dx * arm, 0), corner);
      canvas.drawLine(origin, origin.translate(0, dy * arm), corner);
    }

    final band = mrzBandFraction;
    if (band != null) {
      final bandRect = Rect.fromLTRB(
        rect.left + 8,
        rect.bottom - rect.height * band,
        rect.right - 8,
        rect.bottom - 8,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bandRect, const Radius.circular(6)),
        Paint()
          ..color = Colors.amberAccent.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      final label = TextPainter(
        text: const TextSpan(
          text: 'MRZ',
          style: TextStyle(
            color: Colors.amberAccent,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, bandRect.topLeft.translate(8, 4));
    }
  }

  @override
  bool shouldRepaint(_CardFramePainter old) =>
      old.frame != frame || old.mrzBandFraction != mrzBandFraction;
}
