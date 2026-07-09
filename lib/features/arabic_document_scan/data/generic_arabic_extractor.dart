import 'package:injectable/injectable.dart';
import 'package:mrz/features/arabic_document_scan/data/arabic_ocr_engine.dart';
import 'package:mrz/features/arabic_document_scan/data/ocr_debug_log.dart';
import 'package:mrz/features/arabic_document_scan/data/parsers/country_parser_factory.dart';
import 'package:mrz/features/arabic_document_scan/data/parsers/generic_arabic_id_parser.dart';
import 'package:mrz/features/arabic_document_scan/data/parsers/sudan_id_back_parser.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';
import 'package:mrz/features/arabic_document_scan/domain/id_card_side.dart';

@lazySingleton
class GenericArabicExtractor {
  GenericArabicExtractor(this._ocrEngine);

  final ArabicOcrEngine _ocrEngine;

  Future<DocumentScanResult> extract({
    required String imagePath,
    required String countryCode,
    IdCardSide idCardSide = IdCardSide.front,
  }) async {
    final comparison = await _ocrEngine.compareEngines(imagePath);
    final ocrText = _ocrEngine.mergeForArabicParsing(comparison);

    logRawOcrBeforeParsing(
      context: 'arabicId/$countryCode/${idCardSide.name}',
      mergedText: ocrText,
      tesseractText: comparison.tesseractText,
      mlKitText: comparison.mlKitText,
    );

    if (ocrText == null || ocrText.isEmpty) {
      return DocumentScanResult(
        documentType: DocumentType.arabicId,
        countryCode: countryCode,
        fields: const {},
        imagePath: imagePath,
        warnings: const [
          'No text recognized in image. '
          'Ensure good lighting, flat card, and try gallery import.',
        ],
        ocrComparison: comparison,
      );
    }

    if (countryCode == 'sd' && idCardSide == IdCardSide.back) {
      return SudanIdBackParser().parseAsync(
        ocrText,
        imagePath: imagePath,
        ocrComparison: comparison,
      );
    }

    final parser = CountryParserFactory.forCountry(
      countryCode: countryCode,
      side: idCardSide,
    );

    if (parser != null) {
      return parser.parse(
        ocrText,
        imagePath: imagePath,
        ocrComparison: comparison,
      );
    }

    return GenericArabicIdParser(countryCode: countryCode).parse(
      ocrText,
      imagePath: imagePath,
      ocrComparison: comparison,
    );
  }
}
