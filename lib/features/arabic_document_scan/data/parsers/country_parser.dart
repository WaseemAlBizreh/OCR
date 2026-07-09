import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';

abstract class CountryParser {
  String get countryCode;

  DocumentScanResult parse(
    String ocrText, {
    required String imagePath,
    OcrEngineComparison? ocrComparison,
  });
}
