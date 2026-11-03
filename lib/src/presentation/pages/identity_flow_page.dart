import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:idlens/src/api/scan_exception.dart';
import 'package:idlens/src/api/scan_options.dart';
import 'package:idlens/src/api/scan_outcome.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/presentation/scan_issue_text.dart';
import 'package:idlens/src/presentation/widgets/card_camera_page.dart';
import 'package:idlens/src/scan_runner.dart';
import 'package:idlens/src/services.dart';

/// How the flow page ended. [outcome] is null when nothing was captured, and
/// [failure] then says why, if the camera was the reason.
class ScanFlowExit {
  const ScanFlowExit({this.outcome, this.failure});

  final ScanOutcome? outcome;
  final ScanException? failure;
}

/// Capture every page of the document, preview it, then scan it and pop with
/// a [ScanFlowExit].
class IdentityFlowPage extends StatefulWidget {
  const IdentityFlowPage({
    super.key,
    required this.kind,
    this.options = const ScanOptions(),
  });

  final DocumentKind kind;
  final ScanOptions options;

  @override
  State<IdentityFlowPage> createState() => _IdentityFlowPageState();
}

class _IdentityFlowPageState extends State<IdentityFlowPage> {
  final Map<DocumentSide, String> _originals = {};
  final _runner = ScanRunner();
  String? _busyLabel;
  ScanException? _cameraFailure;
  late bool _showTips = widget.options.showTips;
  bool _capturing = false;

  /// True once the captured files belong to a returned result; they must not
  /// be deleted then.
  bool _handedOff = false;

  bool get _permissionDenied =>
      _cameraFailure?.reason == ScanFailureReason.permissionDenied;

  bool get _complete =>
      widget.kind.sides.every((side) => _originals.containsKey(side));

