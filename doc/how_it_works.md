# How idlens works

**From a photo of an identity document to typed, checked fields, all on the
phone.** This page explains what happens between the moment a photo exists and
the moment you get a result, why each step is there, and how to read what comes
back. If you only want to use the package, the
[README](https://github.com/WaseemAlBizreh/OCR#readme) is the place to start.

Everything runs on the device. No image or text is uploaded, and idlens makes
no network calls.

## Contents

- [The idea in 30 seconds](#the-idea-in-30-seconds)
- [One scan, step by step](#one-scan-step-by-step)
  - [1. The photo](#1-the-photo)
  - [2. Photo checks](#2-photo-checks)
  - [3. The MRZ](#3-the-mrz-id-card-and-passport)
  - [4. The printed text](#4-the-printed-text)
  - [5. Merge](#5-merge)
  - [6. Review](#6-review)
  - [7. The result](#7-the-result)
- [The time limit](#the-time-limit)
- [What "verified" means](#what-verified-means)
- [Models and privacy](#models-and-privacy)
- [Where things live in the code](#where-things-live-in-the-code)
- [Links](#links)

## The idea in 30 seconds

1. **You always get the photos back,** even when reading fails, so your app can
   still upload them for manual review.
2. **A photo problem and a doubt about one value are different things.** A blurry
   photo is an *issue*: retake it. A date that disagrees with the MRZ is a *field
   to check*: ask the user to look at that one field.
3. **The MRZ is the anchor.** Its check digits prove a value is right. Printed
   text fills in the rest and is never trusted over an MRZ value that passed.
4. **One set of rules for every document.** An ID card, a passport and a
   certificate all go through the same review, so a status means the same thing
   everywhere.

## One scan, step by step

```
photo ──► photo checks ──► MRZ stage ──► printed-text stage ──► merge ──► review ──► result
```

| Step | What it does | Output |
|---|---|---|
| 1. Photo | Makes sure the photo has the shape the checks expect | A cropped photo with a strip of background |
| 2. Photo checks | Measures clarity, distance and cut-off | A possible `issue` |
| 3. MRZ | Finds, reads, repairs and validates the machine-readable lines | An `MrzData` with every check digit |
| 4. Printed text | Reads the Arabic and Latin text and picks the fields | Fields from the printed text |
| 5. Merge | Combines the MRZ and the printed text | One set of fields, with doubts marked |
| 6. Review | Turns everything into `status`, `issue`, `issueSides`, `fieldsToCheck` | The verdict |
| 7. Result | Packs fields, MRZ, verdict and images | An `IdCardResult`, `PassportResult` or `CivilRegistryResult` |

### 1. The photo

Each page of a document gets one photo: an ID card has a front and a back, a
passport has its data page, and a certificate has its one page.

idlens' checks (cut off? too far?) need to see a thin **strip of background
around the document**. It is how they tell a document that ends inside the photo
from one that runs past its edge.

```
 photo
 ┌───────────────────────────┐
 │  ·   strip of background  │   The strip is 6% of the document's size
 │   ┌───────────────────┐   │   on every side.
 │   │                   │   │
 │   │     document      │   │   The box the user fits the document into is
 │   │       (box)       │   │   86% of the camera area wide, so the strip
 │   │                   │   │   always fits.
 │   └───────────────────┘   │
 │                           │
 └───────────────────────────┘
```

The photo gets its strip in one of three ways, and they all use the same crop
function, so the checks see the same photo whichever way you scan:

| You use | Who makes the photo | Where the crop happens |
|---|---|---|
| `scan...` | idlens' own camera | At capture |
| `process...` with `DocumentPhoto.camera` | Your own camera | Inside the `process...` call, around the box from `DocumentGuide` |
| `process...` with `DocumentPhoto.file` | You (a finished photo) | Nowhere: the photo is read as it is |

A certificate is straightened into a flat A4 copy, but only for reading (step
4). The checks look at the photo with its strip, and your image is never
changed.

### 2. Photo checks

These measure the photo itself. They only produce an `issue`: they never stop a
scan, so the user can still choose "Use anyway", and you always get the images.

| Check | Question | `issue` |
|---|---|---|
| Sharpness, brightness, glare | Is it clear enough to read? | `imageNotClear` |
| Distance | Does the document fill enough of the box? (A document narrower than about 72% of the box counts as too far.) | `documentNotInFrame` |
| Cut-off | Does the document run past an edge of the photo? | `documentNotInFrame` |

**Cut-off uses three checks, strongest first,** and each is used only when the one
before it can't decide:

1. **The document's outline.** The four corners are found. A corner within about
   1.5% of an edge means the document is cut off there.
2. **Its bright area against the background.** An area lying along an edge for at
   least half its own side runs past it. A hand holding the card touches the
   edge over a much shorter stretch, so it doesn't count.
3. **Printed text running up to an edge.**

One cut edge is enough for the first two. A document moved a little to one side
is cut on one side only, so this catches it.

The numbers were tuned on a small number of real photos and are still checked
against more: see [Accuracy](https://github.com/WaseemAlBizreh/OCR#accuracy) in
the README.

### 3. The MRZ (ID card and passport)

The machine-readable zone is the three (ID card) or two (passport) lines of
letters and `<` signs at the bottom. It is the most reliable part of the
document, because it carries check digits.

1. **Find and read** the lines with ML Kit.
2. **Repair look-alikes by the type of character expected** in each position:
   `O` and `0`, `I` and `1`, `S` and `5`, `B` and `8`. A digit position can't
   hold an `O`, so it is read as a `0`.
3. **Validate** with the ICAO 9303 check digits: the document number, the date
   of birth, the expiry date and the composite digit (plus the personal number on
   a passport).
4. **Keep the best read** even when some digits fail, so a near miss is visible
   in `result.mrz.checks`.
5. **Notice a cut MRZ.** A name has no check digit, so a name cut short by the
   photo would pass unnoticed. A line missing its first or last characters gives
   `documentNotInFrame` and `mrz.cutOff`.

A certificate has no MRZ, so it skips this step.

### 4. The printed text

- **PaddleOCR** (a detector and an Arabic recogniser, run with ONNX Runtime)
  reads the Arabic text.
- **ML Kit** reads the Latin text.
- **A parser for each document** picks the fields by their labels and their
  position on the page.

Reading runs off the app's UI work as much as possible: image work uses OpenCV's
background threads, and the detector's input and its text-box search run on a
short-lived worker isolate.

### 5. Merge

- A value from the **MRZ wins** when its own check digit passed.
- **Printed values fill the rest.**
- A printed value that **disagrees with the MRZ**, or a **date that can't be
  right** (an issue date on or after the expiry date; on a certificate also a birth
  date not before the issue date), is **kept and marked as doubtful**. idlens never clears a value it
  read: it tells you to look at it.

### 6. Review

One place (`ScanReview`) turns all of this into the verdict, with the same rules
for every document.

| Output | Question it answers |
|---|---|
| `issue` | What is wrong with the photo or the document as a whole? |
| `issueSides` | Which pages should the user retake? |
| `fieldsToCheck` | Which fields should the user look at? |
| `status` | How far can the result be trusted? |

An ID card has two photos, so the front's and the back's checks are kept apart:
`issueSides` can name only the side that caused the issue, and the user doesn't
retake a good photo. When both photos have problems, the more serious issue is
reported, in this order: `wrongDocument`, `readerUnavailable`, `timedOut`,
`processingFailed`, `documentNotInFrame`, `contentNotFound`, `imageNotClear`.

### 7. The result

Fields, MRZ, issue, fields to check and the images come back as one typed
object. English warnings meant for your logs are in `diagnostics`; they are not
part of the stable API. See
[Reading the result](https://github.com/WaseemAlBizreh/OCR#results) in the README
for every member.

## The time limit

With a `timeout`, the whole read, including cropping a camera photo, runs under
one deadline (`ScanDeadline`). When it passes, the result returns at once as
`failed` with `timedOut`, even if a native call is stuck, and the photos are
fine. The text reader checks the deadline before each text line and between
stages, so the read left behind stops at its next step instead of running to the
end.

## What "verified" means

| Status | Meaning |
|---|---|
| `verified` | No issue, and nothing in `fieldsToCheck`. For ID cards and passports this includes all MRZ check digits passing. |
| `needsReview` | The photo isn't clear, or a field needs checking: a required field not read, a printed value disagreeing with the MRZ, a failed check digit, or a date that can't be right. |
| `failed` | Wrong document, document not in the frame, nothing identifying read (no MRZ, or none of a certificate's required fields), the text reader couldn't start, reading took longer than the `timeout`, or an unexpected processing error. `issue` says which. Images are still returned. |
| `incomplete` | The user left before every page was captured. Nothing was read. |

Required fields are the Arabic name and national number on an ID card, and the
national number, name and date of birth on a certificate. A passport has none
beyond its MRZ. Any other field not read is `null`, isn't in `fieldsToCheck` and
doesn't change the status.

A civil registry certificate has no MRZ, so for it `verified` only means the
photo was fine, the required fields were read and the dates agree. It doesn't
prove the values are correct.

## Models and privacy

The OCR models live in `assets/models/paddle/`, with their provenance and hashes
in that folder's README. They are Apache-2.0 PaddleOCR weights converted to ONNX
and add about 12 MB to your app. ML Kit and OpenCV have their own licenses.

Photos are kept only in the app's temporary folder until you call `dispose()` or
the system clears it.

## Where things live in the code

For contributors. Paths are relative to `lib/src/`.

| Folder or file | What is there |
|---|---|
| `idlens_scanner.dart` | `IdLens`, the one public entry point |
| `api/` | Everything public: results, `DocumentPhoto`, `DocumentGuide`, options, `ScanException`, and `scan_review.dart` (the review rules) |
| `scan_runner.dart` | Runs a document through the steps; the built-in flow and `process...` both go through it |
| `presentation/` | The built-in screens, and `capture_crop.dart`, the one crop function |
| `data/image/` | OpenCV work: crops, straightening, clarity and framing measurements |
| `data/mrz/` | Finding, reading and parsing the MRZ |
| `data/ocr/paddle/` | The PaddleOCR engine and the parsers for each document |
| `domain/` | Plain types and rules: framing, image quality, MRZ validation, the deadline |

## Links

- [README](https://github.com/WaseemAlBizreh/OCR#readme): installation, the two ways to use idlens, and examples
- [Changelog](https://pub.dev/packages/idlens/changelog)
- [idlens on pub.dev](https://pub.dev/packages/idlens)
- [Report an issue](https://github.com/WaseemAlBizreh/OCR/issues)
