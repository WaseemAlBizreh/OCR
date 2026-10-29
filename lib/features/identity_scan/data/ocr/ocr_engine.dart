import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:injectable/injectable.dart';

/// On-device ML Kit (Latin) OCR: Latin text, digits and MRZ lines.
@lazySingleton
class OcrEngine {
  TextRecognizer? _latin;

  Future<String?> recognizeLatin(String imagePath) async {
    try {
      _latin ??= TextRecognizer(script: TextRecognitionScript.latin);
      final result =
          await _latin!.processImage(InputImage.fromFilePath(imagePath));
      final text = result.text.trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await _latin?.close();
    _latin = null;
  }
}
