import 'package:mrz/features/identity_scan/domain/mrz_data.dart';

enum MrzIssueSeverity {
  /// The MRZ cannot be trusted; the scan should be retaken.
  error,

  /// The MRZ is readable but something about the document deserves a look.
  warning,
}

class MrzIssue {
  const MrzIssue(this.severity, this.code, this.message);

  final MrzIssueSeverity severity;
  final String code;
  final String message;

  Map<String, dynamic> toJson() => {
        'severity': severity.name,
        'code': code,
        'message': message,
      };
}

class MrzValidation {
  const MrzValidation(this.issues);

  final List<MrzIssue> issues;

  List<MrzIssue> get errors =>
      issues.where((i) => i.severity == MrzIssueSeverity.error).toList();

  List<MrzIssue> get warnings =>
      issues.where((i) => i.severity == MrzIssueSeverity.warning).toList();

  /// True when the MRZ is good enough to trust (warnings are allowed).
  bool get isAcceptable => errors.isEmpty;

  /// One sentence for the user, or null when the MRZ is acceptable.
  String? get userMessage {
    final list = errors;
    if (list.isEmpty) return null;
    if (list.any((i) => i.code == 'notFound')) return list.first.message;
    return list.map((i) => i.message).join('\n');
  }
}

/// Decides whether a scanned MRZ can be trusted, beyond what the parser's
/// check digits already say: the read must be complete (no failed check
/// digit), and its fields must make sense (real dates, a name, a number,
/// three-letter country codes).
class MrzValidator {
  const MrzValidator({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  static final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _country = RegExp(r'^[A-Z]{3}$');

  static const _checkLabels = {
    'documentNumber': 'document number',
    'dateOfBirth': 'date of birth',
    'expiryDate': 'expiry date',
    'personalNumber': 'personal number',
    'composite': 'overall check',
  };

  MrzValidation validate(MrzData? mrz) {
    if (mrz == null) {
      return const MrzValidation([
        MrzIssue(
          MrzIssueSeverity.error,
          'notFound',
          'No MRZ found. Make sure the machine-readable lines at the '
              'bottom of the document are inside the frame, then retake.',
        ),
      ]);
    }

    final issues = <MrzIssue>[];
    void error(String code, String message) =>
        issues.add(MrzIssue(MrzIssueSeverity.error, code, message));

    final failed = [
      for (final entry in mrz.checks.entries)
        if (!entry.value) _checkLabels[entry.key] ?? entry.key,
    ];
    if (failed.isNotEmpty) {
      error(
        'checkDigits',
        'The MRZ was read incorrectly (${failed.join(', ')} did not verify). '
            'Retake the photo with less glare and the MRZ fully visible.',
      );
    }

    final today = _clock();
    final now = DateTime(today.year, today.month, today.day);
    final dob = _parse(mrz.dateOfBirth);
    final expiry = _parse(mrz.expiryDate);

    if (dob == null) {
      error('dateOfBirth', 'The date of birth in the MRZ is not a valid date.');
    } else if (dob.isAfter(now)) {
      error('dateOfBirth', 'The date of birth in the MRZ is in the future.');
    }
    if (expiry == null) {
      error('expiryDate', 'The expiry date in the MRZ is not a valid date.');
    } else if (dob != null && !expiry.isAfter(dob)) {
      error('expiryDate', 'The expiry date in the MRZ is before the date of birth.');
    } else if (expiry.isBefore(now)) {
      issues.add(const MrzIssue(
        MrzIssueSeverity.warning,
        'expired',
        'This document has expired.',
      ));
    }

    if (mrz.documentNumber.isEmpty) {
      error('documentNumber', 'The document number in the MRZ is empty.');
    }
    if (mrz.surname.isEmpty) {
      error('name', 'The name in the MRZ is empty.');
    }
    if (!_country.hasMatch(mrz.issuingCountry) || !_country.hasMatch(mrz.nationality)) {
      error('country', 'The country code in the MRZ is not valid.');
    }
    if (mrz.sex.isEmpty) {
      issues.add(const MrzIssue(
        MrzIssueSeverity.warning,
        'sex',
        'The sex field in the MRZ could not be read.',
      ));
    }
    return MrzValidation(issues);
  }

  static DateTime? _parse(String iso) {
    if (!_isoDate.hasMatch(iso)) return null;
    final parsed = DateTime.tryParse(iso);
    // DateTime rolls 31 Feb over to March; reject such dates.
    return parsed != null && parsed.toIso8601String().startsWith(iso) ? parsed : null;
  }
}
