import 'package:flutter_test/flutter_test.dart';
import 'package:mrz/features/identity_scan/data/mrz/mrz_parser.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_line.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_ocr_lines.dart';
import 'package:mrz/features/identity_scan/domain/mrz_data.dart';

PassportLine frag(String text, double left, double top) =>
    PassportLine(text, left, top, left + 100, top + 20);

void main() {
  group('dropJoinedRows', () {
    test('removes items that reuse an earlier item\'s box object', () {
      final boxA = Object();
      final boxB = Object();
      final items = [
        ('right', boxA),
        ('left', boxB),
        ('right left', boxA), // joined copy of the row, reuses the first box
      ];
      final kept = PassportOcrLines.dropJoinedRows(items, (i) => i.$2);
      expect(kept.map((i) => i.$1), ['right', 'left']);
    });
  });

  group('mrzText', () {
    test('puts fragments back left to right, one string per row', () {
      final text = PassportOcrLines.mrzText([
        frag('<<ANNA<MARIA<<<<', 400, 100), // detector gave the right part first
        frag('P<UTOERIKSSON', 0, 100),
        frag('7408122F1204159ZE184226B<<<<<10', 200, 140),
        frag('L898902C36UTO', 0, 140),
      ]);
      expect(text, 'P<UTOERIKSSON<<ANNA<MARIA<<<<\nL898902C36UTO7408122F1204159ZE184226B<<<<<10');
    });

    test('ICAO specimen split into fragments still parses with valid checks', () {
      final text = PassportOcrLines.mrzText([
        frag('P<UTOERIKSSON<<ANNA<MARIA', 0, 100),
        frag('<<<<<<<<<<<<<<<<<<<', 260, 100),
        frag('L898902C36UTO7408122F12', 0, 140),
        frag('04159ZE184226B<<<<<10', 260, 140),
      ]);
      final mrz = MrzParser(clock: () => DateTime(2026, 10, 28))
          .parseText(text, formats: [MrzFormat.td3]);
      expect(mrz, isNotNull);
      expect(mrz!.isValid, isTrue);
      expect(mrz.surname, 'ERIKSSON');
    });
  });

  group('mergeLatin', () {
    test('adds Latin-only lines that are new, skips duplicates and Arabic', () {
      final paddle = [
        const PassportLine('الاسم', 300, 0, 400, 20),
        const PassportLine('23/09/1992', 0, 40, 100, 60),
      ];
      final mlkit = [
        const PassportLine('23/09/1992', 1, 41, 101, 61), // same place and text
        const PassportLine('P05000040', 0, 80, 100, 100), // new
        const PassportLine('الخرطوم', 0, 120, 100, 140), // Arabic
      ];
      final merged = PassportOcrLines.mergeLatin(paddle, mlkit);
      expect(merged.map((l) => l.text), ['الاسم', '23/09/1992', 'P05000040']);
    });
  });
}
