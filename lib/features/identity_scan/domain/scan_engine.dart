/// Which OCR engine reads the printed card text. The MRZ is read the same way
/// for both.
enum ScanEngine {
  /// Tesseract `ara+eng` plus ML Kit (the original scanner).
  classic,

  /// PaddleOCR PP-OCRv5 Arabic on ONNX Runtime.
  paddle;

  String get label => switch (this) {
        ScanEngine.classic => 'classic',
        ScanEngine.paddle => 'paddle+mlkit-latin',
      };
}
