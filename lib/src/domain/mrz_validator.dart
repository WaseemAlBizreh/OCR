import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/mrz_data.dart';
import 'package:idlens/src/domain/scan_issue.dart';

/// Decides only whether the image holds the MRZ of the expected document: one
/// must exist, and its format must match. Missing or wrong fields inside it
/// (dates, expiry, check digits) are deliberately not judged here.
///
/// Returns a [ScanIssue] code, or null when the MRZ is acceptable.
class MrzValidator {
  const MrzValidator();

  ScanIssue? validate(MrzData? mrz, DocumentKind expected) {
    if (mrz == null) return ScanIssue.mrzNotFound;
    final expectedFormat = switch (expected) {
      DocumentKind.sudanId => MrzFormat.td1,
      DocumentKind.passport => MrzFormat.td3,
      DocumentKind.civilRegistryCertificate => null,
    };
    if (expectedFormat == null || mrz.format == expectedFormat) return null;
    return ScanIssue.wrongDocument;
  }
}
