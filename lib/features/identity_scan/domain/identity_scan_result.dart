import 'package:mrz/features/identity_scan/domain/document_kind.dart';
import 'package:mrz/features/identity_scan/domain/mrz_data.dart';

class IdentityScanResult {
  IdentityScanResult({
    required this.documentKind,
    required this.identity,
    this.frontFields,
    this.backFields,
    this.dataPageFields,
    this.mrz,
    this.mrzAttempts = const [],
    this.imagePaths = const {},
    this.rawText = const {},
    this.warnings = const [],
    DateTime? scannedAt,
  }) : scannedAt = scannedAt ?? DateTime.now();

  final DocumentKind documentKind;

  /// Merged, cross-checked fields: the payload consumers should read.
  final Map<String, dynamic> identity;
  final Map<String, String?>? frontFields;
  final Map<String, String?>? backFields;

  /// Printed fields of a passport data page.
  final Map<String, String?>? dataPageFields;
  final MrzData? mrz;
  final List<Map<String, dynamic>> mrzAttempts;
  final Map<DocumentSide, String> imagePaths;

  /// What OCR read from a passport data page, before parsing. Debug aid for
  /// the printed-field parser.
  final Map<DocumentSide, String> rawText;
  final List<String> warnings;
  final DateTime scannedAt;

  Map<String, dynamic> toJson() => {
        'documentKind': documentKind.name,
        'identity': identity,
        'mrz': mrz?.toJson(),
        'front': frontFields,
        'back': backFields,
        if (dataPageFields != null) 'dataPage': dataPageFields,
        'warnings': warnings,
        'images': {
          for (final entry in imagePaths.entries) entry.key.name: entry.value,
        },
        if (rawText.isNotEmpty)
          'rawText': {
            for (final entry in rawText.entries) entry.key.name: entry.value,
          },
        'mrzAttempts': mrzAttempts,
        'scannedAt': scannedAt.toIso8601String(),
      };
}
