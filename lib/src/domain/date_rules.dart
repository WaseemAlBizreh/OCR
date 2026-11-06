/// Dates on an ID card or passport that cannot be right together.
class DateRules {
  DateRules._();

  static final _iso = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Marks in [doubtful], and explains in [warnings], dates that contradict
  /// each other. Each value is kept as read; the user is told to look at it.
  ///
  /// - a birth date in the future;
  /// - a birth date on or after the issue date or the expiry date;
  /// - an issue date on or after the expiry date.
  ///
  /// Only real `yyyy-MM-dd` dates are compared (they sort as text); a value
  /// that could not be read as a date is left to `fieldsToCheck`. An expired
  /// document is not an error here: the app decides what to do with it.
  static void check({
    String? birthDate,
    String? issueDate,
    String? expiryDate,
    required List<String> warnings,
    required Set<String> doubtful,
    DateTime? now,
  }) {
    String? iso(String? v) => v != null && _iso.hasMatch(v) ? v : null;
    final birth = iso(birthDate);
    final issue = iso(issueDate);
    final expiry = iso(expiryDate);

    final today = (now ?? DateTime.now()).toIso8601String().substring(0, 10);
    if (birth != null && birth.compareTo(today) > 0) {
      doubtful.add('dateOfBirth');
      warnings.add('Date of birth ($birth) is in the future.');
    }
    if (birth != null && issue != null && birth.compareTo(issue) >= 0) {
      doubtful.addAll(['dateOfBirth', 'issueDate']);
      warnings.add(
        'Date of birth ($birth) is not before the issue date ($issue).',
      );
    }
    if (birth != null && expiry != null && birth.compareTo(expiry) >= 0) {
      doubtful.addAll(['dateOfBirth', 'expiryDate']);
      warnings.add(
        'Date of birth ($birth) is not before the expiry date ($expiry).',
      );
    }
    if (issue != null && expiry != null && issue.compareTo(expiry) >= 0) {
      doubtful.add('issueDate');
      warnings.add(
        'Issue date ($issue) is not before the expiry date ($expiry).',
      );
    }
  }
}
