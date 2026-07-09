import 'package:mrz/features/arabic_document_scan/data/parsers/country_parser.dart';
import 'package:mrz/features/arabic_document_scan/data/parsers/sudan_id_front_parser.dart';
import 'package:mrz/features/arabic_document_scan/data/parsers/uae_id_parser.dart';
import 'package:mrz/features/arabic_document_scan/domain/id_card_side.dart';

class CountryParserFactory {
  CountryParserFactory._();

  static CountryParser? forCountry({
    required String countryCode,
    required IdCardSide side,
  }) {
    if (side == IdCardSide.back) {
      return null;
    }

    return switch (countryCode) {
      'sd' => SudanIdFrontParser(),
      'ae' => UaeIdParser(),
      _ => null,
    };
  }
}
