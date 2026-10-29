# OCR flows: Tesseract (classic) and Paddle

The app has two scanners for the printed text of a Sudan ID, side by side on the home page:

| Home button | Engine | `engine` in the payload |
|---|---|---|
| Sudan ID (front + back) | **Classic**: Tesseract `ara+eng` + ML Kit | `classic` |
| Sudan ID, Paddle OCR (beta) | **Paddle**: PaddleOCR on ONNX Runtime + ML Kit Latin | `paddle+mlkit-latin` |
| Passport | Classic (Paddle is not wired for passports) | `classic` |

Both share the capture screen, the MRZ stage, the merge step and the payload. They differ only
in how the **printed card text** is read and parsed.

Every diagram below is a sequence diagram: each box at the top is an object (a class or a
library), each arrow is a call or a result, and each note says **why** that step exists.

Status: both work. Paddle is a prototype tuned on one Sudan ID and one Android phone; neither
engine has been measured on a set of real cards.

---

## 1. Who is who (the objects)

| Object | What it is | Why it exists |
|---|---|---|
| `IdentityFlowPage` | the screen that runs a scan | collects the photos, picks the engine, shows the JSON |
| `CardCameraPage` | camera screen | takes the photo and crops it to the card frame |
| `ImageOps` | crop helper (uses **OpenCV**) | crops and upscales images before OCR |
| `IdentityScanService` | the orchestrator | runs MRZ, card text and merge in order |
| `MrzReader` / `MrzParser` | MRZ stage | find the 3 MRZ lines and verify their check digits |
| `OcrEngine` | classic OCR (**Tesseract** + **ML Kit**) | reads card text the classic way; also reads the MRZ for both engines |
| `PaddleLatinHybridRecognizer` | Paddle's front door | combines Paddle (Arabic) with ML Kit (Latin and digits) |
| `PaddleOcrEngine` | Paddle pipeline | finds text lines, reads each one |
| `OnnxRuntime` | `flutter_onnxruntime` | runs the two Paddle models on the phone |
| `DbPostProcess` | detector post-processing | turns the detector's output map into boxes |
| `CtcDecoder` | recognizer post-processing | turns the recognizer's output into characters |
| `RtlReorder` | Arabic order fix | recognizer output is left to right, Arabic must be right to left |
| `SudanCardParser` / `PaddleSudanCardParser` | text to fields | classic and Paddle parsers |

---

## 2. Why OpenCV?

OpenCV is a native image-processing library (C++) used through the `opencv_dart` package.
It is **not an OCR engine**. It only prepares pictures. Here is every use:

| Where | OpenCV calls | Why |
|---|---|---|
| `ImageOps.crop` (both engines) | `imread`, `rotate`, region crop, `resize` (cubic), `imwrite` | cut the photo to the card frame; rotate a landscape-saved photo upright; **upscale the thin MRZ strip** so Tesseract and ML Kit can read it |
| `PaddleOcrEngine` detection | `imread`, `resize` | the detector needs an image of a fixed kind: long side up to 960 px, sides multiples of 32 |
| `PaddleOcrEngine` recognition | region crop, `resize` to height 48 | the recognizer reads one text line at a time, scaled to a fixed height |
| `PaddleOcrEngine` digit retry | `cvtColor` (to LAB and back), `split`, `merge`, **CLAHE** | the card background pattern hides digits; contrast normalisation brought back a phone number that lost 3 of 10 digits |

**Why OpenCV and not Dart's own image code?**

- It is fast: these steps run on full camera photos (several megapixels). Pure Dart
  per-pixel loops would be much slower.
- Flutter's built-in image classes cannot crop or resample files without a UI, and no
  common Dart package has CLAHE.
- It was already in the project for `ImageOps` before Paddle was added; Paddle reuses it.

**What it costs:** about 10.5 MB per phone (arm64), even trimmed to two modules
(`imgcodecs`, `imgproc`) in `pubspec.yaml`. It is also what makes `flutter test` fail in
this environment (the native build needs CMake).

**Honest answer on whether you need it:** the crop and upscale could be done with a pure-Dart
image package, and the Paddle resize steps could be too, at lower speed. CLAHE is the one
thing that would have to be rewritten by hand. If app size matters more than scan speed,
dropping OpenCV is possible but is a separate piece of work.

---

## 3. The whole scan (shared by both engines)

