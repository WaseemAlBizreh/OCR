class MrzScanResult {
  const MrzScanResult({
    this.frontPayload,
    this.backPayload,
    this.frontSavedPath,
    this.backSavedPath,
  });

  final Map<String, dynamic>? frontPayload;
  final Map<String, dynamic>? backPayload;
  final String? frontSavedPath;
  final String? backSavedPath;

  Map<String, dynamic> toDisplayJson() {
    return {
      'frontPayload': frontPayload,
      'backPayload': backPayload,
      'frontSavedPath': frontSavedPath,
      'backSavedPath': backSavedPath,
      'scannedAt': DateTime.now().toIso8601String(),
    };
  }
}
