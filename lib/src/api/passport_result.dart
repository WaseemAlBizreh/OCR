import 'package:idlens/src/api/id_card_result.dart';
import 'package:idlens/src/domain/document_kind.dart';

/// The result of scanning the data page of a passport from any country.
class PassportResult extends IdentityDocumentResult {
  /// Creates a result. Built by idlens; apps read it.
  const PassportResult({
    required super.status,
    super.issue,
    super.fieldsToCheck,
    super.images,
    super.diagnostics,
    required super.scannedAt,
    super.fields,
    super.mrz,
  }) : super(documentKind: DocumentKind.passport);

  /// Nationality as printed, in English.
  String? get nationalityText => fields['nationalityText'] as String?;

  /// Nationality as printed, in Arabic.
  String? get nationalityTextArabic =>
      fields['nationalityTextArabic'] as String?;

  /// Issuing country's name in English.
  String? get issuingCountryName => fields['issuingCountryName'] as String?;

  /// Place of birth as printed, in Arabic.
  String? get placeOfBirthArabic => fields['placeOfBirthArabic'] as String?;

  /// Place of issue as printed, in Arabic.
  String? get placeOfIssueArabic => fields['placeOfIssueArabic'] as String?;
}
