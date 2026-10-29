import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mrz/core/config/injection.dart';
import 'package:mrz/features/identity_scan/data/identity_scan_service.dart';
import 'package:mrz/features/identity_scan/domain/document_kind.dart';
import 'package:mrz/features/identity_scan/presentation/widgets/card_camera_page.dart';
import 'package:mrz/features/identity_scan/presentation/widgets/json_result_sheet.dart';
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
  bool _showTips = true;
  bool _capturing = false;

  IdentityScanService get _service => locator<IdentityScanService>();

  bool get _complete =>
      widget.kind.sides.every((side) => _originals.containsKey(side));

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
    if (_capturing) return; // a second tap must not open a second camera
    _capturing = true;
    try {
      if (!await _ensureCamera()) return;
      for (final side in widget.kind.sides) {
        if (_originals.containsKey(side)) continue;
        if (!await _capture(side)) return;
      }
    } finally {
      _capturing = false;
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
    final wasComplete = _complete;
    setState(() {
      _originals[side] = path;
      // The last page is in: the tips have done their job, so fold them away
      // and leave only the Photo tips button. A retake afterwards keeps
      // whatever the user chose.
      if (!wasComplete && _complete) _showTips = false;
    });
    if (stale != null) await _service.discard([stale]);
    return true;
  }

  Future<void> _retake(DocumentSide side) async {
    if (_capturing) return;
    _capturing = true;
    try {
      if (!await _ensureCamera()) return;
      await _capture(side);
    } finally {
      _capturing = false;
    }
  }

  Future<void> _scan() async {
    if (!_complete || _busyLabel != null) return;
    setState(() => _busyLabel = 'Scanning document...');
    try {
      final stopwatch = Stopwatch()..start();
      final result = await _service.scan(
        kind: widget.kind,
        imagePaths: {
          for (final side in widget.kind.sides) side: _originals[side]!,
        },
      );
      stopwatch.stop();
      if (!mounted) return;
      setState(() => _busyLabel = null);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => JsonResultSheet(
          resultJson: {
            ...result.toJson(),
            'engine': 'classic',
            'scanMs': stopwatch.elapsedMilliseconds,
          },
        ),
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
      appBar: AppBar(
        title: Text(widget.kind.label),
      ),
      body: Stack(
        children: [
          if (_permissionDenied)
            _PermissionDenied(onRetry: _captureMissing)
          else
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
                if (_showTips || _originals.isEmpty)
                  _InstructionCard(
                    kind: widget.kind,
                    // The notes stay until the first photo is taken, and the
                    // card carries the button that starts capturing.
                    onClose: _originals.isEmpty
                        ? null
                        : () => setState(() => _showTips = false),
                    onStart: _originals.isEmpty && !busy ? _captureMissing : null,
                  )
                else
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.tonalIcon(
                      onPressed: () => setState(() => _showTips = true),
                      icon: const Icon(Icons.lightbulb_outline),
                      label: const Text('Photo tips'),
                    ),
                  ),
                const SizedBox(height: 8),
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
      // Before the first photo, the card above holds the start button.
      bottomNavigationBar: _originals.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: busy ? null : (_complete ? _scan : _captureMissing),
                icon: Icon(
                  _complete
                      ? Icons.document_scanner_outlined
                      : Icons.camera_alt_outlined,
                ),
                label: Text(_complete ? 'Scan' : 'Continue capturing'),
              ),
            ),
    );
  }
}

/// Tells the user how to take good photos and to retake a poor one: fields
/// that cannot be read from a blurry or cut-off photo stay empty.
class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.kind, this.onClose, this.onStart});

  final DocumentKind kind;

  /// Starts capturing; null once capturing has begun.
  final VoidCallback? onStart;

  /// Null while the card cannot be dismissed yet.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      color: colors.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, color: colors.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Before you scan',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: 'Hide tips',
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                    color: colors.onSecondaryContainer,
                  )
                else
                  const SizedBox(height: 48), // keeps the header height steady
              ],
            ),
            _TipSection(title: 'Taking the photo', tips: kind.photoTips),
            const SizedBox(height: 12),
            _TipSection(title: 'Check each photo', tips: kind.checkTips),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.refresh, size: 20, color: colors.onSurface),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'If a photo is blurry, cut off or has glare, tap Retake. '
                        'A clear photo lets more data be read; anything that '
                        'cannot be read stays empty.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (onStart != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Start capturing'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  kind.captureOrder,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TipSection extends StatelessWidget {
  const _TipSection({required this.title, required this.tips});

  final String title;
  final List<String> tips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSecondaryContainer;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: theme.textTheme.bodyMedium?.copyWith(color: color)),
                  Expanded(
                    child: Text(
                      tip,
                      style: theme.textTheme.bodyMedium?.copyWith(color: color),
                    ),
                  ),
                ],
              ),
            ),
        ],
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
                  label: Text(path == null ? 'Capture' : 'Retake'),
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
