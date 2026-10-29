import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mrz/core/config/injection.dart';
import 'package:mrz/features/identity_scan/data/image/image_ops.dart';
import 'package:mrz/features/identity_scan/domain/document_kind.dart';
import 'package:mrz/features/identity_scan/presentation/widgets/card_frame_overlay.dart';

/// Full-screen camera with a card-shaped border. Pops with the path of the
/// photo cropped to that border, or null if the user backs out.
class CardCameraPage extends StatefulWidget {
  const CardCameraPage({super.key, required this.kind, required this.side});

  final DocumentKind kind;
  final DocumentSide side;

  @override
  State<CardCameraPage> createState() => _CardCameraPageState();
}

class _CardCameraPageState extends State<CardCameraPage> {
  CameraController? _controller;
  String? _error;
  bool _capturing = false;
  bool _flashOn = false;
  bool _flashBusy = false;

  /// Where the user last tapped to focus (preview pixels), for the focus ring.
  Offset? _focusRing;
  int _focusRingId = 0;
  bool _focusRingDimmed = false;
  Timer? _focusRingTimer;
  Timer? _focusRingDimTimer;
  DateTime? _tappedAt;

  bool get _showsMrz =>
      widget.kind.hasMrz && widget.side != DocumentSide.front;

  /// The MRZ sits right at the card's bottom edge, so on MRZ pages the photo
  /// is cropped a little wider than the frame: a card held slightly low or
  /// high in the frame then keeps its MRZ.
  static const _mrzCropMargin = 0.06;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await controller.setFlashMode(FlashMode.off);
      await _useAutoFocus(controller);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera unavailable: $e');
    }
  }

  /// Continuous auto focus; some cameras do not support choosing a mode.
  Future<void> _useAutoFocus(CameraController controller) async {
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
    } catch (e) {
      debugPrint('Focus mode unavailable: $e');
    }
  }

  /// Focuses and meters exposure at [point], given as 0..1 of the preview.
  /// Devices without a focus point ignore it, so failures are not shown.
  Future<void> _focusAt(Offset point) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
    } catch (e) {
      debugPrint('Focus point unavailable: $e');
    }
  }

  void _onPreviewTap(Offset position, Size previewSize) {
    if (_capturing) return;
    _tappedAt = DateTime.now();
    HapticFeedback.selectionClick();
    _focusRingTimer?.cancel();
    _focusRingDimTimer?.cancel();
    setState(() {
      _focusRing = position;
      _focusRingId++;
      _focusRingDimmed = false;
    });
    // Like the iOS camera: the box settles bright, dims, then goes away.
    _focusRingDimTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _focusRingDimmed = true);
    });
    _focusRingTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _focusRing = null);
    });
    _focusAt(Offset(
      (position.dx / previewSize.width).clamp(0.0, 1.0),
      (position.dy / previewSize.height).clamp(0.0, 1.0),
    ));
  }

  /// Refocuses on the middle of the card frame just before the photo, unless
  /// the user chose a focus point a moment ago.
  Future<void> _focusBeforeCapture(CardFrame frame) async {
    final tapped = _tappedAt;
    if (tapped != null &&
        DateTime.now().difference(tapped) < const Duration(seconds: 3)) {
      return;
    }
    await _focusAt(Offset(
      (frame.left + frame.right) / 2,
      (frame.top + frame.bottom) / 2,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  @override
  void dispose() {
    _focusRingTimer?.cancel();
    _focusRingDimTimer?.cancel();
    final controller = _controller;
    if (controller != null) {
      // Leaving with the back button: switch the torch off before releasing.
      (_flashOn ? controller.setFlashMode(FlashMode.off) : Future<void>.value())
          .catchError((_) {})
          .whenComplete(controller.dispose);
    }
    super.dispose();
  }

  /// Stops drawing the preview, then waits for the camera to be released, so
  /// the next page (e.g. the back side) never opens a second controller on
  /// the same camera while this one is still shutting down.
  Future<void> _releaseCamera() async {
    final controller = _controller;
    if (controller == null) return;
    if (mounted) setState(() => _controller = null);
    if (_flashOn) {
      await controller.setFlashMode(FlashMode.off).catchError((_) {});
    }
    await controller.dispose();
  }

  /// Turns the flash (continuous light) on or off. It stays on while the
  /// photo is taken and until the camera closes.
  ///
  /// The camera plugin does not throw when the camera refuses a torch change:
  /// it only reports the error on its own error channel. So the icon is not
  /// switched until the controller has had a moment to report one, and a
  /// failure is shown with the plugin's message.
  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || _flashBusy) return;
    _flashBusy = true;
    final next = !_flashOn;
    final errorBefore = controller.value.errorDescription;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final errorAfter = controller.value.errorDescription;
      if (errorAfter != null && errorAfter != errorBefore) {
        _showMessage('Flash did not turn on: $errorAfter');
        debugPrint('Flash failed: $errorAfter');
        return;
      }
      if (mounted) setState(() => _flashOn = next);
    } on CameraException catch (e) {
      _showMessage('Flash unavailable: ${e.description ?? e.code}');
      debugPrint('Flash failed: ${e.code} ${e.description}');
    } catch (e) {
      _showMessage('Flash unavailable: $e');
      debugPrint('Flash failed: $e');
    } finally {
      _flashBusy = false;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _capture(CardFrame frame) async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      await _focusBeforeCapture(frame);
      final photo = await controller.takePicture();
      final cropFrame = _showsMrz ? frame.expanded(_mrzCropMargin) : frame;
      final cropped = await locator<ImageOps>().crop(
        photo.path,
        left: cropFrame.left,
        top: cropFrame.top,
        right: cropFrame.right,
        bottom: cropFrame.bottom,
        portrait: true,
        label: 'card_${widget.side.name}',
      );
      // A certificate is flattened to a straight A4 sheet when its outline is
      // found; otherwise the plain crop is kept.
      var result = cropped;
      if (widget.kind == DocumentKind.civilRegistryCertificate) {
        final flat = await locator<ImageOps>().cropPage(cropped, label: 'certificate');
        if (flat != null) {
          await locator<ImageOps>().deleteTemp(cropped);
          result = flat;
        }
      }
      await File(photo.path).delete().catchError((_) => File(photo.path));
      await _releaseCamera();
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        setState(() => _capturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${widget.kind.label} · ${widget.side.label}'),
        actions: [
          if (controller != null)
            IconButton(
              tooltip: _flashOn ? 'Flash off' : 'Flash on',
              onPressed: _toggleFlash,
              icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off),
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : controller == null
              ? const Center(child: CircularProgressIndicator())
              : _buildPreview(controller),
    );
  }

  Widget _buildPreview(CameraController controller) {
    // Portrait preview: the sensor reports landscape, so invert its ratio.
    final previewAspect = 1 / controller.value.aspectRatio;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: previewAspect,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final frame = CardFrame.centered(
                      previewSize: constraints.biggest,
                      aspectRatio: widget.kind.aspectRatio,
                    );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) =>
                              _onPreviewTap(d.localPosition, constraints.biggest),
                          child: CameraPreview(controller),
                        ),
                        // The overlay is a full-size CustomPaint, which would
                        // otherwise swallow the taps meant for the preview.
                        IgnorePointer(
                          child: CardFrameOverlay(
                            frame: frame,
                            mrzBandFraction:
                                _showsMrz ? widget.kind.mrzGuideFraction : null,
                          ),
                        ),
                        if (_focusRing != null)
                          Positioned(
                            left: (_focusRing!.dx - _FocusIndicator.size / 2)
                                .clamp(0.0, constraints.maxWidth - _FocusIndicator.size),
                            top: (_focusRing!.dy - _FocusIndicator.size / 2)
                                .clamp(0.0, constraints.maxHeight - _FocusIndicator.size),
                            child: IgnorePointer(
                              child: _FocusIndicator(
                                key: ValueKey(_focusRingId),
                                dimmed: _focusRingDimmed,
                              ),
                            ),
                          ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 12,
                          child: Text(
                            widget.side.hint,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (_capturing)
                          const ColoredBox(
                            color: Colors.black45,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 56,
                          child: Center(
                            child: _ShutterButton(
                              onPressed:
                                  _capturing ? null : () => _capture(frame),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 72,
        height: 72,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onPressed == null ? Colors.white38 : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Focus indicator: a thin white circle. It starts large, snaps in to size,
/// then dims.
class _FocusIndicator extends StatelessWidget {
  const _FocusIndicator({super.key, required this.dimmed});

  static const size = 76.0;

  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: dimmed ? 0.5 : 1,
      duration: const Duration(milliseconds: 400),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.45, end: 1),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: const SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: _FocusBoxPainter()),
        ),
      ),
    );
  }
}

class _FocusBoxPainter extends CustomPainter {
  const _FocusBoxPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // Inset so the stroke is not clipped at the edge of the box.
    final radius = size.shortestSide / 2 - 2;
    // A faint dark outline keeps the thin white line visible on light cards.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_FocusBoxPainter oldDelegate) => false;
}
