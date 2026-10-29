import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mrz/core/UI/routes/router.gr.dart';
import 'package:mrz/features/identity_scan/domain/document_kind.dart';

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
              'Choose a document to scan',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Scan the front and back of a Sudan ID, a passport, or a civil registry certificate. The MRZ is validated and combined with the printed fields.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.router.push(
                IdentityFlowRoute(kind: DocumentKind.sudanId),
              ),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Sudan ID (front + back)'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => context.router.push(
                IdentityFlowRoute(kind: DocumentKind.passport),
              ),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Passport'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => context.router.push(
                IdentityFlowRoute(kind: DocumentKind.civilRegistryCertificate),
              ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Civil registry certificate (A4)'),
            ),
          ],
        ),
      ),
    );
  }
}