```mermaid
sequenceDiagram
    actor User
    participant Home as AppHomePage
    participant Flow as IdentityFlowPage
    participant Cam as CardCameraPage
    participant Ops as ImageOps (OpenCV)
    participant Svc as IdentityScanService
    participant Mrz as MrzReader
    participant Eng as Card text engine
    participant Prs as Card parser
    participant Res as IdentityScanResult

    User->>Home: tap a button
    Home->>Flow: open with kind and engine
    Note over Home,Flow: Why: the button decides the engine, so both scanners can be compared on the same card

    loop front, then back
        Flow->>Cam: open camera
        User->>Cam: take photo
        Cam->>Ops: crop to the card frame
        Note over Cam,Ops: Why: OCR reads only the card, not the table around it. OpenCV crops and rotates the photo upright
        Ops-->>Flow: saved PNG path
    end

    User->>Flow: tap Scan
    Flow->>Svc: scan with both image paths, engine, parsers

    Svc->>Mrz: read the MRZ from the back
    Note over Svc,Mrz: Why first: the MRZ has check digits, so it is the one source we can prove correct
    Mrz-->>Svc: MrzData and attempts

    Svc->>Eng: recognizeCardText front
    Eng-->>Svc: text
    Svc->>Prs: parseFront text
    Prs-->>Svc: front fields and warnings
    Svc->>Eng: recognizeCardText back
    Eng-->>Svc: text
    Svc->>Prs: parseBack text
    Prs-->>Svc: back fields

    Note over Svc: Merge: MRZ values win when their check digit passed. Printed values fill the rest. Disagreements become warnings
    Svc->>Res: build the payload
    Res-->>Flow: toJson plus engine and scanMs
    Flow-->>User: show the JSON
```

The only things that change between engines are the two objects in the middle:
**Card text engine** and **Card parser**. Sections 5 and 6 open those up.

---

## 4. Stage 1: the MRZ (shared)

```mermaid
sequenceDiagram
    participant Svc as IdentityScanService
    participant Mrz as MrzReader
    participant Ocr as OcrEngine
    participant Ops as ImageOps (OpenCV)
    participant Prs as MrzParser

    Svc->>Mrz: read back image
    Mrz->>Ocr: ML Kit on the full image
    Ocr-->>Mrz: text
    Mrz->>Prs: parse and check the digits
    Prs-->>Mrz: MrzData with passed checks

    alt all check digits pass
        Mrz-->>Svc: done after one attempt
    else some check failed
        Mrz->>Ops: crop the bottom band, upscale to 1800 px wide
        Note over Mrz,Ops: Why: the MRZ is small text. A tight, enlarged strip is much easier to read than the whole card
        Ops-->>Mrz: band image
        Mrz->>Ocr: ML Kit on the band
        Mrz->>Prs: parse and check
        opt still failing
            Mrz->>Ocr: Tesseract with an MRZ-only character set
            Note over Mrz,Ocr: Why: restricting Tesseract to A-Z, 0-9 and the filler stops it inventing other characters
            Mrz->>Prs: parse and check
        end
        opt still failing
            Mrz->>Ocr: Tesseract on the full image
            Mrz->>Prs: parse and check
        end
        Mrz-->>Svc: the best attempt, even if imperfect
    end
```

`MrzParser` reads the TD1 layout (3 lines of 30 characters), repairs letter and digit
confusions by field type (O/0, I/1, S/5, B/8) and verifies four check digits: document
number, date of birth, expiry and the composite. Every attempt is stored in `mrzAttempts`.
Both engines use this stage, including its Tesseract fallback.

---

## 5. Classic engine: Tesseract + ML Kit

```mermaid
sequenceDiagram
    participant Svc as IdentityScanService
    participant Eng as OcrEngine
    participant Tess as Tesseract (ara+eng)
    participant Kit as ML Kit (Latin)
    participant PU as ParserUtils
    participant Prs as SudanCardParser

    Svc->>Eng: recognizeCardText image
    loop psm 6, then 11, then 3
        Eng->>Tess: read with this page-segmentation mode
        Tess-->>Eng: text
    end
    Note over Eng,Tess: Why three passes: each mode finds lines the others miss (block text, sparse text, automatic layout)
    Eng->>Eng: merge unique lines
    Eng->>PU: normalizeArabic on each line
    Note over Eng,PU: Why: drop tatweel, unify alef forms, so labels match however Tesseract spelled them
    Eng->>Kit: read the full image
    Note over Eng,Kit: Why: ML Kit is better than Tesseract at Latin text and digits
    Kit-->>Eng: Latin lines
    Eng->>Eng: merge unique lines with the Tesseract lines
    Eng-->>Svc: one text blob

    Svc->>Prs: parseFront or parseBack
    Note over Prs: Reads each field by its Arabic label, then falls back to the next line or a pattern anywhere in the text
    Prs-->>Svc: fields and warnings
```

