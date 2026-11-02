## 0.1.3

- Allow `google_mlkit_text_recognition` 0.15.1 again, so idlens can be installed
  alongside packages that need `google_mlkit_commons` 0.11, such as
  `google_mlkit_face_detection` 0.13.
- No code changes.

## 0.1.2

- Updated dependencies: `camera` to `^0.12.0+2` and
  `google_mlkit_text_recognition` to `^0.16.0`.
- Example app: added the Android and iOS launcher icons.
- No API changes.

## 0.1.1

- Rewrote the README for pub.dev: install with `flutter pub add idlens`, every
  API with its signature and a usage example, and clearer platform setup.
- Smaller published package: build output is no longer included.
- No code changes.

## 0.1.0

First release.

- `IdLens.scanIdCard`, `scanPassport` and `scanCivilRegistry`: built-in capture
  flow that returns a typed result.
- `IdLens.processIdCard`, `processPassport` and `processCivilRegistry`: read
  image files without any UI.
- Results (`IdCardResult`, `PassportResult`, `CivilRegistryResult`) extend
  `ScanOutcome` and always carry the captured images, with a `status` and typed
  `issues` instead of exceptions for read problems.
- MRZ detection with ICAO 9303 check-digit validation and character repair.
- Sudan ID card (front and back), passport data page (any country) and civil
  registry certificate (A4).
- On-device only: PaddleOCR (ONNX Runtime) and ML Kit; nothing is uploaded.
