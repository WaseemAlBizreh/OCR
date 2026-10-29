/// What a civil registry certificate scan returns.
class CivilRegistryResult {
  CivilRegistryResult({
    required this.fields,
    this.confidence = const {},
    this.warnings = const [],
    this.imagePath,
    this.rawText = '',
    this.rawMlKit = '',
    DateTime? scannedAt,
  }) : scannedAt = scannedAt ?? DateTime.now();

  /// Keyed by `CertificateField.name`; null when a field was not found.
  final Map<String, String?> fields;

  /// OCR confidence (0..1) of the line each value came from.
  final Map<String, double> confidence;
  final List<String> warnings;
  final String? imagePath;

  /// What OCR read before parsing. Debug aid.
  final String rawText;

  /// ML Kit's own reading, kept apart from [rawText] to see which engine
  /// missed a value.
  final String rawMlKit;
  final DateTime scannedAt;

  Map<String, dynamic> toJson() => {
        'documentKind': 'civilRegistryCertificate',
        'fields': fields,
        'confidence': confidence,
        'warnings': warnings,
        if (imagePath != null) 'image': imagePath,
        if (rawText.isNotEmpty) 'rawText': rawText,
        if (rawMlKit.isNotEmpty) 'rawMlKit': rawMlKit,
        'scannedAt': scannedAt.toIso8601String(),
      };
}