  @override
  void initState() {
    super.initState();
    if (!widget.options.showTips) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _captureMissing();
      });
    }
  }

  @override
  void dispose() {
    if (!_handedOff) _discard(_originals.values);
    super.dispose();
  }

  Future<void> _discard(Iterable<String> paths) async {
    for (final path in paths) {
      await IdLensServices.instance.imageOps.deleteTemp(path);
    }
  }

  /// Leaves the page. What was captured is handed back as an incomplete
  /// result, so the host app can still keep the images.
  void _leave() {
    if (_busyLabel != null) return;
    final ScanFlowExit exit;
    if (_originals.isEmpty) {
      exit = ScanFlowExit(failure: _cameraFailure);
    } else {
      _handedOff = true;
      exit = ScanFlowExit(outcome: _runner.incomplete(widget.kind, _originals));
    }
    Navigator.of(context).pop(exit);
  }

  /// Walks the sides in order (front, then back) until all are captured.
  Future<void> _captureMissing() async {
    if (_capturing) return; // a second tap must not open a second camera
    _capturing = true;
    try {
      for (final side in widget.kind.sides) {
        if (_originals.containsKey(side)) continue;
        if (!await _capture(side)) return;
      }
    } finally {
      _capturing = false;
    }
  }

  Future<bool> _capture(DocumentSide side) async {
    final result = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CardCameraPage(kind: widget.kind, side: side),
      ),
    );
    if (!mounted) return false;
    if (result is ScanException) {
      setState(() => _cameraFailure = result);
      if (!_permissionDenied) {
        _toast('Camera unavailable. ${result.message ?? ''}');
      }
      return false;
    }
    if (result is! String) return false;

    final stale = _originals[side];
    final wasComplete = _complete;
    setState(() {
      _cameraFailure = null;
      _originals[side] = result;
      // The last page is in: the tips have done their job, so fold them away
      // and leave only the Photo tips button. A retake afterwards keeps
      // whatever the user chose.
      if (!wasComplete && _complete) _showTips = false;
    });
    if (stale != null) await _discard([stale]);
    return true;
  }

  Future<void> _retake(DocumentSide side) async {
    if (_capturing) return;
    _capturing = true;
    try {
      await _capture(side);
    } finally {
      _capturing = false;
    }
  }

  /// The page whose photo has no MRZ, so only its clarity and framing can be
  /// judged before the scan.
  DocumentSide? get _precheckSide => switch (widget.kind) {
    DocumentKind.sudanId => DocumentSide.front,
    DocumentKind.civilRegistryCertificate => DocumentSide.page,
    DocumentKind.passport => null,
  };

  Future<void> _scan() async {
    if (!_complete || _busyLabel != null) return;
    setState(() => _busyLabel = 'Scanning document...');
    try {
      final side = _precheckSide;
      PhotoCheck? check;
      if (side != null) {
        // A blurry or cut-off photo is reported before OCR runs, not after.
        check = await _runner.checkPhoto(_originals[side]!, widget.kind);
        final issue = check.issue;
        if (issue != null) {
          if (!mounted) return;
          setState(() => _busyLabel = null);
          final go = await _confirmContinue(
            ScanNotice.forIssue(issue),
            sides: [side],
          );
          if (!go) return;
          setState(() => _busyLabel = 'Scanning document...');
        }
      }

      final outcome = switch (widget.kind) {
        DocumentKind.sudanId => await _runner.idCard(
          _originals,
          temporary: true,
          frontCheck: check,
          timeout: widget.options.timeout,
        ),
        DocumentKind.passport => await _runner.passport(
          _originals[DocumentSide.dataPage]!,
          temporary: true,
          timeout: widget.options.timeout,
        ),
        DocumentKind.civilRegistryCertificate => await _runner.civilRegistry(
          _originals[DocumentSide.page]!,
          temporary: true,
          pageCheck: check,
          timeout: widget.options.timeout,
        ),
      };
      if (!mounted) return;

      final notice = ScanNotice.after(
        outcome,
        alreadyShown: check?.issue,
        shownSide: side,
      );
      if (notice != null) {
        setState(() => _busyLabel = null);
        final blocked =
            widget.options.requireValidMrz && ScanNotice.hasMrzProblem(outcome);
        final sides = notice.readAgain
            ? const <DocumentSide>[]
            : outcome.issueSides;
        if (!await _confirmContinue(notice, sides: sides, blocked: blocked)) {
          // The photos were fine: read them again rather than retaking.
          if (notice.readAgain && mounted) unawaited(_scan());
          return;
        }
      }
      if (!mounted) return;
      _handedOff = true;
      Navigator.of(context).pop(ScanFlowExit(outcome: outcome));
    } catch (e) {
      if (mounted) {
        setState(() => _busyLabel = null);
        _toast('Scan failed: $e');
      }
    }
  }

  /// Tells the user what is wrong. Returns true when they choose to continue
  /// anyway, false when they retake (or try again, when the photos are fine).
  /// When [blocked] (an MRZ problem with `requireValidMrz`), only Retake is
  /// offered.
  Future<bool> _confirmContinue(
    ScanNotice notice, {
    List<DocumentSide> sides = const [],
    bool blocked = false,
  }) async {
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          sides.isEmpty || widget.kind.sides.length < 2
              ? notice.title
              : '${_sidesLabel(sides)}: ${notice.title}',
        ),
        content: Text(notice.message),
        actions: [
          if (!blocked)
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Use anyway'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(notice.readAgain ? 'Try again' : 'Retake'),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  /// "Front", "Back" or "Front and back".
  static String _sidesLabel(List<DocumentSide> sides) => [
    sides.first.label,
    for (final side in sides.skip(1)) side.label.toLowerCase(),
  ].join(' and ');

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    final hasTips = widget.options.showTips;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.kind.label)),
        body: Stack(
          children: [
            if (_permissionDenied)
              _PermissionDenied(onRetry: _captureMissing)
            else
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  if (hasTips && (_showTips || _originals.isEmpty))
                    _InstructionCard(
                      kind: widget.kind,
                      // The notes stay until the first photo is taken, and the
                      // card carries the button that starts capturing.
                      onClose: _originals.isEmpty
                          ? null
                          : () => setState(() => _showTips = false),
                      onStart: _originals.isEmpty && !busy
                          ? _captureMissing
                          : null,
                    )
                  else if (hasTips)
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
        // With the tips page, its card holds the start button until the first
        // photo is taken.
        bottomNavigationBar:
            (hasTips && _originals.isEmpty) || _permissionDenied
            ? null
            : SafeArea(
                minimum: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : (_complete ? _scan : _captureMissing),
                  icon: Icon(
                    _complete
                        ? Icons.document_scanner_outlined
                        : Icons.camera_alt_outlined,
                  ),
                  label: Text(
                    _complete
                        ? 'Scan'
                        : (_originals.isEmpty
                              ? 'Start capturing'
                              : 'Continue capturing'),
                  ),
                ),
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
                Icon(
                  Icons.lightbulb_outline,
                  color: colors.onSecondaryContainer,
                ),
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
                  Text(
                    '•  ',
                    style: theme.textTheme.bodyMedium?.copyWith(color: color),
                  ),
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
              'Camera permission is required to scan documents. If the '
              'permission prompt does not appear, enable camera access for '
              'this app in the system settings.',
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