Notes:

- No image pre-processing: the cropped photo goes straight in.
- Output is plain text; no boxes or confidences.
- Parser rules: name after الإسم (else a 3-word Arabic line); national number is 11 digits;
  date of birth after تاريخ الميلاد; place of birth, profession, address after their labels;
  blood type pattern `[ABO][+-]`; phone is a 10-digit number starting 09 or 01 on the `ت/`
  line; on the back, issue and expiry dates by label or the two most recent dates.
- **Weak points seen in the code** (found when this parser was fed Paddle text, so they
  apply to any text it receives): with a required pattern and no value on the label's line,
  the next line is returned unchecked, so a national number could come out as the next label;
  the blood-type pattern ends with `\b`, which cannot match after `+` at the end of a line;
  an address on the line below its label is missed; labels must match exactly. The classic
  parser is deliberately left unchanged as the baseline, so these are documented, not fixed.
- Cost: Tesseract models 5.5 MB + native libraries about 8.3 MB (arm64), about 14 MB.

---

## 6. Paddle engine

### 6.1 Overview: the hybrid recognizer

```mermaid
sequenceDiagram
    participant Svc as IdentityScanService
    participant Hy as PaddleLatinHybridRecognizer
    participant Pad as PaddleOcrEngine
    participant Kit as ML Kit (Latin)
    participant Prs as PaddleSudanCardParser

    Svc->>Hy: recognizeCardText image
    Hy->>Pad: read Arabic and Latin lines
    Note over Hy,Pad: Why Paddle: it reads Arabic much better than Tesseract in the tests we ran
    Pad-->>Hy: lines in reading order
    Hy->>Kit: read the full image
    Note over Hy,Kit: Why also ML Kit: Paddle often drops values printed in Latin digits next to an Arabic label (date of birth, blood type O+, the back-of-card dates). ML Kit reads those reliably
    Kit-->>Hy: Latin lines
    Hy->>Hy: add only ML Kit lines with no Arabic letters, containing A-Z or 0-9, not already present
    Note over Hy: Why filter: ML Kit's attempts at Arabic are garbage and would pollute the parser
    Hy-->>Svc: one text blob
    Svc->>Prs: parseFront or parseBack
    Prs-->>Svc: fields and warnings
```

### 6.2 Inside `PaddleOcrEngine`

```mermaid
sequenceDiagram
    participant Hy as PaddleLatinHybridRecognizer
    participant Pad as PaddleOcrEngine
    participant CV as OpenCV
    participant Ort as OnnxRuntime
    participant Db as DbPostProcess
    participant Ctc as CtcDecoder
    participant Rtl as RtlReorder

    Hy->>Pad: recognize image
    opt first call only
        Pad->>Ort: create sessions for det.onnx and arabic_rec.onnx
        Note over Pad,Ort: Why lazy: loading 12.8 MB of models takes time, so it happens when first needed. Dictionary has 747 characters plus space
    end

    Pad->>CV: imread
    Pad->>CV: resize, long side at most 960, sides multiples of 32
    Note over Pad,CV: Why: the detector expects sizes divisible by 32, and a bigger image only makes it slower
    Pad->>Pad: BGR to float32, subtract mean and divide by std
    Note over Pad: Why: the model was trained on normalised pixels. The same numbers must be used here
    Pad->>Ort: det.onnx with the image tensor
    Ort-->>Pad: probability map, one value per pixel for "is text"
    Pad->>Db: boxes from the map
    Note over Db: Threshold 0.3, connected blobs, keep blobs with mean score at least 0.6, expand each box by 0.7
    Note over Db: Why expand 0.7 and not Paddle's default 1.5: at this card size 1.5 made the phone row twice the text height, swallowing the address line below, and the recognizer dropped digits
    Db-->>Pad: text boxes, scaled back to the photo

    loop for each box
        Pad->>CV: crop the box, resize to height 48
        Note over Pad,CV: Why: the recognizer reads one line at a time at a fixed height
        Pad->>Ort: arabic_rec.onnx
        Ort-->>Pad: logits, one score per character per time step
        Pad->>Ctc: greedy decode
        Note over Ctc: Take the best class per step, drop repeats and blanks. Gives text and a mean confidence
        Ctc-->>Pad: text and confidence
        alt confidence below 0.3
            Pad->>Pad: discard the line as noise
        else keep
            Pad->>Rtl: fix the order
            Note over Rtl: Why: the model returns letters left to right as drawn on the image. Arabic must be read right to left. Number runs are kept the right way round
            Rtl-->>Pad: logical text
            opt line contains digits
                Pad->>CV: CLAHE contrast normalisation on the crop
                Note over Pad,CV: Why: the card background pattern hides digits (a phone lost 3 of 10)
                Pad->>Ort: arabic_rec.onnx again
                Pad->>Pad: keep whichever read has more digits
            end
        end
    end

    Pad->>Pad: sort boxes top to bottom, group into rows, order each row right to left
    Note over Pad: Why: Arabic cards are read right to left, label on the right and value on its left. A row with several boxes is also emitted joined, so the parser can match either form
    Pad-->>Hy: lines in reading order
```

