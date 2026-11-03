import 'package:idlens/src/api/scan_outcome.dart';
import 'package:idlens/src/api/scan_status.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/mrz_data.dart';
import 'package:idlens/src/domain/scan_issue.dart';

/// The rules that turn what a pipeline read into `fieldsToCheck` and a
/// `status`. Every document goes through here, so the rules live in one place.
class ScanReview {
  ScanReview._();

  /// Fields a document is not usable without. When one is not read it is
  /// listed in `fieldsToCheck` and is null. A passport has none: the MRZ
  /// carries its identity.
  static const requiredFields = {
    DocumentKind.sudanId: ['arabicName', 'nationalNumber'],
    DocumentKind.passport: <String>[],
    DocumentKind.civilRegistryCertificate: [
      'nationalNumber',
      'name',
      'dateOfBirth',
    ],
  };

  static const _dateFields = ['dateOfBirth', 'issueDate', 'expiryDate'];

  /// The fields each MRZ check digit covers. The composite digit covers the
  /// others together, so it alone failing marks all of them.
  static const _checkedFields = {
    'documentNumber': ['documentNumber'],
    'dateOfBirth': ['dateOfBirth'],
    'expiryDate': ['expiryDate'],
    'personalNumber': ['nationalNumber'],
    'composite': ['documentNumber', 'dateOfBirth', 'expiryDate'],
  };

  /// What the user should look at, in the order of [fields]:
  /// - a required field that was not read (its value is null),
  /// - a field the pipeline doubted ([doubtful]: differs from the MRZ, or a
  ///   date that cannot be right),
  /// - a field covered by a failed MRZ check digit,
  /// - a date that is not a real calendar date.
  static List<String> fieldsToCheck({
    required DocumentKind kind,
    required Map<String, dynamic> fields,
    Iterable<String> doubtful = const [],
    MrzData? mrz,
  }) {
    final marked = <String>{
      for (final key in requiredFields[kind]!)
        if (_isEmpty(fields[key])) key,
      ...doubtful,
      if (mrz != null)
        for (final check in mrz.checks.entries)
          if (!check.value) ...?_checkedFields[check.key],
      for (final key in _dateFields)
        if (!_isEmpty(fields[key]) && parseScanDate(fields[key]) == null) key,
    };
    final order = fields.keys.toList();
    int rank(String key) {
      final i = order.indexOf(key);
      return i < 0 ? order.length : i;
    }

    return marked.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  /// False when nothing that identifies the document was read: no MRZ on an
  /// ID card or passport, or none of a certificate's required fields.
  static bool isReadable({
    required DocumentKind kind,
    required Map<String, dynamic> fields,
    MrzData? mrz,
  }) => kind.hasMrz
      ? mrz != null
      : requiredFields[kind]!.any((key) => !_isEmpty(fields[key]));

  /// The more serious of two photos' issues (an ID card has two). On a tie the
  /// first one, the front, is kept.
  static ScanIssue? worse(ScanIssue? first, ScanIssue? second) {
    if (first == null) return second;
    if (second == null) return first;
    return _severity[second]! < _severity[first]! ? second : first;
  }

  static const _severity = {
    ScanIssue.wrongDocument: 0,
    ScanIssue.readerUnavailable: 1,
    ScanIssue.processingFailed: 2,
    ScanIssue.documentNotInFrame: 3,
    ScanIssue.imageNotClear: 4,
  };

  /// The issue to report: an unreadable document always has one, so the app
  /// can say why it failed.
  static ScanIssue? issueFor(ScanIssue? issue, {required bool readable}) =>
      issue ?? (readable ? null : ScanIssue.imageNotClear);

  /// - `failed`: the document is unreadable, wrong, out of the frame, the
  ///   reader couldn't start, or reading crashed.
  /// - `needsReview`: the photo is not clear, or a field needs checking.
  /// - `verified`: neither.
  static ScanStatus statusFor({
    required ScanIssue? issue,
    required bool readable,
    required List<String> fieldsToCheck,
  }) {
    if (!readable || (issue != null && issue != ScanIssue.imageNotClear)) {
      return ScanStatus.failed;
    }
    if (issue != null || fieldsToCheck.isNotEmpty) {
      return ScanStatus.needsReview;
    }
    return ScanStatus.verified;
  }

  static bool _isEmpty(Object? value) =>
      value == null || (value is String && value.trim().isEmpty);
}
