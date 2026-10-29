import 'package:flutter_test/flutter_test.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/country_names.dart';

void main() {
  test('resolves ICAO codes to country names', () {
    expect(countryName('SDN'), 'Sudan');
    expect(countryName('ARE'), 'United Arab Emirates');
    expect(countryName('GBR'), 'United Kingdom');
    expect(countryName('D'), 'Germany');
    expect(countryName('UNO'), 'United Nations');
    expect(countryName('sdn'), 'Sudan');
  });

  test('unknown or missing codes give null', () {
    expect(countryName('ZZZ'), isNull);
    expect(countryName(null), isNull);
    expect(countryName(''), isNull);
  });
}
