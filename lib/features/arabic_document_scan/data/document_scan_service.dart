import 'package:injectable/injectable.dart';
import 'package:mrz/features/arabic_document_scan/data/arabic_ocr_engine.dart';
import 'package:mrz/features/arabic_document_scan/data/ocr_debug_log.dart';
import 'package:mrz/features/arabic_document_scan/data/generic_arabic_extractor.dart';
import 'package:mrz/features/arabic_document_scan/data/passport_mrz_extractor.dart';
import 'package:mrz/features/arabic_document_scan/data/saudi_id_extractor.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';
import 'package:mrz/features/arabic_document_scan/domain/id_card_side.dart';

@lazySingleton
class DocumentScanService {
  DocumentScanService(
    this._saudiIdExtractor,
    this._passportMrzExtractor,
    this._genericArabicExtractor,
    this._ocrEngine,
  );

  final SaudiIdExtractor _saudiIdExtractor;
  final PassportMrzExtractor _passportMrzExtractor;
  final GenericArabicExtractor _genericArabicExtractor;
  final ArabicOcrEngine _ocrEngine;

  Future<DocumentScanResult> scan({
    required DocumentType documentType,
    required String imagePath,
    String? countryCode,
    IdCardSide idCardSide = IdCardSide.front,
  }) async {
    return switch (documentType) {
      DocumentType.saudiId => _scanSaudiId(imagePath),
      DocumentType.passport => _passportMrzExtractor.extract(
          imagePath: imagePath,
          countryCode: countryCode,
        ),
      DocumentType.arabicId => _genericArabicExtractor.extract(
          imagePath: imagePath,
          countryCode: countryCode ?? 'sd',
          idCardSide: idCardSide,
        ),
    };
  }

  Future<DocumentScanResult> _scanSaudiId(String imagePath) async {
    final comparison = await _ocrEngine.compareEngines(imagePath);
    final ocrText = _ocrEngine.mergeForArabicParsing(comparison);

    logRawOcrBeforeParsing(
      context: 'saudiId',
      mergedText: ocrText,
      tesseractText: comparison.tesseractText,
      mlKitText: comparison.mlKitText,
    );

    return _saudiIdExtractor.extract(
      imagePath: imagePath,
      ocrComparison: comparison,
      ocrTextOverride: ocrText,
    );
  }
}
