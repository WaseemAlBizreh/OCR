# AI Features in the App: Approach and Guide

How we run AI models inside this Flutter app, what options exist, and how to add a new model. Written from a design discussion; package versions and platform support should be re-checked before adopting anything.

## 1. How it works today (OCR)

- Model files (`.onnx`) are bundled as assets in `assets/models/paddle/` (declared in `pubspec.yaml`).
- `flutter_onnxruntime` loads a model and runs inference on it. It is a **generic** runtime with nothing OCR-specific in it.
- Code around the runtime lives in `lib/features/identity_scan/data/ocr/paddle/`:
  - `db_postprocess.dart` turns the detection model's heatmap into text boxes.
  - `ctc_decoder.dart` turns the recognition model's output into characters.
  - `rtl_reorder.dart` and `paddle_sudan_card_parser.dart` handle Arabic ordering and the card layout.
  - `paddle_ocr_engine.dart` ties it together behind the `OcrEngine` / `ScanEngine` interfaces.

## 2. Can we run any model with ONNX Runtime?

Yes, in principle: image classification, object detection, segmentation, face or document detection, embeddings, small NLP models, speech and so on.

**The catch:** the runtime only turns tensors into tensors. For every new model we still write:

1. **Preprocessing**: resize, normalize, channel order (NCHW or NHWC), tokenization for NLP.
2. **Postprocessing**: decode output tensors into something useful (boxes, labels, text, scores).

Other limits:

- The model must be exportable to ONNX (some ops or opsets are unsupported).
- Model size and speed: big transformers and LLMs are often too heavy for phones. Small and medium models are fine.
- NLP needs a tokenizer (WordPiece, BPE, ...) ported to Dart, plus its vocab file.
- GPU/NPU acceleration (NNAPI, CoreML) depends on the platform and on what the plugin exposes. CPU always works.
- Models need not be bundled. They can be downloaded at runtime to keep the app small.

## 3. On-device options in Flutter

| Option | What it is | Good for | Trade-offs |
|---|---|---|---|
| **ONNX Runtime** (`flutter_onnxruntime`, `onnxruntime`) | Cross-platform runtime for `.onnx` models | Models from PyTorch or PaddlePaddle, like our OCR | We write pre/post-processing. Acceleration depends on the plugin. |
| **TensorFlow Lite / LiteRT** (`tflite_flutter`) | Google's mobile runtime | Android-first work, vision and audio, quantized models | Needs `.tflite` conversion. Plugin maintenance has been uneven. |
| **Google ML Kit** (`google_mlkit_*`, already used for text recognition) | Ready-made models behind a simple API | Latin OCR, barcodes, face and object detection, translation, language ID | No custom models, no Arabic OCR, no control over behavior. Least work when it fits. |
| **Core ML / platform channels** | Native iOS or Android ML APIs called from Dart | Apple Neural Engine, Apple Vision, Android on-device Gemini Nano | Separate native code per platform. |
| **MediaPipe** (plugins or native) | Google task library for vision, text, audio, on-device LLM | Pose, hand and face tracking, small LLMs | Flutter support is mostly native channels or community plugins. |
| **LLM runtimes** (`llama.cpp` via FFI, `flutter_gemma`, MLC) | Quantized small language models run locally | Offline chat, summarization, extraction | Models of 0.5-4 GB, battery drain, recent phones only. |
| **Dart FFI to C/C++** | Call a native inference library directly | Maximum control and speed, engines with no plugin | Highest effort: we own the build for every platform. |

## 4. Best practices

1. **Start with the least custom option.** ML Kit if it fits, then a ready model on ONNX or TFLite, then training or converting our own. We use Paddle because ML Kit can't read Arabic.
2. **Hide inference behind an interface.** `OcrEngine` / `ScanEngine` is the pattern. Swapping engines should touch one class.
3. **Run inference off the UI thread** (`Isolate.run` / `compute`). Preprocessing and decoding are heavy and will drop frames.
4. **Keep models small.** Use quantized models (INT8 / FP16), prefer mobile variants (for example PaddleOCR "mobile", not "server"), and download large models after install.
5. **Reuse sessions.** Load once, keep alive, release when the feature closes. Loading per scan is slow.
6. **Test on real, low-end devices.** Emulators and flagship phones hide latency and memory problems.
7. **Add a fallback.** If confidence is low or the device is weak, fall back to a server model.
8. **Test pre/post-processing.** Most bugs live there, not in the model. See `test/paddle_decoding_test.dart`.

## 5. On-device vs server

- **On-device** when privacy matters (ID images never leave the phone), offline use is needed, latency should be instant, or per-request cost should be zero.
- **Server** for large models (big LLMs, heavy vision), model updates without an app release, or when device accuracy isn't enough.
- **Hybrid** is common: on-device for the fast path, server for hard cases.

For identity scanning, on-device ONNX is a good fit because of privacy and offline use. For future features such as LLM-based field extraction or summarization, prefer the server unless offline use is required.

## 6. Checklist: adding a new model to the app

1. Pick the task and check whether ML Kit already covers it. If so, use it.
2. Find a **mobile-sized** model and export or convert it (ONNX or TFLite). Note the exact input shape, dtype, normalization and channel order.
3. Add the file under `assets/models/<name>/` and declare the folder in `pubspec.yaml`. Consider runtime download if it is large.
4. Define a small domain interface (like `OcrEngine`) so the rest of the app doesn't depend on the runtime.
5. Implement preprocessing, the session call and postprocessing in a new data-layer class. Keep each step in its own file or function so it can be unit tested.
6. Run it in an isolate. Load the session once and dispose it properly.
7. Write unit tests for pre/post-processing with fixed tensors, as in `paddle_decoding_test.dart`.
8. Measure latency, memory and size on a low-end real device.
9. Decide on a fallback (server or simpler path) for failures and low confidence.

## 7. Open ideas

- Compare ONNX vs TFLite for the Paddle models (size, speed, acceleration).
- Check whether ML Kit can replace any part of the pipeline (for example Latin-script fields).
- Consider a hybrid fallback to a server OCR for low-confidence scans.