### 6.3 Why each Paddle design choice

| Choice | Why |
|---|---|
| Two models (detector + recognizer) | OCR here is two jobs: find the lines, then read each one. Paddle splits them |
| ONNX Runtime | runs the converted models on the phone, offline, on both Android and iOS, with no Paddle framework in the app |
| Converted from the official weights ourselves | no official ONNX files exist; our conversion is documented with SHA-256 in `assets/models/paddle/README.md` |
| CTC decoding | the recognizer outputs a score per time step, not a string; CTC turns it into characters |
| Right-to-left reorder | without it Arabic text comes out reversed, and Arabic-Indic digits (٠-٩) must not be reversed with the letters |
| CLAHE retry only on digit lines | it fixes digits but would slow every line; one extra read where it matters |
| Hybrid with ML Kit | Paddle misses Latin-digit values, ML Kit does not |
| Own parser | the classic parser's fall-backs return wrong values when Paddle gives clean separate lines |

### 6.4 `PaddleSudanCardParser`

```mermaid
sequenceDiagram
    participant Svc as IdentityScanService
    participant Prs as PaddleSudanCardParser

    Svc->>Prs: parseFront text
    Note over Prs: Each field is read from its own labelled line and checked by shape. A missing value stays null and is never borrowed from the next line
    Prs->>Prs: name, national number, date of birth, place of birth
    Prs->>Prs: blood type, profession, address, phone
    Note over Prs: Why a phone rule of its own: it is the only number printed in Arabic-Indic digits, so any line with 6 or more such digits is the phone, even if the label was misread
    Prs-->>Svc: fields and warnings (incomplete phone, missing name)
    Svc->>Prs: parseBack text
    Prs->>Prs: place of issue, issue date, expiry date
    Note over Prs: Why the two most recent dates: the date of birth is printed on the back too, right next to the issue and expiry labels, so labels cannot be trusted to pick the date
    Prs-->>Svc: back fields
```

| Field | Rule |
|---|---|
| `arabicName` | after the name label (tolerates الإسم / الاسم / ااسم); if the label is lost, the first Arabic line of 3+ words above the date of birth that is not a heading |
| `nationalNumber` | exactly 11 digits; labelled line first, then any line |
| `dateOfBirth` | `yyyy/mm/dd` or `dd/mm/yyyy`; labelled line first, then any line |
| `placeOfBirth`, `profession` | Arabic text after their label |
| `bloodType` | A, B, AB or O with `+` or `-`; sign on either side; `0` read as `O`; label line first, then short lines with no Arabic |
| `address` | text after the address label minus the phone part, else the first real Arabic line below it (6+ letters), skipping the issuing-authority block that can sit between them |
| `phone` | digits after `ت/`, converted to Latin; a lost leading 0 is added; a trailing 1 that was really the `/` is dropped; other than 10 digits triggers a warning |
| back `placeOfIssue` | after `مكان الإصدار`; the label accepts a misread last letter (الإصدان) because the `:` is often read as a letter |

---

## 7. Stage 3: merge and cross-check (shared)

