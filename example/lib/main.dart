import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:idlens/idlens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IdLens Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6623)),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// IdLens holds no state, so one const instance is enough.
  static const _idLens = IdLens();

  // The two options, as switches.
  bool _showTips = true;
  bool _requireValidMrz = false;

  /// The last ID card scan, kept so its images can be read again without UI.
  IdCardResult? _lastIdCard;

  // 1. The three scans that open idlens' own screens. Each returns a typed
  //    result, or null when the user leaves before capturing anything.

  Future<void> _scanIdCard() => _run(() async {
    final result = await _idLens.scanIdCard(
      context,
      options: IdCardScanOptions(
        showTips: _showTips,
        requireValidMrz: _requireValidMrz,
      ),
    );
    // Keep the images of this scan; free the previous scan's temp files.
    if (result != null) {
      await _lastIdCard?.dispose();
      setState(() => _lastIdCard = result);
    }
    return result;
  });

  Future<void> _scanPassport() => _run(
    () => _idLens.scanPassport(
      context,
      options: PassportScanOptions(
        showTips: _showTips,
        requireValidMrz: _requireValidMrz,
      ),
    ),
  );

  Future<void> _scanCivilRegistry() => _run(
    () => _idLens.scanCivilRegistry(
      context,
      // A certificate has no MRZ, so there is no requireValidMrz here.
      options: CivilRegistryScanOptions(showTips: _showTips),
    ),
  );

  // 2. The same scan without any UI: pass the image files you already have.
  //    Here they come from the last ID card scan; in your app they could come
  //    from your own camera, a gallery picker or a server.

  Future<void> _readLastIdCardAgain() => _run(() {
    final last = _lastIdCard!;
    return _idLens.processIdCard(
      front: last.imageFor(DocumentSide.front)!.file,
      back: last.imageFor(DocumentSide.back)!.file,
    );
  });

  /// Runs [scan], shows whatever it returns and turns a [ScanException] (no
  /// image could be captured at all) into a message.
  Future<void> _run(Future<ScanOutcome?> Function() scan) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await scan();
      if (result == null || !mounted) {
        return; // The user left before capturing anything.
      }
      await _showResult(result);
      // A real app would upload result.images first. Only temporary files are
      // deleted; files passed to process... are left alone. The last ID card
      // scan is kept for the "read again" button.
      if (result != _lastIdCard) await result.dispose();
    } on ScanException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Scan not started: ${e.reason.name}')),
      );
    }
  }

  Future<void> _showResult(ScanOutcome result) {
    // Every result has the same members: status, issues, warnings, images,
    // mrz, fields and toJson(). The typed getters (result.dateOfBirth, ...)
    // are on the concrete class.
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ResultSheet(result: result),
    );
  }

  @override
  void dispose() {
    _lastIdCard?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IdLens Demo')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Scan with idlens\' screens',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _scanIdCard,
            icon: const Icon(Icons.badge_outlined),
            label: const Text('scanIdCard (front + back)'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _scanPassport,
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('scanPassport'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _scanCivilRegistry,
            icon: const Icon(Icons.description_outlined),
            label: const Text('scanCivilRegistry (A4)'),
          ),
          const SizedBox(height: 24),
          Text('Options', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('showTips'),
            subtitle: const Text('Show the photo tips before the camera'),
            value: _showTips,
            onChanged: (value) => setState(() => _showTips = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('requireValidMrz'),
            subtitle: const Text('Only allow Retake while the MRZ fails'),
            value: _requireValidMrz,
            onChanged: (value) => setState(() => _requireValidMrz = value),
          ),
          const SizedBox(height: 16),
          Text(
            'Read files without any UI',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _lastIdCard == null ? null : _readLastIdCardAgain,
            icon: const Icon(Icons.image_search_outlined),
            label: const Text('processIdCard (re-read last scan)'),
          ),
          if (_lastIdCard == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Scan an ID card first to enable this.'),
            ),
        ],
      ),
    );
  }
}

/// Shows a result: its status and issues first, then the full JSON.
class _ResultSheet extends StatelessWidget {
  const _ResultSheet({required this.result});

  final ScanOutcome result;

  @override
  Widget build(BuildContext context) {
    final json = const JsonEncoder.withIndent('  ').convert(result.toJson());
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${result.status.name}  ·  '
                    '${result.images.length} image(s)'
                    '${result.issues.isEmpty ? '' : '  ·  ${result.issues.map((i) => i.name).join(', ')}'}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy JSON',
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: json));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('JSON copied')),
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                json,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
