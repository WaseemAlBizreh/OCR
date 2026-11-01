import 'package:flutter_test/flutter_test.dart';
import 'package:mrz/features/identity_scan/data/mrz/mrz_parser.dart';
import 'package:mrz/features/identity_scan/domain/mrz_validator.dart';

void main() {
  final clock = DateTime(2026, 10, 28);
  final parser = MrzParser(clock: () => clock);
  final validator = MrzValidator(clock: () => clock);

  const td3 = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\n'
      'L898902C36UTO7408122F1204159ZE184226B<<<<<10\n';

  test('no MRZ is an error telling the user to retake', () {
    final v = validator.validate(null);
    expect(v.isAcceptable, isFalse);
    expect(v.userMessage, contains('No MRZ found'));
  });

  test('a clean read is acceptable', () {
    // The ICAO specimen expired in 2012, which is only a warning.
    final v = validator.validate(parser.parseText(td3));
    expect(v.isAcceptable, isTrue);
    expect(v.warnings.map((w) => w.code), ['expired']);
    expect(v.userMessage, isNull);
  });

  test('a failed check digit is rejected', () {
    final broken = td3.replaceFirst('L898902C36', 'L898902C37');
    final v = validator.validate(parser.parseText(broken));
    expect(v.isAcceptable, isFalse);
    expect(v.errors.map((e) => e.code), contains('checkDigits'));
  });

  test('a date of birth in the future is rejected', () {
    final future = MrzValidator(clock: () => DateTime(1970, 1, 1));
    final v = future.validate(parser.parseText(td3));
    expect(v.errors.map((e) => e.code), contains('dateOfBirth'));
  });
}
