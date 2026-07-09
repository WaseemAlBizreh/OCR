import 'package:mrz/features/arabic_document_scan/domain/arabic_country.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';

class OcrEngineComparison {
  const OcrEngineComparison({
    this.mlKitText,
    this.tesseractText,
    this.mlKitDurationMs,
    this.tesseractDurationMs,
  });

  final String? mlKitText;
  final String? tesseractText;
  final int? mlKitDurationMs;
  final int? tesseractDurationMs;

  Map<String, dynamic> toJson() => {
        'mlKitText': mlKitText,
        'tesseractText': tesseractText,
        'mlKitDurationMs': mlKitDurationMs,
        'tesseractDurationMs': tesseractDurationMs,
      };
}

class DocumentScanResult {
  DocumentScanResult({
    required this.documentType,
    this.countryCode,
    required this.fields,
    this.rawOcrText,
    this.imagePath,
    this.mrzResult,
    this.warnings = const [],
    this.ocrComparison,
    DateTime? scannedAt,
  }) : scannedAt = scannedAt ?? DateTime.now();

  final DocumentType documentType;
  final String? countryCode;
  final Map<String, dynamic> fields;
  final String? rawOcrText;
  final String? imagePath;
  final Map<String, dynamic>? mrzResult;
  final List<String> warnings;
  final OcrEngineComparison? ocrComparison;
  final DateTime scannedAt;

  ArabicCountry? get country => ArabicCountry.fromCode(countryCode);

  Map<String, dynamic> toDisplayJson() => {
        'documentType': documentType.name,
        'countryCode': countryCode,
        'fields': fields,
        'rawOcrText': rawOcrText,
        'imagePath': imagePath,
        'mrzResult': mrzResult,
        'warnings': warnings,
        'ocrComparison': ocrComparison?.toJson(),
        'scannedAt': scannedAt.toIso8601String(),
      };
}
