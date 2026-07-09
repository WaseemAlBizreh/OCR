import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mrz_scanner_plus/mrz_scanner_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:mrz/features/mrz_scan/domain/mrz_scan_result.dart';
import 'package:mrz/features/mrz_scan/presentation/widgets/json_result_sheet.dart';

@RoutePage()
class MrzScanPage extends StatefulWidget {
  const MrzScanPage({super.key});

  @override
  State<MrzScanPage> createState() => _MrzScanPageState();
}

class _MrzScanPageState extends State<MrzScanPage> {
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openMrzScanner());
  }

  Future<void> _openMrzScanner() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() => _permissionDenied = true);
      }
      return;
    }
    if (mounted) {
      setState(() => _permissionDenied = false);
    }

    if (!mounted) return;
    final result = await Navigator.of(context).push<MrzScanResult>(
      MaterialPageRoute(
        builder: (scanContext) => CameraScanPage(
          onResult: ({
            Map<String, dynamic>? frontPayload,
            Map<String, dynamic>? backPayload,
            String? frontSavedPath,
            String? backSavedPath,
          }) {
            Navigator.of(scanContext).pop(
              MrzScanResult(
                frontPayload: frontPayload,
                backPayload: backPayload,
                frontSavedPath: frontSavedPath,
                backSavedPath: backSavedPath,
              ),
            );
          },
        ),
      ),
    );
    if (!mounted || result == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => JsonResultSheet(resultJson: result.toDisplayJson()),
    );

    if (mounted) {
      _openMrzScanner();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) {
      return Scaffold(
        appBar: AppBar(title: const Text('OCR Test')),
        body: Center(
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
                  onPressed: _openMrzScanner,
                  child: const Text('Grant Permission'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
