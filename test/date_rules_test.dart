import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/domain/date_rules.dart';

void main() {
  final now = DateTime(2026, 11, 6);

  ({List<String> warnings, Set<String> doubtful}) run({
    String? birth,
    String? issue,
    String? expiry,
  }) {
    final warnings = <String>[];
    final doubtful = <String>{};
    DateRules.check(
      birthDate: birth,
      issueDate: issue,
      expiryDate: expiry,
      warnings: warnings,
      doubtful: doubtful,
      now: now,
    );
    return (warnings: warnings, doubtful: doubtful);
  }

  test('consistent dates raise nothing', () {
    final r = run(
      birth: '1992-09-23',
      issue: '2022-05-16',
      expiry: '2027-05-16',
    );
    expect(r.doubtful, isEmpty);
    expect(r.warnings, isEmpty);
  });

  test('an expired document is not an error', () {
    expect(
      run(
        birth: '1970-01-01',
        issue: '2000-01-01',
        expiry: '2010-01-01',
      ).doubtful,
      isEmpty,
    );
  });

  test('a birth date in the future is doubtful', () {
    expect(run(birth: '2030-01-01').doubtful, {'dateOfBirth'});
  });

  test('a birth date after the issue date marks both', () {
    expect(run(birth: '2010-01-01', issue: '2005-01-01').doubtful, {
      'dateOfBirth',
      'issueDate',
    });
  });

  test('a birth date after the expiry date marks both', () {
    expect(run(birth: '2010-01-01', expiry: '2005-01-01').doubtful, {
      'dateOfBirth',
      'expiryDate',
    });
  });

  test('an issue date on or after the expiry date marks the issue date', () {
    expect(run(issue: '2027-05-16', expiry: '2027-05-16').doubtful, {
      'issueDate',
    });
    expect(run(issue: '2030-01-01', expiry: '2027-05-16').doubtful, {
      'issueDate',
    });
  });

  test('values that are not real dates are never compared', () {
    expect(
      run(birth: '920923', issue: 'garbage', expiry: '2010-01-01').doubtful,
      isEmpty,
    );
  });
}