```mermaid
sequenceDiagram
    participant Svc as IdentityScanService
    participant Mrz as MrzData
    participant Front as front and back fields
    participant Out as identity map

    Svc->>Mrz: which check digits passed?
    Mrz-->>Svc: documentNumber, dateOfBirth, expiry, composite
    Svc->>Out: copy MRZ fields whose check passed
    Note over Svc,Out: Why: a passed check digit means the value is very likely correct, so OCR guesses must not overwrite it
    Svc->>Front: read the printed fields
    Svc->>Out: fill what the MRZ does not have
    Note over Svc,Out: Arabic name, place of birth, profession, address, blood type, phone, national number, issue place and date
    Svc->>Out: printed date differs from a trusted MRZ date?
    Note over Svc,Out: Keep the MRZ date and add a warning
    Svc->>Out: issue date on or after expiry?
    Note over Svc,Out: Drop the issue date. It cannot be right
```

---

## 8. Side by side

| | Classic | Paddle |
|---|---|---|
| Arabic OCR | Tesseract `ara+eng`, 3 passes | PaddleOCR detector + Arabic recognizer |
| Latin text and digits | ML Kit (merged) | ML Kit (lines without Arabic merged) |
| Image pre-processing | none | resize for the detector; CLAHE retry on digit lines |
| Line detection | Tesseract's own | DB detector, 0.7 box expansion |
| Right-to-left handling | inside Tesseract | explicit reorder of the recognizer's output |
| OCR output | text only | text with boxes and confidences |
| Parser | `SudanCardParser` | `PaddleSudanCardParser` |
| Missing value | can borrow the next line | stays `null` |
| Phone | exactly 10 digits starting 09 or 01 | digits after `ت/`, repaired, flagged if not 10 |
| Raw OCR text in payload | no (Sudan ID) | yes (`rawText`) |
| Size (arm64) | about 14 MB | about 41 MB (ONNX Runtime 28.6 + models 12.8) |
| OS requirement | none extra | iOS 16.0+, static linking |
| Speed | not measured | about 7 s per scan on one phone |
| Known weaknesses | see section 5 | Arabic letter confusions; heuristic row grouping; axis-aligned boxes only; needs ML Kit for Latin values |

OpenCV (about 10.5 MB) and ML Kit (about 11 MB) are in the app for both engines.

---

## 9. Payload

`IdentityScanResult.toJson()` plus `engine` and `scanMs` (both engines) and `rawText`
(Paddle only). All values below are **made up**, to show the shape.

```json
{
  "documentKind": "sudanId",
  "identity": {
    "documentType": "ID",
    "documentNumber": "012345678",
    "nationalNumber": "12345678901",
    "arabicName": "اسم أول اسم ثاني اسم ثالث",
    "englishName": "FIRST SECOND THIRD FAMILY",
    "surname": "FAMILY",
    "givenNames": "FIRST SECOND THIRD",
    "dateOfBirth": "1990-01-15",
    "sex": "M",
    "nationality": "SDN",
    "issuingCountry": "SDN",
    "issueDate": "2022-05-17",
    "expiryDate": "2027-05-16",
    "placeOfBirth": "الخرطوم - أم درمان",
    "placeOfIssue": "مجمع بحري",
    "profession": "طالب",
    "address": "حي المثال بحري الخرطوم",
    "bloodType": "O+",
    "phone": "0912345678"
  },
  "mrz": {
    "format": "TD1",
    "documentCode": "ID",
    "issuingCountry": "SDN",
    "documentNumber": "012345678",
    "dateOfBirth": "1990-01-15",
    "sex": "M",
    "expiryDate": "2027-05-16",
    "nationality": "SDN",
    "surname": "FAMILY",
    "givenNames": "FIRST SECOND THIRD",
    "optionalData": "",
    "checks": { "documentNumber": true, "dateOfBirth": true, "expiryDate": true, "composite": true },
    "isValid": true,
    "lines": ["IDSDN…", "…", "…"]
  },
  "front": { "arabicName": "…", "nationalNumber": "…", "dateOfBirth": "1990/01/15",
             "placeOfBirth": "…", "bloodType": "O+", "profession": "…",
             "address": "…", "phone": "0912345678" },
  "back":  { "placeOfIssue": "…", "issueDate": "2022/05/17", "expiryDate": "2027/05/16" },
  "warnings": [],
  "images": { "front": "/data/user/0/<app>/cache/card_front_….png",
              "back":  "/data/user/0/<app>/cache/card_back_….png" },
  "rawText": { "front": "<what OCR read, one line per box>", "back": "<…>" },
  "mrzAttempts": [ { "source": "mlkit/full", "text": "…", "passedChecks": 4 } ],
  "scannedAt": "2026-10-29T10:00:00.000",
  "engine": "paddle+mlkit-latin",
  "scanMs": 7140
}
```

