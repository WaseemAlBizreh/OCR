import 'package:injectable/injectable.dart';
import 'package:mrz/features/arabic_document_scan/data/generic_arabic_extractor.dart';
import 'package:mrz/features/arabic_document_scan/data/passport_mrz_extractor.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';
import 'package:mrz/features/arabic_document_scan/domain/id_card_side.dart';

@lazySingleton
class DocumentScanService {
  DocumentScanService(
    this._passportMrzExtractor,
    this._genericArabicExtractor,
  );

  final PassportMrzExtractor _passportMrzExtractor;
  final GenericArabicExtractor _genericArabicExtractor;

  Future<DocumentScanResult> scan({
    required DocumentType documentType,
    required String imagePath,
    String? countryCode,
    IdCardSide idCardSide = IdCardSide.front,
  }) async {
    return switch (documentType) {
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
}
