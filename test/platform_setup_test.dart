import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/platform_setup.dart';

void main() {
  const key = 'NSCameraUsageDescription';

  test('finds the key in an XML plist', () {
    const xml =
        '<dict>\n\t<key>NSCameraUsageDescription</key>\n'
        '\t<string>x</string>\n</dict>';
    expect(PlatformSetup.plistMentions(utf8.encode(xml), key), isTrue);
  });

  test('finds the key in the middle of binary data', () {
    final bytes = [0, 1, 2, 255, ...ascii.encode(key), 0, 9, 9];
    expect(PlatformSetup.plistMentions(bytes, key), isTrue);
  });

  test('does not match a different key or a truncated one', () {
    expect(
      PlatformSetup.plistMentions(
        utf8.encode('<key>NSMicrophoneUsageDescription</key>'),
        key,
      ),
      isFalse,
    );
    expect(
      PlatformSetup.plistMentions(utf8.encode('NSCameraUsageDescriptio'), key),
      isFalse,
    );
    expect(PlatformSetup.plistMentions(const [], key), isFalse);
  });
}
