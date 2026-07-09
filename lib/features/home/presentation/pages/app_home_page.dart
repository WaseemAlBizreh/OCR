import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mrz/core/UI/routes/router.gr.dart';

@RoutePage()
class AppHomePage extends StatelessWidget {
  const AppHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR Test')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose a scanning mode',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'MRZ camera flow for passports and ID backs, or Arabic document OCR for national IDs.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.router.push(const MrzScanRoute()),
              icon: const Icon(Icons.camera_outlined),
              label: const Text('MRZ Camera Scanner'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  context.router.push(const DocumentScanHomeRoute()),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Arabic Document Scanner'),
            ),
          ],
        ),
      ),
    );
  }
}
