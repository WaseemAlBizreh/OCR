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
