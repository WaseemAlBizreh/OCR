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

  bool get _showsMrz => widget.side != DocumentSide.front;

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
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera unavailable: $e');
    }
  }

  @override
  void dispose() {
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
      await File(photo.path).delete().catchError((_) => File(photo.path));
      await _releaseCamera();
      if (mounted) Navigator.of(context).pop(cropped);
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
                        CameraPreview(controller),
                        CardFrameOverlay(
                          frame: frame,
                          mrzBandFraction:
                              _showsMrz ? widget.kind.mrzGuideFraction : null,
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
