import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/mrz_data.dart';

/// Decides only whether a found MRZ belongs to the expected document: its
/// format must match. Missing or wrong values inside it (dates, expiry, check
/// digits) are deliberately not judged here.
class MrzValidator {
  const MrzValidator();

  /// True when [mrz] was found but is of another document type than
  /// [expected]. A missing MRZ is not a wrong document.
  bool isWrongDocument(MrzData? mrz, DocumentKind expected) {
    if (mrz == null) return false;
    final expectedFormat = switch (expected) {
      DocumentKind.sudanId => MrzFormat.td1,
      DocumentKind.passport => MrzFormat.td3,
      DocumentKind.civilRegistryCertificate => null,
    };
    return expectedFormat != null && mrz.format != expectedFormat;
  }
}
