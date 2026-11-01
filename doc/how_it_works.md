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
   produce issues, they never stop a scan.
3. **MRZ stage** (ID card and passport). The machine-readable lines are located,
   read with ML Kit, repaired by expected character type (`O`/`0`, `I`/`1`,
   `S`/`5`, `B`/`8`) and accepted only when the ICAO 9303 check digits agree.
   The best read is kept even when some digits fail, so a near miss is visible.
4. **Printed-text stage.** PaddleOCR (detector + Arabic recogniser, ONNX Runtime)
   reads the Arabic text, ML Kit reads the Latin text, and per-document parsers
   pick the fields by label and position.
5. **Merge.** A value from the MRZ wins when its own check digit passed;
   printed values fill the rest. A printed value that disagrees with the MRZ
   becomes a warning.
6. **Result.** Fields, MRZ, issues, warnings and the images are returned as one
   typed object.

## What "verified" means

| Status | Meaning |
|---|---|
| `verified` | No issues and no warnings. For ID cards and passports this includes all MRZ check digits passing. |
| `needsReview` | Fields were read but something is off (blurry photo, failed check digit, a printed value disagreeing with the MRZ). |
| `failed` | Wrong document, document not in the frame, no MRZ found, or an unexpected processing error. Images are still returned. |
| `incomplete` | The user left before every page was captured. Nothing was read. |

A civil registry certificate has no MRZ, so for it `verified` only means the photo
was fine and every expected field was read.

## Models

The OCR models live in `assets/models/paddle/` with their provenance and hashes
in that folder's README. They are Apache-2.0 PaddleOCR weights converted to ONNX.
