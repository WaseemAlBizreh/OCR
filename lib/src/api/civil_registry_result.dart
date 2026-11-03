import 'package:idlens/src/api/scan_outcome.dart';
import 'package:idlens/src/domain/document_kind.dart';

/// The result of scanning a civil registry certificate (A4). The certificate
/// has no MRZ, so [ScanOutcome.mrz] is always null and there are no check
/// digits: `verified` here means only that nothing was found wrong with the
/// photo and the national number, name and date of birth were read. It does
/// not prove the values are correct; see [confidence].
class CivilRegistryResult extends ScanOutcome {
  /// Creates a result. Built by idlens; apps read it.
  const CivilRegistryResult({
    required super.status,
    super.issue,
    super.fieldsToCheck,
    super.images,
    super.diagnostics,
    required super.scannedAt,
    this.fields = const {},
    this.confidence = const {},
  }) : super(documentKind: DocumentKind.civilRegistryCertificate);

  @override
  final Map<String, dynamic> fields;

  /// OCR confidence (0..1) of the line each field was read from, keyed like
  /// [fields].
  final Map<String, double> confidence;

  /// The registry office that issued the certificate.
  String? get registryOffice => fields['registryOffice'] as String?;

  /// Date the certificate was issued.
  DateTime? get issueDate => parseScanDate(fields['issueDate']);

  /// The national number.
  String? get nationalNumber => fields['nationalNumber'] as String?;

  /// The person's name.
  String? get name => fields['name'] as String?;

  /// Place of birth.
  String? get placeOfBirth => fields['placeOfBirth'] as String?;

  /// Date of birth.
  DateTime? get dateOfBirth => parseScanDate(fields['dateOfBirth']);

  /// Marital status as printed.
  String? get maritalStatus => fields['maritalStatus'] as String?;

  /// Gender as printed.
  String? get gender => fields['gender'] as String?;

  /// Type of nationality as printed.
  String? get nationalityType => fields['nationalityType'] as String?;

  /// Profession as printed.
  String? get profession => fields['profession'] as String?;

  /// Work address as printed.
  String? get workAddress => fields['workAddress'] as String?;

  /// The mother's name.
  String? get motherName => fields['motherName'] as String?;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'confidence': confidence,
  };
}
