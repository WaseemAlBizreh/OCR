import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';

class DocumentResultSheet extends StatefulWidget {
  const DocumentResultSheet({
    super.key,
    required this.result,
  });

  final DocumentScanResult result;

  @override
  State<DocumentResultSheet> createState() => _DocumentResultSheetState();
}

class _DocumentResultSheetState extends State<DocumentResultSheet> {
  bool _showRawOcr = false;
  bool _showComparison = false;

  @override
  Widget build(BuildContext context) {
    final prettyJson = const JsonEncoder.withIndent('  ').convert(
      widget.result.toDisplayJson(),
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            _buildHeader(context, prettyJson),
            if (widget.result.warnings.isNotEmpty) _buildWarnings(context),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFields(context),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Show raw OCR text'),
                      value: _showRawOcr,
                      onChanged: (value) => setState(() => _showRawOcr = value),
                    ),
                    if (_showRawOcr && widget.result.rawOcrText != null)
                      _buildMonospaceBlock(widget.result.rawOcrText!),
                    if (widget.result.ocrComparison != null) ...[
                      SwitchListTile(
                        title: const Text('Show OCR engine comparison'),
                        value: _showComparison,
                        onChanged: (value) =>
                            setState(() => _showComparison = value),
                      ),
                      if (_showComparison)
                        _buildComparison(widget.result.ocrComparison!),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Full JSON',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    _buildMonospaceBlock(prettyJson),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, String prettyJson) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Scan Result',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          IconButton(
            tooltip: 'Copy JSON',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: prettyJson));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('JSON copied to clipboard')),
              );
            },
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildWarnings(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.result.warnings
            .map(
              (warning) => Text(
                '• $warning',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildFields(BuildContext context) {
    final entries = widget.result.fields.entries
        .where((entry) => entry.value != null && '$entry.value'.isNotEmpty)
        .toList();

    if (entries.isEmpty) {
      return Text(
        'No structured fields extracted.',
        style: Theme.of(context).textTheme.bodyLarge,
      );
    }

    return Column(
      children: entries.map((entry) {
        final isArabicField = entry.key.toLowerCase().contains('arabic');
        final value = '${entry.value}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _labelForKey(entry.key),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 4),
              Directionality(
                textDirection:
                    isArabicField ? TextDirection.rtl : TextDirection.ltr,
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: isArabicField ? 18 : 16,
                      ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildComparison(OcrEngineComparison comparison) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ML Kit (${comparison.mlKitDurationMs ?? 0} ms)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        _buildMonospaceBlock(comparison.mlKitText ?? '(empty)'),
        const SizedBox(height: 12),
        Text(
          'Tesseract ara+eng (${comparison.tesseractDurationMs ?? 0} ms)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        _buildMonospaceBlock(comparison.tesseractText ?? '(empty)'),
      ],
    );
  }

  Widget _buildMonospaceBlock(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }

  String _labelForKey(String key) => switch (key) {
        'arabicName' => 'Arabic Name',
        'englishName' => 'English Name',
        'identityNumber' => 'Identity Number',
        'nationalNumber' => 'National Number',
        'idNumber' => 'ID Number',
        'dateOfBirth' => 'Date of Birth',
        'dateOfExpiry' => 'Date of Expiry',
        'placeOfBirth' => 'Place of Birth',
        'placeOfBirthEnglish' => 'Place of Birth (EN)',
        'placeOfBirthArabic' => 'Place of Birth (AR)',
        'placeOfIssue' => 'Place of Issue',
        'placeOfIssueEnglish' => 'Place of Issue (EN)',
        'placeOfIssueArabic' => 'Place of Issue (AR)',
        'issueDate' => 'Issue Date',
        'expiryDate' => 'Expiry Date',
        'issuingDate' => 'Issuing Date',
        'gender' => 'Gender',
        'sex' => 'Sex',
        'cardType' => 'Card Type',
        'cardSide' => 'Card Side',
        'bloodType' => 'Blood Type',
        'profession' => 'Profession',
        'address' => 'Address',
        'phone' => 'Phone',
        'serialNumber' => 'Serial Number',
        'nationality' => 'Nationality',
        'nationalityArabic' => 'Nationality (AR)',
        'nationalityEnglish' => 'Nationality (EN)',
        'passportType' => 'Passport Type',
        'passportNumber' => 'Passport Number',
        'fullNameEnglish' => 'Full Name (EN)',
        'fullNameArabic' => 'Full Name (AR)',
        'countryCode' => 'Country Code',
        'documentNumber' => 'Document Number',
        'surname' => 'Surname',
        'givenNames' => 'Given Names',
        'confidence' => 'Confidence',
        _ => key,
      };
}
