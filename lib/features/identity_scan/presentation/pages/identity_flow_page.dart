import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mrz/core/config/injection.dart';
import 'package:mrz/features/identity_scan/data/identity_scan_service.dart';
import 'package:mrz/features/identity_scan/domain/document_kind.dart';
import 'package:mrz/features/identity_scan/presentation/widgets/card_camera_page.dart';
import 'package:mrz/features/mrz_scan/presentation/widgets/json_result_sheet.dart';
import 'package:permission_handler/permission_handler.dart';

/// Capture every page of the document, preview it,
/// then scan and show the payload.
@RoutePage()
class IdentityFlowPage extends StatefulWidget {
  const IdentityFlowPage({super.key, required this.kind});

  final DocumentKind kind;

  @override
  State<IdentityFlowPage> createState() => _IdentityFlowPageState();
}

class _IdentityFlowPageState extends State<IdentityFlowPage> {
  final Map<DocumentSide, String> _originals = {};
  String? _busyLabel;
  bool _permissionDenied = false;

  IdentityScanService get _service => locator<IdentityScanService>();

  bool get _complete =>
      widget.kind.sides.every((side) => _originals.containsKey(side));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _captureMissing());
  }

  @override
  void dispose() {
    _service.discard(_originals.values);
    super.dispose();
  }

  Future<bool> _ensureCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return false;
    setState(() => _permissionDenied = !status.isGranted);
    if (status.isPermanentlyDenied) await openAppSettings();
    return status.isGranted;
  }

  /// Walks the sides in order (front, then back) until all are captured.
  Future<void> _captureMissing() async {
    if (!await _ensureCamera()) return;
    for (final side in widget.kind.sides) {
      if (_originals.containsKey(side)) continue;
      final captured = await _capture(side);
      if (!captured) {
        if (mounted && _originals.isEmpty) context.router.maybePop();
        return;
      }
    }
  }

  Future<bool> _capture(DocumentSide side) async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CardCameraPage(kind: widget.kind, side: side),
      ),
    );
    if (path == null || !mounted) return false;

    final stale = _originals[side];
    setState(() => _originals[side] = path);
    if (stale != null) await _service.discard([stale]);
    return true;
  }

  Future<void> _retake(DocumentSide side) async {
    if (!await _ensureCamera()) return;
    await _capture(side);
  }

  Future<void> _scan() async {
    if (!_complete || _busyLabel != null) return;
    setState(() => _busyLabel = 'Scanning document...');
    try {
      final result = await _service.scan(
        kind: widget.kind,
        imagePaths: {
          for (final side in widget.kind.sides) side: _originals[side]!,
        },
      );
      if (!mounted) return;
      setState(() => _busyLabel = null);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => JsonResultSheet(resultJson: result.toJson()),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busyLabel = null);
        _toast('Scan failed: $e');
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _zoom(String path) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 6,
                child: Image.file(File(path), fit: BoxFit.contain),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busyLabel != null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.kind.label)),
      body: Stack(
        children: [
          if (_permissionDenied)
            _PermissionDenied(onRetry: _captureMissing)
          else
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
                for (final side in widget.kind.sides) ...[
                  _SideCard(
                    kind: widget.kind,
                    side: side,
                    path: _originals[side],
                    onZoom: _zoom,
                    onCapture: busy ? null : () => _retake(side),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          if (busy)
            ColoredBox(
              color: Colors.black38,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_busyLabel!),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _complete && !busy ? _scan : null,
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Scan'),
        ),
      ),
    );
  }
}

class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.kind,
    required this.side,
    required this.path,
    required this.onZoom,
    required this.onCapture,
  });

  final DocumentKind kind;
  final DocumentSide side;
  final String? path;
  final ValueChanged<String> onZoom;
  final VoidCallback? onCapture;

  @override
  Widget build(BuildContext context) {
    final path = this.path;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    side.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: onCapture,
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: Text(path == null ? 'Scan' : 'Retake'),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: kind.aspectRatio,
            child: path == null
                ? const ColoredBox(
                    color: Colors.black12,
                    child: Center(child: Text('Not captured yet')),
                  )
                : GestureDetector(
                    onTap: () => onZoom(path),
                    child: Image.file(
                      File(path),
                      key: ValueKey(path),
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PermissionDenied extends StatelessWidget {
  const _PermissionDenied({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Camera permission is required to scan documents.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }
}
