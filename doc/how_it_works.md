# How idlens works

Everything runs on the device. Nothing is uploaded.

## One scan, step by step

```
photos ──► photo checks ──► MRZ stage ──► printed-text stage ──► merge ──► result
```

1. **Photos.** The built-in flow takes one photo per page (ID: front and back;
   passport: data page; certificate: the page), cropped to the on-screen frame.
   The `process*` methods take files you already have and skip this step.
2. **Photo checks.** Sharpness, brightness, glare and how much of the frame the
   document fills are measured (`ImageQualityChecker`); text running into the
   photo's edges means the document is cut off (`FrameEdgeChecker`). They only
   produce an issue, they never stop a scan.
3. **MRZ stage** (ID card and passport). The machine-readable lines are located,
   read with ML Kit, repaired by expected character type (`O`/`0`, `I`/`1`,
   `S`/`5`, `B`/`8`) and accepted only when the ICAO 9303 check digits agree.
   The best read is kept even when some digits fail, so a near miss is visible.
4. **Printed-text stage.** PaddleOCR (detector + Arabic recogniser, ONNX Runtime)
   reads the Arabic text, ML Kit reads the Latin text, and per-document parsers
   pick the fields by label and position.
5. **Merge.** A value from the MRZ wins when its own check digit passed;
   printed values fill the rest. A printed value that disagrees with the MRZ,
   or a date that can't be right, is kept and marked as doubtful.
6. **Review** (`ScanReview`). One place turns all of this into the result's
   `issue`, the sides to retake (`issueSides`), `fieldsToCheck` and
   `status`, with the same rules for every document. An ID card keeps the
   front's and the back's photo checks apart, so `issueSides` can name only
   the side that caused the issue.
7. **Result.** Fields, MRZ, issue, fields to check and the images are returned
   as one typed object. English warnings for logs are in `diagnostics`.

## What "verified" means

| Status | Meaning |
|---|---|
| `verified` | No issue, and nothing in `fieldsToCheck`. For ID cards and passports this includes all MRZ check digits passing. |
| `needsReview` | The photo isn't clear, or a field needs checking: a required field not read, a printed value disagreeing with the MRZ, a failed check digit, or a date that can't be right. |
| `failed` | Wrong document, document not in the frame, nothing identifying read (no MRZ, or none of a certificate's required fields), the text reader couldn't start, or an unexpected processing error. `issue` says which. Images are still returned. |
| `incomplete` | The user left before every page was captured. Nothing was read. |

Required fields are the Arabic name and national number on an ID card, and the
national number, name and date of birth on a certificate. A passport has none
beyond its MRZ. Any other field not read is `null`, isn't in `fieldsToCheck`
and doesn't change the status.

A civil registry certificate has no MRZ, so for it `verified` only means the photo
was fine, the required fields were read and the dates agree. It doesn't prove the
values are correct.

## Models

The OCR models live in `assets/models/paddle/` with their provenance and hashes
in that folder's README. They are Apache-2.0 PaddleOCR weights converted to ONNX.
