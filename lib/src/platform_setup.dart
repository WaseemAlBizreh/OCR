import 'dart:io';

/// Checks the app-level setup a package cannot do for the host app.
class PlatformSetup {
  PlatformSetup._();

  static const _cameraKey = 'NSCameraUsageDescription';

  /// True when the app's iOS `Info.plist` can be read and has no
  /// `NSCameraUsageDescription`. iOS ends the app the moment the camera opens
  /// without it, so this is checked first to give a readable error instead.
  ///
  /// False on other platforms, and when the file cannot be read: an unknown
  /// answer never blocks a scan.
  static Future<bool> iosCameraUsageMissing() async {
    if (!Platform.isIOS) return false;
    try {
      // Info.plist sits next to the executable inside the .app bundle.
      final dir = File(Platform.resolvedExecutable).parent.path;
      final bytes = await File('$dir/Info.plist').readAsBytes();
      return !plistMentions(bytes, _cameraKey);
    } on FileSystemException {
      return false;
    }
  }

  /// Whether [key] appears in a plist, in XML or binary form. Keys are stored
  /// as plain ASCII in both, so a byte search is enough and no plist parser is
  /// needed.
  static bool plistMentions(List<int> bytes, String key) {
    final needle = key.codeUnits;
    for (var i = 0; i <= bytes.length - needle.length; i++) {
      var j = 0;
      while (j < needle.length && bytes[i + j] == needle[j]) {
        j++;
      }
      if (j == needle.length) return true;
    }
    return false;
  }
}
