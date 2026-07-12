import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mrz/core/config/injection.dart';
import 'package:mrz/features/arabic_document_scan/data/document_scan_service.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';
import 'package:mrz/features/arabic_document_scan/domain/id_card_side.dart';
import 'package:mrz/features/arabic_document_scan/domain/image_enhancement_preview.dart';
import 'package:mrz/features/arabic_document_scan/presentation/widgets/document_result_sheet.dart';
import 'package:mrz/features/arabic_document_scan/presentation/widgets/enhanced_image_preview_sheet.dart';
import 'package:permission_handler/permission_handler.dart';

@RoutePage()
class DocumentCapturePage extends StatefulWidget {
  const DocumentCapturePage({
    super.key,
    required this.documentType,
    this.countryCode,
    this.idCardSide = IdCardSide.front,
  });

  final DocumentType documentType;
  final String? countryCode;
  final IdCardSide idCardSide;

  @override
  State<DocumentCapturePage> createState() => _DocumentCapturePageState();
}

class _DocumentCapturePageState extends State<DocumentCapturePage> {
  final _picker = ImagePicker();
  bool _isProcessing = false;
  String? _error;
  String _processingLabel = 'Processing...';

  DocumentScanService get _scanService => locator<DocumentScanService>();

  Future<void> _pickAndScan(ImageSource source) async {
    if (_isProcessing) return;

    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() => _error = 'Camera permission is required.');
        return;
      }
    }

    if (source == ImageSource.gallery) {
      final status = await Permission.photos.request();
      if (!status.isGranted && !status.isLimited) {
        setState(() => _error = 'Photo library permission is required.');
        return;
      }
    }

    setState(() {
      _isProcessing = true;
      _processingLabel = 'Enhancing image...';
      _error = null;
    });

    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
      );
      if (picked == null) {
        setState(() => _isProcessing = false);
        return;
      }

      final preview = await _scanService.prepareImage(picked.path);

      if (!mounted) return;
      setState(() => _isProcessing = false);

      final selection = await showEnhancedImagePreview(
        context,
        preview: preview,
      );

      if (!mounted) return;

      if (selection == null ||
          selection.action != ImagePreviewAction.accept) {
        await _scanService.discardPreparedImages(
          selection?.allGeneratedPaths ?? preview.generatedTempPaths,
        );
        return;
      }

      setState(() {
        _isProcessing = true;
        _processingLabel = 'Scanning document...';
      });

      final result = await _scanService.scan(
        documentType: widget.documentType,
        imagePath: preview.originalPath,
        ocrImagePath: selection.ocrImagePath,
        enhancementWarning: preview.enhancementFailed ? preview.warning : null,
        countryCode: widget.countryCode,
        idCardSide: widget.idCardSide,
      );

      await _scanService.discardPreparedImages(
        selection.allGeneratedPaths,
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => DocumentResultSheet(result: result),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = 'Scan failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.documentType.label)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_captureHint),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const Spacer(),
            if (_isProcessing)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(_processingLabel),
                ],
              )
            else ...[
              FilledButton.icon(
                onPressed: () => _pickAndScan(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take photo'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _pickAndScan(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose from gallery'),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String get _captureHint {
    if (widget.documentType == DocumentType.arabicId &&
        widget.countryCode == 'sd') {
      return widget.idCardSide.captureHint;
    }
    return widget.documentType.captureHint;
  }
}
