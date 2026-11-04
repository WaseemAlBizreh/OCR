/// On-device scanner for identity documents: Sudan ID cards, passports from any
/// country and civil registry certificates.
///
/// Start with [IdLens].
library;

export 'src/api/civil_registry_result.dart';
export 'src/api/document_guide.dart';
export 'src/api/document_photo.dart';
export 'src/api/id_card_result.dart';
export 'src/api/passport_result.dart';
export 'src/api/scan_exception.dart';
export 'src/api/scan_options.dart';
export 'src/api/scan_outcome.dart' show ScanOutcome;
export 'src/api/scan_status.dart';
export 'src/api/scanned_image.dart';
export 'src/domain/document_kind.dart' show DocumentKind, DocumentSide;
export 'src/domain/mrz_data.dart' show MrzData, MrzFormat;
export 'src/domain/scan_issue.dart' show ScanIssue;
export 'src/idlens_scanner.dart';