How to read it:

- **`identity`** is what consumers should use: merged and cross-checked.
- **`front` / `back`** are the parser outputs (`null` where nothing was read), to see what came
  from the printed card versus the MRZ.
- **`rawText`** (Paddle) is exactly what OCR returned before parsing. When a field is wrong,
  look here first: if the text is not there, the problem is recognition; if it is, the parser.
- **`warnings`**: missing required fields, MRZ and print disagreements, incomplete phones.
- **`mrz.checks` and `isValid`**: whether the MRZ values can be trusted.
- **`mrzAttempts`**: every MRZ read, for debugging.
- **`engine` and `scanMs`**: make the two engines comparable on the same card.

---

## 10. Files

```
lib/features/identity_scan/
  data/
    identity_scan_service.dart             orchestrates the three stages
    image/image_ops.dart                   crop and upscale (OpenCV)
    mrz/mrz_reader.dart, mrz_parser.dart   MRZ stage (shared)
    front/sudan_card_parser.dart           classic parser
    front/parser_utils.dart, card_dates.dart   helpers used by the classic parser
    ocr/
      card_text_recognizer.dart            interface both engines implement
      ocr_engine.dart                      classic engine (Tesseract + ML Kit)
      paddle/
        paddle_ocr_engine.dart             detector + recognizer pipeline
        db_postprocess.dart                probability map to boxes
        ctc_decoder.dart                   logits to text
        rtl_reorder.dart                   visual to logical order
        paddle_latin_hybrid_recognizer.dart  Paddle + ML Kit Latin lines
        paddle_sudan_card_parser.dart      Paddle parser
  domain/scan_engine.dart                  classic | paddle
  presentation/pages/identity_flow_page.dart   chooses the engine per scan
assets/tessdata/                           Tesseract ara + eng
assets/models/paddle/                      ONNX models, dictionary, provenance README
```

The classic scanner is intentionally untouched; Paddle fixes live only in `paddle/`.
The engine is picked through optional parameters on `IdentityScanService.scan`
(`cardText`, `parseFront`, `parseBack`, `includeRawText`); with none given it runs the classic
path exactly as before.

Models (`assets/models/paddle/`):

| File | Source | Size |
|---|---|---|
| `det.onnx` | `PaddlePaddle/PP-OCRv5_mobile_det`, paddle2onnx 2.1.0, opset 14 | 4.8 MB |
| `arabic_rec.onnx` | `PaddlePaddle/arabic_PP-OCRv5_mobile_rec`, same conversion | 8.0 MB |
| `arabic_dict.txt` | `character_dict` from the recognizer's `inference.yml` | 2 KB |

---

## 11. Known limits and next steps

- **Single-card tuning.** Paddle's constants (box expansion 0.7, confidence 0.3, CLAHE 2.0 with
  4x4 tiles) and parser rules were tuned on one Sudan ID and one phone. Run both engines on
  30 to 50 real cards (good and bad light) and compare field accuracy before choosing.
- **Arabic misreads remain** in Paddle (ميرغنى for ميرغني, الحرطوم for الخرطوم); no word
  lists or spell correction are applied.
- **Axis-aligned boxes only** in Paddle: a tilted card reads worse.
- **Latin values depend on ML Kit** in the Paddle path.
- **Speed.** About 7 s for Paddle; tensors cross a platform channel and pixel loops run in
  Dart. A smaller detector input or an FFI runtime are untried.
- **Tests.** `flutter test` does not run in this environment (the OpenCV native build
  fails); decoder, detector and parser checks ran as standalone Dart scripts.
  `test/paddle_decoding_test.dart` covers the decoder and right-to-left code.
- **Moving to a package.** Add `flutter_onnxruntime`, set iOS to 16.0 with static linking,
  bundle `assets/models/paddle/`; asset paths become `packages/<name>/assets/...` (three
  constants at the top of `PaddleOcrEngine`). Paddle adds about 41 MB per phone (arm64,
  uncompressed); replacing Tesseract nets about +27 MB.
