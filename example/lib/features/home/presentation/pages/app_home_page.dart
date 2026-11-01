import 'package:flutter/material.dart';
import 'package:idlens/idlens.dart';

import '../widgets/json_result_sheet.dart';

/// Demo home: one button per document, each calling the package the way a
/// host app would.
class AppHomePage extends StatelessWidget {
  const AppHomePage({super.key});

  static const _idLens = IdLens();

  Future<void> _run(
    BuildContext context,
    Future<ScanOutcome?> Function() scan,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await scan();
      if (result == null || !context.mounted) {
        return; // cancelled, nothing captured
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => JsonResultSheet(resultJson: result.toJson()),
      );
      // A real app would upload result.images first; the demo just cleans up.
      await result.dispose();
    } on ScanException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Scan not started: ${e.reason.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IdLens Demo')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose a document to scan',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a Sudan ID card, a passport, or a civil registry certificate. '
              'The result always comes back with the images, even when reading '
              'had problems.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => _run(context, () => _idLens.scanIdCard(context)),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Sudan ID (front + back)'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () =>
                  _run(context, () => _idLens.scanPassport(context)),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Passport'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () =>
                  _run(context, () => _idLens.scanCivilRegistry(context)),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Civil registry certificate (A4)'),
            ),
          ],
        ),
      ),
    );
  }
}
