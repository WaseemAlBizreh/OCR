import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mrz/core/UI/routes/router.gr.dart';
import 'package:mrz/features/arabic_document_scan/domain/arabic_country.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';
import 'package:mrz/features/arabic_document_scan/domain/id_card_side.dart';

@RoutePage()
class DocumentScanHomePage extends StatefulWidget {
  const DocumentScanHomePage({super.key});

  @override
  State<DocumentScanHomePage> createState() => _DocumentScanHomePageState();
}

class _DocumentScanHomePageState extends State<DocumentScanHomePage> {
  DocumentType _documentType = DocumentType.arabicId;
  ArabicCountry _country = ArabicCountry.sudan;
  IdCardSide _idCardSide = IdCardSide.front;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Arabic Document Scanner')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Select document type',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DocumentType.values.map((type) {
              final selected = _documentType == type;
              return ChoiceChip(
                label: Text(type.label),
                selected: selected,
                onSelected: (value) {
                  if (!value) return;
                  setState(() => _documentType = type);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            _captureHint,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Text(
            'Select country',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<ArabicCountry>(
            initialValue: _country,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Country',
            ),
            items: ArabicCountry.values
                .map(
                  (country) => DropdownMenuItem(
                    value: country,
                    child: Text(
                      '${country.englishName} (${country.arabicName})',
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _country = value;
                  if (value != ArabicCountry.sudan) {
                    _idCardSide = IdCardSide.front;
                  }
                });
              }
            },
          ),
          if (_documentType == DocumentType.arabicId &&
              _country == ArabicCountry.sudan) ...[
            const SizedBox(height: 24),
            Text(
              'ID card side',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<IdCardSide>(
              segments: IdCardSide.values
                  .map(
                    (side) => ButtonSegment(
                      value: side,
                      label: Text(side.label),
                    ),
                  )
                  .toList(),
              selected: {_idCardSide},
              onSelectionChanged: (selection) {
                setState(() => _idCardSide = selection.first);
              },
            ),
          ],
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () {
              context.router.push(
                DocumentCaptureRoute(
                  documentType: _documentType,
                  countryCode: _country.code,
                  idCardSide: _documentType == DocumentType.arabicId &&
                          _country == ArabicCountry.sudan
                      ? _idCardSide
                      : IdCardSide.front,
                ),
              );
            },
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Continue to capture'),
          ),
        ],
      ),
    );
  }

  String get _captureHint {
    if (_documentType == DocumentType.arabicId &&
        _country == ArabicCountry.sudan) {
      return _idCardSide.captureHint;
    }
    return _documentType.captureHint;
  }
}
