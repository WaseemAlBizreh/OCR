# Arabic OCR vs English OCR — Packages

This document explains which packages handle **Arabic** text recognition vs **English / Latin** text recognition in the app. No implementation code — packages and roles only.

---

## Summary

| Script | Primary package | Secondary / supplement |
|--------|-----------------|------------------------|
| **Arabic** | `flutter_tesseract_ocr` | — (no dedicated Arabic engine besides Tesseract) |
| **English / Latin** | `google_mlkit_text_recognition` | `flutter_tesseract_ocr` (via `eng` in `ara+eng`) |
| **MRZ (Latin machine-readable zone)** | `mrz_scanner_plus` | `google_mlkit_text_recognition` (when OCR text is merged with MRZ flows) |

Both Arabic and English OCR run **on-device**. Nothing is sent to a cloud API for text recognition.

---

## Arabic OCR

### Package: `flutter_tesseract_ocr` (^0.4.31)

The **only engine used for Arabic script** in this app.

| Detail | Value |
|--------|-------|
| **Role** | Primary Arabic text recognition |
| **Languages loaded** | `ara` (Arabic) + `eng` (English) — combined as `ara+eng` |
| **Bundled models** | `assets/tessdata/ara.traineddata`, `assets/tessdata/eng.traineddata` |
| **Config file** | `assets/tessdata_config.json` — lists which traineddata files to ship |
| **Used by** | `ArabicOcrEngine` (all photo-based document scans) |

### What Arabic OCR is used for

- Arabic names, labels, and field text on national ID cards (Sudan, UAE, etc.)
- Arabic text on Sudan passports (names, places, dates in Arabic)
- Any Arabic script on Saudi National ID cards (before field parsing)

### What is **not** used for Arabic OCR

| Package | Why not |
|---------|---------|
| `google_mlkit_text_recognition` | Configured with **Latin script only** in this app — does not read Arabic |
| `flutter_ocr_identity_extractor` | Used for **Saudi ID field parsing** after OCR text exists; its built-in OCR path (`OcrService`) is **not used** because it crashes on repeated scans |

---

## English OCR

English and Latin characters are recognized through **two packages**, depending on context.

### Package 1: `google_mlkit_text_recognition` (^0.15.1)

| Detail | Value |
|--------|-------|
| **Role** | Primary supplement for **Latin / English** text |
| **Script mode** | Latin (`TextRecognitionScript.latin`) |
| **Used by** | `ArabicOcrEngine` (runs in parallel with Tesseract on every photo scan) |
| **Related override** | `google_mlkit_commons` (^0.11.0) — shared ML Kit foundation |

### What ML Kit English OCR is used for

- English names on ID cards and passports
- Numbers, dates, and alphanumeric codes in Latin characters
- MRZ-like Latin text that Tesseract may miss
- Faster Latin recognition compared to Tesseract alone

### Package 2: `flutter_tesseract_ocr` (^0.4.31)

| Detail | Value |
|--------|-------|
| **Role** | Secondary English source via the `eng` model bundled alongside `ara` |
| **Languages loaded** | `ara+eng` (same run as Arabic OCR) |

Tesseract’s English output is merged with ML Kit’s Latin output when both return text. Tesseract is treated as the **primary** source; ML Kit **adds unique lines** not already found by Tesseract.

### Package 3: `mrz_scanner_plus` (git dependency)

| Detail | Value |
|--------|-------|
| **Role** | English/Latin **MRZ** (machine-readable zone) detection and parsing |
| **Script** | MRZ uses Latin letters, digits, and `<` fillers — effectively English OCR for the bottom band of passports and ID backs |

### What MRZ scanner is used for

| Flow | MRZ package API |
|------|-----------------|
| Live camera MRZ scan | `CameraScanPage` |
| Passport from still image (non-Sudan) | `MrzScanResultBuilder.buildPassportPayloadFromImage` |
| Sudan passport from still image | Same builder, combined with Tesseract + ML Kit OCR text |
| Sudan ID card **back** | `MrzScanResultBuilder.buildBackMrzPayloadFromImage` |

MRZ fields (document number, names, dates of birth/expiry, nationality, sex) are all Latin characters.

---

## How the two engines work together (photo scans)

For every **photo / gallery** document scan that goes through `ArabicOcrEngine`:

```
Image
  ├── flutter_tesseract_ocr  →  Arabic + English (ara+eng)     [PRIMARY]
  └── google_mlkit_text_recognition  →  Latin / English only  [SUPPLEMENT]
           ↓
      Merged text → country parsers / Saudi ID extractor
```

| Engine | Arabic script | English / Latin |
|--------|---------------|-----------------|
| Tesseract (`ara+eng`) | Yes — primary | Yes — included in same run |
| ML Kit (Latin) | No | Yes — supplement |
| **Merged result** | From Tesseract | From both (unique lines combined) |

---

## Package usage by document type

| Document | Arabic OCR packages | English OCR packages |
|----------|--------------------|--------------------|
| **Saudi National ID** | `flutter_tesseract_ocr` | `google_mlkit_text_recognition`, `flutter_tesseract_ocr` (eng) |
| **Arabic country ID (front)** | `flutter_tesseract_ocr` | `google_mlkit_text_recognition`, `flutter_tesseract_ocr` (eng) |
| **Sudan ID (back)** | `flutter_tesseract_ocr` | `google_mlkit_text_recognition`, `flutter_tesseract_ocr` (eng), `mrz_scanner_plus` (MRZ band) |
| **Sudan passport** | `flutter_tesseract_ocr` | `google_mlkit_text_recognition`, `flutter_tesseract_ocr` (eng), `mrz_scanner_plus` (MRZ band) |
| **Other passport (photo)** | — | `mrz_scanner_plus` only (no Tesseract / ML Kit for generic passport path) |
| **Live MRZ camera scan** | — | `mrz_scanner_plus` only |

---

## Post-OCR parsing (not OCR engines)

These packages **read OCR text** but do **not** perform image-to-text recognition in the current flow:

| Package | Role |
|---------|------|
| `flutter_ocr_identity_extractor` | Parses Saudi ID fields from existing OCR text (`SaudiIdParser`, `AiIdExtractor`) |

---

## Asset dependencies (Arabic OCR only)

| Asset | Package that needs it |
|-------|----------------------|
| `assets/tessdata/ara.traineddata` | `flutter_tesseract_ocr` |
| `assets/tessdata/eng.traineddata` | `flutter_tesseract_ocr` |
| `assets/tessdata_config.json` | `flutter_tesseract_ocr` |

ML Kit and `mrz_scanner_plus` ship their own on-device models; no extra tessdata assets are required for English OCR.

---

## Quick reference

| Need | Package |
|------|---------|
| Read **Arabic** text from a photo | `flutter_tesseract_ocr` |
| Read **English / Latin** text from a photo | `google_mlkit_text_recognition` (+ Tesseract `eng` as backup) |
| Read **MRZ** (passport / ID back Latin band) | `mrz_scanner_plus` |
| Parse **Saudi ID fields** from OCR text | `flutter_ocr_identity_extractor` (parsing only) |
