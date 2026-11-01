import 'package:idlens/src/api/scan_outcome.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/mrz_data.dart';

/// Fields shared by documents with a machine-readable zone: the ID card and
/// the passport. Values come from the MRZ when its own check digit passed,
/// and from the printed text otherwise. Anything not read is null.
abstract class IdentityDocumentResult extends ScanOutcome {
  /// Creates a result. Built by idlens; apps read it.
  const IdentityDocumentResult({
    required super.status,
    required super.documentKind,
    super.issues,
    super.warnings,
    super.images,
    super.diagnostics,
    required super.scannedAt,
    this.fields = const {},
    this.mrz,
  });

  @override
  final Map<String, dynamic> fields;

  @override
  final MrzData? mrz;

  /// The document number.
  String? get documentNumber => fields['documentNumber'] as String?;

  /// The national number printed on the document (or in the MRZ).
  String? get nationalNumber => fields['nationalNumber'] as String?;

  /// Full name as printed, in Arabic.
  String? get arabicName => fields['arabicName'] as String?;

  /// Full name in Latin letters, from the MRZ when it is available.
  String? get englishName => fields['englishName'] as String?;

  /// Surname, from the MRZ.
  String? get surname => fields['surname'] as String?;

  /// Given names, from the MRZ.
  String? get givenNames => fields['givenNames'] as String?;

  /// Date of birth.
  DateTime? get dateOfBirth => parseScanDate(fields['dateOfBirth']);

  /// Sex as printed in the MRZ: `M`, `F` or `<`.
  String? get sex => fields['sex'] as String?;

  /// Nationality as a three-letter code, such as `SDN`.
  String? get nationality => fields['nationality'] as String?;

  /// Issuing country as a three-letter code.
  String? get issuingCountry => fields['issuingCountry'] as String?;

  /// Date the document was issued.
  DateTime? get issueDate => parseScanDate(fields['issueDate']);

  /// Date the document expires.
  DateTime? get expiryDate => parseScanDate(fields['expiryDate']);

  /// Place of birth as printed.
  String? get placeOfBirth => fields['placeOfBirth'] as String?;

  /// Place of issue as printed.
  String? get placeOfIssue => fields['placeOfIssue'] as String?;

  /// Whether the expiry date is in the past, or null when it is unknown.
  bool? get isExpired {
    final expiry = expiryDate;
    if (expiry == null) return null;
    final now = DateTime.now();
    return expiry.isBefore(DateTime(now.year, now.month, now.day));
  }
}

/// The result of scanning a Sudan ID card: front and back.
class IdCardResult extends IdentityDocumentResult {
  /// Creates a result. Built by idlens; apps read it.
  const IdCardResult({
    required super.status,
    super.issues,
    super.warnings,
    super.images,
    super.diagnostics,
    required super.scannedAt,
    super.fields,
    super.mrz,
  }) : super(documentKind: DocumentKind.sudanId);

  /// Profession as printed on the front.
  String? get profession => fields['profession'] as String?;

  /// Address as printed on the front.
  String? get address => fields['address'] as String?;

  /// Blood type as printed on the front.
  String? get bloodType => fields['bloodType'] as String?;

  /// Phone number as printed on the front.
  String? get phone => fields['phone'] as String?;
}
