# idlens: Bugs to Fix in the Package

These bugs are in the `idlens` package ([`WaseemAlBizreh/OCR`](https://github.com/WaseemAlBizreh/OCR)), not in the MTN app. They were found by reading idlens 0.1.3 while reviewing the SIM registration OCR on 2026-11-02. Bugs on the app side are in [`SIM_REGISTRATION_OCR_BUGS.md`](SIM_REGISTRATION_OCR_BUGS.md).

**How this was checked:** by reading the source. Nothing was run on a device, and I didn't run idlens' own tests. I1 matches a real A4 scan where the notice appeared with one value missing, though the missing field wasn't confirmed. File paths are relative to `lib/src/` in the package.

| # | Bug | Priority | Suggested release |
|---|---|---|---|
| [I1](#i1-a-missing-field-is-treated-as-a-value-to-review) | A missing field is treated as a value to review | **Fixed, not released** | Next release (breaking API change) |
| [I2](#i2-a-model-that-fails-to-load-breaks-every-later-scan) | A model that fails to load breaks every later scan | **Fixed, not released** | Next release |
| [I3](#i3-image-work-runs-on-the-ui-isolate) | Image work runs on the UI isolate | **Fixed, not released** | Next release |
| [I4](#i4-some-certificate-values-have-no-confidence-score) | Some certificate values have no confidence score | **Fixed by removing the score, not released** | Next release (breaking API change) |
| [I5](#i5-a-cut-off-document-is-accepted) | A cut-off document is accepted | **Fixed, not released** (limits to check on real photos) | Next release |
| [I6](#i6-issues-dont-say-which-side-of-the-id-caused-them) | Issues don't say which side of the ID caused them | **Fixed, not released** | Next release (adds `issueSides`) |
| [I7](#i7-a-running-read-cant-be-cancelled) | A running read can't be cancelled | **Fixed with a time limit, not released** | Next release (adds `timeout`) |
| [I8](#i8-a-document-far-from-the-camera-can-be-accepted) | A document far from the camera can be accepted | **Fixed, not released** (limit to check on real photos) | Next release |
| [I9](#i9-processcivilregistry-doesnt-flatten-the-page) | `processCivilRegistry` doesn't flatten the page | **Fixed, not released** | Next release |
| [I10](#i10-apps-have-to-build-their-own-camera) | Apps have to build their own camera, with no Arabic support | High, comes before the accuracy test | 0.1.4 |
| [I11](#i11-scan-has-its-own-path-and-no-clear-role) | `scan*` has its own path and no clear role | Medium | 0.1.4 and 0.2.0 |

## Recommended order

1. **Release 0.1.4 with I2, I4, I8, I9, I10 and the shared camera from I11.** None of them breaks the API, so the app can upgrade with `flutter pub upgrade`. I10 only adds to it. Include I3 if phone testing shows a freeze.
2. **Release 0.2.0 with I1, I5, I6 and the option cleanup from I11.** These change results, their types or method signatures, so they fit in one breaking release. The app's `^0.1.3` constraint won't pick up 0.2.0, so its `pubspec.yaml` must change too.
3. **Decide on I7 later,** once read times are measured. The app can skip stale queued reads without it.

---

## I1. A missing field is treated as a value to review

- [x] Fixed in idlens (2026-11-02, reworked 2026-11-03, not committed or released)
- [ ] Adopted in the app

**Summary of the fix**

The first fix (2026-11-02) only shortened the required-field lists. On
2026-11-03 the result was simplified so that apps never read warning text. This
changes the API, so the app must update its code when it upgrades.

The result now says two things: whether to retake (`status` and `issue`) and
which fields to look at (`fieldsToCheck`).

| Before | Now |
|---|---|
| `issues` (list) | `issue`: one `ScanIssue` or `null`, always set when `failed` |
| `warnings` (text, also drove the status) | Removed. `fieldsToCheck` lists field keys, and the text moves to `diagnostics['warnings']` for logs |
| `mrzNotFound` | Removed. Gives `imageNotClear` (or `documentNotInFrame`), and still `failed` |
| `mrzCheckDigitsFailed` | Removed. The fields the failed digits cover go in `fieldsToCheck` |
| An impossible issue date (ID, passport) cleared with no warning | Kept as read, and listed |
| A certificate birth date not before its issue date cleared | Kept as read, with both dates listed |
| A certificate with nothing readable was `needsReview` | `failed` with `imageNotClear` |

A field in `fieldsToCheck` with a `null` value is a required field that wasn't
read. With a value, it was read but may be wrong. Optional fields that weren't
read are `null` and never listed.

| Status | When |
|---|---|
| `failed` | `wrongDocument`, `documentNotInFrame` or `processingFailed`, or nothing identifying read (no MRZ, or none of a certificate's 3 required fields) |
| `needsReview` | `imageNotClear`, or `fieldsToCheck` isn't empty |
| `verified` | Neither |

**Decisions:** impossible values are kept rather than cleared. idlens doesn't
judge OCR confidence yet: a `lowConfidence` rule waits for the accuracy test to
set the limit. Which side of the ID caused an issue stays in
[I6](#i6-issues-dont-say-which-side-of-the-id-caused-them).

**Files changed:** new `api/scan_review.dart` (all the rules), `scan_outcome.dart`,
the three result classes, `scan_status.dart`, `domain/scan_issue.dart`,
`domain/mrz_validator.dart`, `domain/identity_scan_result.dart`,
`scan_runner.dart`, `data/identity_scan_service.dart` (the shared ID service,
which records doubtful fields), the Paddle passport scan service, the
certificate parser, reading and scan service, the built-in flow's dialogs
(`presentation/scan_issue_text.dart`, `identity_flow_page.dart`), the example
app, the README, `doc/how_it_works.md` and `CHANGELOG.md`. The classic
`SudanCardParser` and `PassportVizParser` weren't touched.

**How it was checked:** `flutter analyze` reports no issues for the package or
the example. 95 tests in 8 files pass (including the new
`test/scan_review_test.dart`), run in a scratch Dart package because
`flutter test` needs a native OpenCV build. Nothing was tried on a device.

**Still needed in the MTN app:** see the MTN issue written for this change.

**What happens**

`ScanOutcome.statusFor` returns `needsReview` when `warnings` isn't empty, and a missing field adds the warning `Missing field: <name>`. The app then tells the dealer "Some values may be wrong. Please check them."

| Document | A missing one of these triggers it | Where |
|---|---|---|
| Certificate | All 12: registry office, issue date, national number, name, place of birth, date of birth, marital status, gender, nationality type, profession, work address, mother's name | `data/ocr/paddle/civil_registry/civil_registry_parser.dart` |
| Passport page | Place of birth, issue date, place of issue | `data/ocr/paddle/passport/paddle_passport_parser.dart` |
| ID front | Arabic name, national number | `data/ocr/paddle/paddle_sudan_card_parser.dart` |

An incomplete phone number on the ID front also triggers it, and the form doesn't use the phone number.

**Why it matters**

- A missing value isn't a wrong value, so the message is false.
- The form doesn't use five certificate fields or the passport's place of issue, yet they still trigger it. A missing mother's name warns the dealer even when the form is correct.
- If most certificates show the notice, dealers will learn to ignore it, including when it's real.

**Original suggestion (not used, see the summary above)**

Report missing fields separately, and make warnings structured so that apps don't have to match text:

```dart
class ScanOutcome {
  final ScanStatus status;
  final List<ScanIssue> issues;
  final List<ScanWarning> warnings; // Real doubts about a value.
  final List<String> missingFields; // Keys in `fields` that weren't read.
}

enum ScanWarningKind { mrzMismatch, inconsistentDates, incompleteValue }

class ScanWarning {
  const ScanWarning(this.kind, this.field, this.message);

  final ScanWarningKind kind;
  final String? field; // Key in `fields`, or null for the whole document.
  final String message; // For debugging. Don't show it to users.
}
```

Update the docs for `ScanStatus.verified`. On a certificate it currently also means "every expected field was read", and it should mean "nothing that was read looks wrong". `missingFields` then answers whether the read was complete.

**Expected behaviour after the fix**

| Scan | `status` | `missingFields` | App shows the notice? |
|---|---|---|---|
| Certificate, mother's name not read | `verified` | `motherName` | No |
| Certificate, name not read | `verified` | `name` | No. The field stays empty, and the form requires it before Next |
| Certificate, birth date not before issue date | `needsReview` | `dateOfBirth`, which idlens clears | Yes |
| Passport, place of issue not read | `verified` | `placeOfIssue` | No |
| Passport or ID, printed date differs from the MRZ | `needsReview` | None | Yes |
| ID front, phone incomplete | `needsReview`, with `field: phone` | None | No. The app ignores warnings for fields it doesn't use |
| Any document, unclear photo | `needsReview` | Any | Yes |
| Passport or ID, MRZ check digits fail | `needsReview` | Any | Yes |

**What to change in the app after the fix**

- Upgrade `pubspec.yaml` to the new version.
- In [`document_reader_service.dart`](../../lib/core/services/document_reader/document_reader_service.dart), add a list of the fields the form uses for each document. Treat a result as needing review only when it has an issue, a warning for the whole document, or a warning for one of those fields.
- Add service tests for the rows in the table above.
- Do the follow-up in [B2](SIM_REGISTRATION_OCR_BUGS.md#b2-the-needs-review-notice-triggers-on-missing-fields): also show the notice on the subscriber info step.

---

## I2. A model that fails to load breaks every later scan

- [x] Fixed in idlens (2026-11-03, not committed or released)
- [ ] Adopted in the app

**Summary of the fix**

1. **Loading** (`data/ocr/paddle/paddle_ocr_engine.dart`):
   - Every read waits on one shared load, so reads that start together don't
     load twice or see a half-loaded reader.
   - A failed load is forgotten, so the next read loads again and works once
     the cause, such as low storage, is gone. No app restart is needed.
   - Anything that loaded before the failure is closed.
   - The detector, recognizer and decoder are kept as one value, so they can't
     get out of step.
   - The unused `dispose()` was removed.
2. **New issue `ScanIssue.readerUnavailable`.** It means "idlens couldn't start
   its text reader on this phone", and the status is `failed`. The photos are
   fine, so the app should offer to read the same files again, not a retake.
   The real error stays in `diagnostics['error']` for logs. Any other error
   during reading is still `processingFailed`.
3. **Passport MRZ reader.** It used to ignore any Paddle error and move on. It
   now passes this one through, so a scan doesn't try to load the reader again
   several times.
4. **Built-in flow.** The dialog says "The scanner couldn't start. Your photos
   are fine. Try again in a moment. If it keeps happening, free up some storage
   or restart the app." Its button says "Try again" and reads the same photos
   again.

| Situation | Before | Now |
|---|---|---|
| The load fails once | Every later scan fails until restart | That scan is `failed` with `readerUnavailable` |
| The dealer tries again after freeing space | Still fails | Works |
| Two scans start together | One may fail, and the detector loads twice | They share one load |
| Any other error while reading | `processingFailed` | `processingFailed` |

**Files changed:** `paddle_ocr_engine.dart`, `paddle_passport_mrz_reader.dart`,
`scan_runner.dart`, `domain/scan_issue.dart`, `api/scan_review.dart` (issue
order), `presentation/scan_issue_text.dart`, `identity_flow_page.dart`, the
README issue table, `doc/how_it_works.md`, `CHANGELOG.md`,
`test/scan_review_test.dart`, and the new `test/paddle_ocr_engine_test.dart`.

**How it was checked:**
- `flutter analyze` reports no issues for the package or the example.
- 77 tests pass in a scratch Dart package. They include `scan_review_test.dart`
  and 4 checks of the retry rules on a copy of the loading logic without ONNX.
- `test/paddle_ocr_engine_test.dart` uses a fake loader, but it imports OpenCV,
  so it has **not been run yet**. It needs the full `flutter test` build and
  more free disk space.
- Nothing was tried on a phone. To check on a device: fill the storage, scan,
  see the dialog, free some space, then tap "Try again" without restarting.

**Still needed in the MTN app**

- Map `ScanIssue.readerUnavailable` to a new `DocumentReadProblem.readerUnavailable`.
- Show its own dialog:

  | | English | Arabic |
  |---|---|---|
  | Title | The scanner couldn't start | تعذّر تشغيل الماسح |
  | Message | Your photos are fine. Try again in a moment. If it keeps happening, free up some storage on the phone or restart the app, or enter the details manually. | صورك سليمة. حاول مرة أخرى بعد قليل. إذا تكرر ذلك، أفرغ بعض المساحة على الهاتف أو أعد تشغيل التطبيق، أو أدخل البيانات يدوياً. |
  | Button 1 | Try again | حاول مرة أخرى |
  | Button 2 | Enter manually | أدخل البيانات يدوياً |

- "Try again" reads the same photos again without opening the camera. The
  dialog doesn't show the photo-example picture.
- The Arabic text needs a check by a native speaker.
- Keep the read queue, because reads are heavy, but update its comment. Remove
  the "keep reads behind the service queue" entry from `docs/GOTCHAS.md`.
- Close B20 in `SIM_REGISTRATION_OCR_BUGS.md`. The retry button also covers
  part of B24.

**What happens**

In `data/ocr/paddle/paddle_ocr_engine.dart`, `_ensureLoaded` returns early if `_det` is set, and assigns `_det`, `_rec` and `_decoder` one at a time. Two things can go wrong:

- **Failed load:** if `_rec` or the dictionary fails after `_det` loads, later calls skip loading and reach `_rec!` or `_decoder!` while they're null.
- **Overlapping first reads:** a second read can see `_det` set while `_rec` is still loading.

**Why it matters**

One temporary failure, such as low memory, makes every scan fail until the app restarts. The dealer only sees that reading failed. The app runs one read at a time just to avoid the overlap.

**Original suggestion (used with changes, see the summary above)**

Keep one shared load, and clear it on failure so the next read can retry:

```dart
Future<void>? _loading;

Future<void> _ensureLoaded() {
  return _loading ??= _load().catchError((Object error) {
    _loading = null; // The next read tries again.
    throw error;
  });
}

Future<void> _load() async {
  final ort = OnnxRuntime();
  final det = await ort.createSessionFromAsset(_detAsset);
  try {
    final rec = await ort.createSessionFromAsset(_recAsset);
    final dict = await rootBundle.loadString(_dictAsset);
    _det = det;
    _rec = rec;
    _decoder = CtcDecoder([/* Built from dict, as today. */]);
  } catch (_) {
    await det.close();
    rethrow;
  }
}
```

`close()` must also clear `_loading`. If `rec` can load and the dictionary still fail, close `rec` too.

**Expected behaviour after the fix**

- A failed load fails only that scan, with `ScanIssue.processingFailed`.
- The next scan tries to load again, and works if the cause has passed.
- Overlapping first reads share one load, and neither sees a half-loaded model.

**What to change in the app after the fix**

- Upgrade to 0.1.4.
- Remove the "keep reads behind the service queue" entry from [`docs/GOTCHAS.md`](../GOTCHAS.md).
- Keep the queue, because reads are heavy, but update its comment in `document_reader_service.dart`. The timeout in B6 is still needed.
- Close [B20](SIM_REGISTRATION_OCR_BUGS.md#b20-a-model-that-fails-to-load-breaks-every-later-scan).

---

## I3. Image work runs on the UI isolate

- [x] Fixed in idlens (2026-11-03, not committed or released), without
      measuring first: the fix is cheap and gives the same results
- [ ] Measured on a low-end phone
- [ ] Adopted in the app

**Summary of the fix**

Reading the code showed that the model runs were never the problem:
`flutter_onnxruntime` already runs inference on a background native task queue
on Android and iOS. Three other kinds of work ran on the calling isolate:

| Work | Before | Now |
|---|---|---|
| OpenCV: decoding the full photo (up to 4 times a scan), resize, colour conversion, CLAHE, blur, edges, contours, page warp | Synchronous calls | `*Async` calls, which run on OpenCV's native threads |
| Recognizer output, about 150,000 values per text line (749 classes × up to 200 steps), read twice for lines with digits | Copied value by value into `List<List<double>>` | Read as the `Float32List` the plugin returns; `CtcDecoder.greedy` takes the flat list |
| Detector input (about 1.7 million pixel values) and the text-box search on its output map | Dart loops on the calling isolate | Run on a short-lived worker isolate (`Isolate.run`) |

- The arithmetic is the same, so results don't change for the same photo. The
  `process*` and `scan*` signatures don't change.
- The worker closure is made in a static helper, so it never holds a native
  OpenCV `Mat` and can always be sent to the worker.
- The per-line pixel loop for the recognizer (48 × up to 1,600 pixels) stays on
  the calling isolate. It is short, and the model run between lines lets frames
  draw.

**Files changed:** `paddle_ocr_engine.dart`, `ctc_decoder.dart`,
`image/image_ops.dart`, `image/image_quality_checker.dart`,
`image/frame_edge_checker.dart`, `passport/paddle_passport_mrz_reader.dart`,
`passport/paddle_passport_scan_service.dart`, `scan_runner.dart`,
`test/paddle_decoding_test.dart`, `CHANGELOG.md`.

**How it was checked:**
- `flutter analyze` reports no issues for the package or the example.
- In a scratch Dart package (`flutter test` can't build OpenCV on this Mac):
  the decoding tests pass; the new decoder gives bit-identical text and
  confidence to the old one on 50 random 749-class outputs; and text boxes
  computed on a worker isolate equal boxes computed in place.
- Nothing was run on a phone. The OpenCV `*Async` calls and the worker isolate
  run only on a device. Check there that scans still read the same values and
  that the "Reading document..." spinner keeps moving on a low-end Android
  phone.

**What happens**

idlens has no `compute` or `Isolate` calls. It runs synchronous OpenCV calls such as `cv.imread`, `cv.resize` and `cv.cvtColor` in `data/ocr/paddle/paddle_ocr_engine.dart`, `data/image/image_ops.dart` and `data/ocr/paddle/passport/paddle_passport_mrz_reader.dart`. These calls run on the isolate that called them, which in the app is the UI isolate.

**Why it matters**

The "Reading document..." spinner and the rest of the UI may stop during a read, especially on low-end phones. This hasn't been measured.

**Recommended fix**

1. Measure dropped frames and scan time on a low-end Android phone. Don't change anything if it's acceptable.
2. If it freezes, move the image work to a background isolate or use `opencv_dart`'s async calls where they exist. Check first whether `flutter_onnxruntime` calls must stay on the main isolate, because that decides how far the work can move.

**Expected behaviour after the fix**

- The spinner keeps moving, and the page stays responsive during a read.
- Results don't change for the same photo.
- `process*` method signatures don't change.

**What to change in the app after the fix**

- Upgrade idlens. No code change should be needed.
- Add scan time and freezing to the [`docs/testing/DEVICE_SMOKE.md`](../testing/DEVICE_SMOKE.md) checks, using a low-end phone.
- Set the B6 timeout from the measured scan times.
- Close [B19](SIM_REGISTRATION_OCR_BUGS.md#b19-reading-may-freeze-the-ui).

---

## I4. Some certificate values have no confidence score

- [x] Fixed in idlens by removing `confidence` (2026-11-03, not committed or
      released)
- [ ] Adopted in the app

**Summary of the fix**

`CivilRegistryResult.confidence` was removed instead of fixed. While reading the
code, a second problem turned up: ML Kit never gave idlens a score, so every
value it read showed 1.0 (100%). Certificate numbers often come from ML Kit,
because Paddle drops digits next to Arabic text, so the app's 60% limit let
badly read numbers through. ML Kit gives a line score on Android but none on
iOS, so no honest score exists for those values on iPhones.

The score was also only on certificates, idlens never used it, and it competed
with `fieldsToCheck` from [I1](#i1-a-missing-field-is-treated-as-a-value-to-review)
as a second way to say "this value may be wrong". Removing it fixes I4 and the
fake 100%, and keeps the result simple. If the accuracy test shows that low
scores predict wrong values, idlens can use the score internally and list those
fields in `fieldsToCheck` (the `lowConfidence` rule decided in I1).

| Before | Now |
|---|---|
| `CivilRegistryResult.confidence`, missing for values found without their label | Removed |
| ML Kit values scored 1.0 | No score anywhere |
| `confidence` in the certificate's `toJson()` | Removed |

The unused `PassportLine.confidence` was removed too. Paddle still drops
lines below its own score limit while reading, as before.

**Files changed:** `api/civil_registry_result.dart`, `scan_runner.dart`, the
certificate parser, reading, scan service and text reader,
`passport/passport_line.dart`, the Paddle passport text and MRZ readers,
`test/scan_outcome_test.dart`, the README and `CHANGELOG.md`.

**How it was checked:** `flutter analyze` reports no issues for the package or
the example. 60 tests in the certificate parser, label, result and review test
files pass in a scratch Dart package. Values read are unchanged: only the
score was removed.

**Still needed in the MTN app**

- Remove `trusted` and the 60% limit from `fromCertificate`. Fill every value
  idlens returns, and use `fieldsToCheck` as for ID cards and passports.
- Close [B13](SIM_REGISTRATION_OCR_BUGS.md#b13-some-good-certificate-values-are-thrown-away).

**What happens**

`CivilRegistryResult.confidence` is documented as the score for each field, but only values found through their label get one. These values appear in `fields` with no score:

- A national number found by `_unlabelledNumber`.
- A date found by `_dateFallback`.
- A value found by the row re-read in `civil_registry_scan_service.dart`, which updates `fields` but keeps `page.confidence`.

**Why it matters**

The app treats a missing score as 0 and drops the value. So the extra work idlens does to recover these values is thrown away, and the dealer has to type them.

**Original suggestion (not used, see the summary above)**

Record the score of the line each value came from, in all three paths. Add to the parser tests that every non-null field has a score, except values that are copied from elsewhere, if any.

**Expected behaviour after the fix**

- Every non-null value in `fields` has an entry in `confidence`.
- A recovered value with a high score fills the form.
- A recovered value with a low score is still left out by the app's 60% limit.

**What to change in the app after the fix**

- Upgrade to 0.1.4.
- Keep `trusted` in `fromCertificate` as it is, because it will now work as intended.
- Add a service test for a recovered value above and below the limit.
- Review the 60% limit against the real accuracy test.
- Close [B13](SIM_REGISTRATION_OCR_BUGS.md#b13-some-good-certificate-values-are-thrown-away).

---

## I5. A cut-off document is accepted

- [x] Fixed in idlens (2026-11-03, not committed or released). The limits
      still need checking on real photos (step 1 below).
- [ ] Adopted in the app

**Summary of the fix**

The decision: a cut-off document gives `documentNotInFrame` and `failed`, as
before. What changed is that idlens now notices it.

- **A margin around every photo.** The built-in camera used to crop the ID
  front and the certificate exactly to the box, so nothing in the photo could
  show a cut. It now crops every document 6% wider than the box on each side
  (`CardFrame.captureMargin`), so a well-placed document has background all
  around it. The box is a little smaller (86% of the preview instead of 92%,
  and an A4 box is limited by height) so the margin always fits.
- **Three checks, strongest first** (`DocumentFraming`, measured by
  `DocumentFrameChecker`):
  1. **Outline:** the document's 4 corners, which must be at least 30% of
     the photo and have the document's shape. A corner at an edge means cut
     off.
  2. **Bright area** against the background, when no outline is found: it
     runs past an edge when it lies along that edge for at least half its own
     side. A hand holding the card touches the edge over a much shorter
     stretch, so it doesn't count.
  3. **Text at the edges**, when neither can tell (a light table, or a photo
     cropped with no margin). **One edge is now enough**, instead of two.
- **The ID back is checked** like every other photo.
- **The certificate is never flattened when its outline reaches the photo's
  edge**, because flattening would hide the cut.
- The "too far" coverage now comes from the same measurement. Because of the
  margin, a well-placed card covers about 80% of the photo instead of 100%, so
  the limit was moved from 0.6 to 0.42 (`ImageQuality.minDocumentCoverage`).
  A device test showed why: a card filling 80–90% of the box was rejected
  with the old limit. Now a card at 80% of the box or more is accepted, and one
  at 60% (too far, also seen on a device) is still rejected. This helps
  [I8](#i8-a-document-far-from-the-camera-can-be-accepted) but doesn't close it.
- **A cut MRZ fails the scan** (added after a device test, 2026-11-03). A
  photo of an ID back cut on the right lost the last character of every MRZ
  line, so the name `MERGHANI` was read as `MERGHAN`. The MRZ reader pads a
  short line with `<`, and a name has no check digit, so nothing flagged it.
  `MrzParser.isCut` now looks at the lines as read: a check-digit line that
  doesn't end in its digit, a name line that doesn't end in `<`, or a first
  line that doesn't start with its document code means the photo cut the MRZ.
  That gives `documentNotInFrame` even when the photo checks can't tell. A `<`
  dropped in the middle of a line is still repaired as before.
- `diagnostics['framing']` (and `frontFraming` for an ID card) says which check
  decided and which edges were cut, with the measurements, so real photos can
  be compared.

Checked on drawn test photos with the same OpenCV steps: a card moved 10-16%
left, right or down is caught on a dark or mid-grey table, a card held by a
hand and a card 3% off-centre are accepted, and a card at 60% of the box gets a
coverage of 0.47 (too far). On a light table, the outline is still found for a
well-placed card. A cut-off card on a light table falls back to the text check.

Tests: `test/document_framing_test.dart` (the rules), `test/card_frame_test.dart`
(the margin always fits), `test/mrz_parser_test.dart` (cut MRZ lines, with the
device case), and `test/image_quality_test.dart`. Not tried on a
phone yet.

**Still to do:** take good, cut-off and far photos of each document on light
and dark tables, read `diagnostics['framing']`, and adjust the limits in
`DocumentFraming` if needed.

**The original report**

**What happens**

Seen on a device: a photo with part of the document outside it is accepted, sometimes as `verified`, sometimes with values to review. It happens on every document:

- **ID back:** the card was moved a little to one side, so one edge was cut off. The scan was accepted.
- **ID front:** the same, moved a little to the left. The scan was accepted.
- **Passport and certificate:** the same.

idlens has two framing checks, and neither one catches a document cut off on one side:

- **Cut-off check** (`PassportFrameCheck.touchedSides`): reports `documentNotInFrame` only when printed text runs to **2 or more** edges of the photo (`ScanIssueResolver.cutOffSides = 2`). A document moved to one side is cut on **one** edge, so it always passes.
- **The ID back has no cut-off check.** `PaddlePassportScanService` and `checkPhoto` (ID front, certificate) measure the edges, but `IdentityScanService` never sets `frameTouchedSides` for the ID back, so it's always 0.
- **Distance check** (`ImageQualityChecker._coverage`): a cut-off document still fills most of the photo, so it passes. This check also misses documents that are too far away; see [I8](#i8-a-document-far-from-the-camera-can-be-accepted).

**Why it matters**

A cut-off photo can lose values, or give wrong ones from a half-read line, and it's a poor image for the backend's KYC record. The dealer gets no warning, so they don't retake it.

**Also wrong today: when a framing problem is found, the scan fails**

When `documentNotInFrame` is reported, `ScanReview.statusFor` returns `failed`, even when the MRZ was read and passes every check digit. The built-in flow warns about a cut-off ID front before reading, and the dealer can choose to continue. The result is still `failed`, so continuing does nothing. Once the checks above catch more photos, this decides what the dealer sees.

**Decision needed before fixing**

When idlens finds a cut-off or far document, should the scan return:

- **`failed`:** the dealer must retake, even when the MRZ was read correctly.
- **`needsReview`, with the issue kept:** the values are kept, and the app shows a warning with a retake button.

**Recommended fix**

1. Collect real photos first: good, cut off on one side, and far away, for each document type, on light and dark backgrounds.
2. Find the document itself, not only its text. Use the document's outline, as `cropPage` already does for the certificate. If its 4 corners aren't all inside the photo, it's cut off. For the ID back and the passport, the MRZ line width is a second measure.
3. Run the cut-off check on the ID back too.
4. Set the limits from the real photos, and add them to `test/image_quality_test.dart`.
5. Apply the decision above in `ScanReview.statusFor`.

**Expected behaviour after the fix**

| Photo | Result |
|---|---|
| Document fully inside the box | No framing problem |
| Cut off on one side, any document | `documentNotInFrame` |
| Cut off on one side, ID back with a valid MRZ | `documentNotInFrame`, status as decided above |
| Too far away | Covered by [I8](#i8-a-document-far-from-the-camera-can-be-accepted) |

**What to change in the app after the fix**

- Upgrade idlens.
- Make sure the `documentNotInFrame` dialog offers a retake for every document type.
- The app uses its own camera ([B27](SIM_REGISTRATION_OCR_BUGS.md#b27-the-apps-camera-skips-steps-from-idlens-camera)). Crop the photo 6% wider than the box on every side, as idlens' camera now does, and make the box smaller (86% of the preview) so that margin fits. Without the margin, only the text check works.
- Decide [D3](SIM_REGISTRATION_OCR_BUGS.md#part-3-decisions-needed) with the decision above, because together they settle B8.
- Add cut-off photos of each document to [`docs/testing/DEVICE_SMOKE.md`](../testing/DEVICE_SMOKE.md), and update the service tests.

---

## I6. Issues don't say which side of the ID caused them

- [x] Fixed in idlens (2026-11-03, committed in d03adbc, not released)
- [ ] Adopted in the app

**Summary of the fix**

The recommended `issuesBySide` map wasn't used: since I1 a result has one
`issue`, not a list, so a map of lists would bring the complexity back. Every
result has a new `issueSides` list instead: the pages to retake because of
`issue`, in document order. idlens already checked the ID front and back
apart, but `ScanReview.worse` kept only the worse issue and dropped the side.
`ScanReview.issueSides` now keeps it.

| Case | `issueSides` |
|---|---|
| Blurry back, good front | `[back]` |
| Front cut off, good back | `[front]` |
| Both photos have a problem | `[front, back]` |
| No MRZ read, no photo check failed | `[back]` (passport `[dataPage]`, certificate `[page]`) |
| `wrongDocument` | Every page |
| No issue, `processingFailed`, `readerUnavailable` | Empty |

It's a list rather than one side, because both photos can be bad at once, and
naming only the worse one would make the dealer retake twice.

The built-in flow now names the side in the dialog after a scan ("Back: Image
not clear"). It also fixes a gap found on the way: when the dealer chose "Use
anyway" for a blurry front, a blurry back was hidden because it was the same
issue.

**Files changed:** `api/scan_outcome.dart` (field, `toJson`), the three result
classes, `api/scan_review.dart` (`issueSides`), `scan_runner.dart`,
`presentation/scan_issue_text.dart`, `presentation/pages/identity_flow_page.dart`,
the example app, the README, `doc/how_it_works.md` and `CHANGELOG.md`.

**How it was checked:** `flutter analyze` reports no issues for the package or
the example. `scan_review_test.dart` (7 new tests) and `scan_outcome_test.dart`
pass, 33 tests, run in a scratch Dart package. Nothing was tried on a device.

**Still needed in the MTN app**

- Pass `result.issueSides` through `ScannedDocumentData`.
- Make `_retake` in `sim_scan_form.dart` open the camera only for the sides in
  `issueSides`. When it's empty, nothing is wrong with the photos.
- Close B26 in `SIM_REGISTRATION_OCR_BUGS.md`.

**What happens**

`issues` is a flat list of `ScanIssue`, so an unclear or out-of-frame result doesn't say whether the front or back caused it.

**Why it matters**

The app has to ask the dealer to retake both sides, even if one was fine.

**Recommended fix**

Add a way to look up the side without changing `issues`:

```dart
final Map<DocumentSide, List<ScanIssue>> issuesBySide;
```

Fill it from the existing front and back checks.

**Expected behaviour after the fix**

- A blurry back on an ID gives `issuesBySide[DocumentSide.back]` containing `imageNotClear`.
- `issues` still lists every issue, so existing code keeps working.
- A passport or certificate reports its only page.

**What to change in the app after the fix**

- Upgrade to 0.2.0.
- Pass `result.issueSides` through `ScannedDocumentData`.
- Make `_retake` in [`sim_scan_form.dart`](../../lib/features/sim/presentation/widgets/sim_scan_form.dart#L441) reopen the camera for only the affected side.
- Close [B26](SIM_REGISTRATION_OCR_BUGS.md#b26-retaking-an-unclear-id-asks-for-both-sides).

---

## I7. A running read can't be cancelled

- [x] Fixed in idlens with a time limit instead of a cancel token (2026-11-03,
      committed in 24fdd47, not released)
- [ ] Adopted in the app

**Summary of the fix**

The cancel token suggested below wasn't used. Read times can't be measured
yet, and a token makes every app manage cancelling. Instead every method takes
an optional time limit, and the app decides the value:

| Method | Where the limit goes |
|---|---|
| `processIdCard`, `processPassport`, `processCivilRegistry` | `timeout:` parameter |
| `scanIdCard`, `scanPassport`, `scanCivilRegistry` | `timeout` in the options |

- `null` (the default) means no limit, so nothing changes for an app that
  doesn't pass one. A zero or negative value throws `ArgumentError`.
- When the limit passes, the result returns at once: `failed`, with the new
  `ScanIssue.timedOut`, the images, and empty `issueSides` (the photos are
  fine). Nothing is thrown, so the app handles it like any other issue.
  `diagnostics['timeoutMs']` holds the limit.
- The result returns on time even when a native call is stuck.
- The work left behind stops too. The whole read runs under one deadline
  (`domain/scan_deadline.dart`), which the Paddle reader checks before each
  text line, and the runner between stages. A step already running inside the
  native reader (one detector or recognizer run, or one ML Kit call) still
  finishes first. The passport MRZ reader passes the timeout through instead
  of trying the next band.
- The built-in flow says "Reading took too long. Your photos are fine. Try
  again. If it keeps happening, close other apps or restart the phone.", with
  a "Try again" button that reads the same photos again.

**Files changed:** new `domain/scan_deadline.dart`, `domain/scan_issue.dart`,
`api/scan_review.dart` (issue order, `issueSides`), `api/scan_options.dart`,
`idlens_scanner.dart`, `scan_runner.dart`, `paddle_ocr_engine.dart`,
`passport/paddle_passport_mrz_reader.dart`, `presentation/scan_issue_text.dart`,
`presentation/pages/identity_flow_page.dart`, the README (new "Time limit"
section), `doc/how_it_works.md` and `CHANGELOG.md`.

**How it was checked:** `flutter analyze` reports no issues for the package or
the example. 39 tests pass in a scratch Dart package, including the new
`test/scan_deadline_test.dart` (a stuck read returns on time, a read past its
limit stops at its next check, no limit runs to the end) and new
`scan_review_test.dart` cases. Nothing was tried on a phone.

**Still needed in the MTN app**

- Pass a `timeout` to `processIdCard`, `processPassport` and
  `processCivilRegistry`. Start generous (for example 30 seconds), because a
  limit that's too short makes every scan fail on a slow phone.
- On `ScanIssue.timedOut`, show a toast or dialog ("Reading took too long")
  and offer to read the same photos again or enter the details manually. Don't
  ask for a retake: the photos are fine.
- Log `diagnostics['scanMs']` from real scans, and lower the limit once real
  read times are known.
- This replaces the app's own timeout in B6. Close B18 and B6 in
  `SIM_REGISTRATION_OCR_BUGS.md` after checking on a phone.

**The original report**

**What happens**

`processIdCard`, `processPassport` and `processCivilRegistry` have no cancel option. Once started, a read runs to the end.

**Why it matters**

If the dealer retakes a photo during a read, the old read keeps using CPU and memory, and the new read waits for it.

**Recommended fix**

First, have the app skip queued reads that are already stale, which needs no idlens change. If retakes are still slow on a low-end phone, add an optional token that's checked between stages:

```dart
Future<IdCardResult> processIdCard({
  required File front,
  required File back,
  ScanCancelToken? cancelToken,
});
```

**Expected behaviour after the fix**

- A cancelled read stops at the next stage, such as between the front and back. A native call already running finishes first.
- It returns a clear cancelled result, which the app ignores.
- A new read starts soon after the cancel.

**What to change in the app after the fix**

- Pass the token from `read` in `document_reader_service.dart`.
- Call `cancel` from `_cancelRead` in the cubit.
- Close [B18](SIM_REGISTRATION_OCR_BUGS.md#b18-old-reads-still-run-after-being-cancelled).

---

## I8. A document far from the camera can be accepted

- [ ] Coverage values collected from real far photos
- [x] Fixed in idlens (2026-11-03, committed in 02b918f, not released)
- [ ] Re-tested in the app

**Summary of the fix**

I5 moved the "too far" check into `DocumentFraming` and set the limit to
0.42, which works on a dark table. It still measured the brightest area, so
the three problems below stayed. `DocumentFraming.coverage` now measures, in
this order:

1. **The document's outline**, when its 4 corners are found with the
   document's shape. This is the document's own size, so a light table or a
   bright object nearby doesn't change it. The outline search now keeps shapes
   down to 15% of the photo (`minFarOutlineShare`), because a far card at 60%
   of the box is only about 0.24–0.29 of the photo and was skipped before. The
   cut-off check still needs 30%, as in I5.
2. **The bright area's box**, when there's no outline, except when that area
   is the background (over 92% of the photo, or along 3 or 4 edges).
3. **Not judged far** when neither can tell, as before.

| Photo | Before | Now |
|---|---|---|
| Far card, dark table | `documentNotInFrame` | `documentNotInFrame` |
| Far card, light table, outline found | Accepted | `documentNotInFrame` |
| Far card next to a bright object, outline found | Accepted | `documentNotInFrame` |
| Far card, light table, no outline found | Accepted | Still accepted |

`diagnostics['framing']['coverage']` (and `frontFraming` for an ID front)
gives `share` and `from` (`outline`, `region` or `none`), so real photos show
which measure decided.

**Not done:** the MRZ line width suggested below. The ID back's MRZ is read by
`MrzReader` through `OcrEngine`, which returns text without positions, and
that classic path stays unchanged. The outline covers the same cases when it's
found.

**How it was checked:** `flutter analyze` reports no issues for the package or
the example. `test/document_framing_test.dart` (11 new coverage tests: far
card, light table, bright object, fallbacks) and `test/image_quality_test.dart`
pass, 48 tests, run in a scratch Dart package. Not tried on a phone.

**Still to do:** photograph far and well-placed documents on light and dark
tables, read `diagnostics['framing']['coverage']`, and check the 0.42 limit
and the 15% outline limit. A far document on a light table whose outline
isn't found is still accepted.

**Still needed in the MTN app**

- Upgrade idlens. No code change: `documentNotInFrame` already opens the
  retake dialog.
- The app's camera must keep the 6% margin from I5, or a far document's
  outline and the limit won't match.
- Add far photos on light and dark tables to `docs/testing/DEVICE_SMOKE.md`,
  for A4 pages, ID backs and passports.

**The original report** (written for 0.1.3; the limit, the box size and the
file names have changed since I5)

**What happens**

Seen on a device: A4 pages and ID backs photographed from far away are sometimes accepted.

`ImageQualityChecker._coverage` in `data/image/image_quality_checker.dart` decides whether a document is too far. It finds the largest bright region in the photo and returns the share of the frame taken by that region's bounding box. `ImageQuality.problem` reports `documentNotInFrame` below `minDocumentCoverage = 0.6`.

That measures the bright region, not the document, so it can pass a far document:

- **Light background:** on a light desk or wall, the background can be the largest bright region, or join the document into one region.
- **No clear region:** it returns 1 by design, which means "not far".
- **Bounding box:** one bright object near a corner makes the box much larger than the document.

The `ImageQuality` comments also call its limits provisional, tuned from one bad photo. A separate check, `PassportFrameCheck`, only detects text cut off at the edges, not a document that's too small.

**The app's box isn't the cause**

The app's box uses the same numbers as idlens' camera:

| Value | idlens | App |
|---|---|---|
| Box width | 92% of the view | 92% of the view |
| ID shape | 85.6 / 54 | 85.6 / 54 |
| Passport shape | 125 / 88 | 125 / 88 |
| A4 shape | 210 / 297 | 210 / 297 |
| MRZ guide, ID | 0.34 | 0.34 |
| MRZ guide, passport | 0.25 | 0.25 |
| MRZ guide inset | 8 | 8 |
| Extra MRZ crop | 6% | 6% |

The rest of the camera differs: see [B27](SIM_REGISTRATION_OCR_BUGS.md#b27-the-apps-camera-skips-steps-from-idlens-camera). None of those differences changes how `_coverage` measures a photo. Scanning from far away through idlens' own `scan*` screens would confirm this.

**Why it matters**

A small document means less detail for reading and a poor image for the backend's KYC record. An ID back with a valid MRZ is still safe for data, because check digits prove the values. A certificate has no check digits, so a far photo risks misread values with nothing to catch them except the confidence limit.

**Recommended fix**

1. Collect values first. `documentCoverage` is already in the result's `diagnostics`, so compare good and far photos on light and dark backgrounds.
2. Measure the document from what was read, not from brightness:
   - **ID back and passport:** use the MRZ line width against the photo width. MRZ lines run almost the full width of the document, so this tracks distance directly.
   - **Certificate and ID front:** use the bounding box of the recognised text lines against the photo size, and the page outline from `cropPage` when it's found.
3. Keep `_coverage` only as a backup, for when no text was read.
4. Set the limits from those real photos, and add them to `test/image_quality_test.dart`.

**Expected behaviour after the fix**

| Photo | Result |
|---|---|
| Document fills the box, any background | No framing problem |
| Far document on a dark background | `documentNotInFrame` |
| Far document on a light background | `documentNotInFrame` |
| Far ID back with an MRZ that can still be read | `documentNotInFrame`, with values still returned |
| Plain background and no text read | Not reported as far, but reading finds nothing |

**What to change in the app after the fix**

- Upgrade to 0.1.4. No code change should be needed, because `documentNotInFrame` already opens the retake dialog.
- Add far photos on light and dark backgrounds to [`docs/testing/DEVICE_SMOKE.md`](../testing/DEVICE_SMOKE.md), for A4 pages, ID backs and passports.

---

## I9. `processCivilRegistry` doesn't flatten the page

- [x] Fixed in idlens (2026-11-03, committed in a533391, not released)
- [ ] Adopted in the app

**Summary of the fix**

- `processCivilRegistry` runs `ImageOps.cropPage` on the photo and reads the
  flat page. With no outline, or if straightening fails, it reads the photo
  as it is.
- The step lives in `ScanRunner.civilRegistry` (`flatten: true`), so the time
  limit from I7 covers it. The built-in flow doesn't pass it, because its
  camera has already straightened the page.
- The clarity and framing checks still look at the original photo, where the
  page edges show. Only the reading uses the flat copy.
- The flat copy is a temporary file and is deleted after the read. The app's
  file isn't changed and is still the result's image.
- `diagnostics['pageFlattened']` says whether the page was straightened.

**What happens**

idlens' own camera flattens a certificate to a straight A4 sheet with `ImageOps.cropPage` when it finds the page outline. That only happens in `presentation/widgets/card_camera_page.dart`. `processCivilRegistry`, which the app uses, reads the photo as it is.

**Why it matters**

The two flows read different images, so accuracy from idlens' own screens doesn't tell us about the app. A tilted or far page in the app gets no correction.

**Recommended fix**

Run the same flattening inside `processCivilRegistry`, and fall back to the plain photo when no outline is found. Clean up its temporary file afterwards.

**Expected behaviour after the fix**

- A tilted page is straightened before reading in both flows.
- A photo with no clear outline reads as it does today.
- The file passed in by the app isn't changed.

**What to change in the app after the fix**

- Upgrade to 0.1.4.
- Compare certificate accuracy before and after with the same real photos.
- Decide whether the image uploaded to the backend should be the flattened one. It isn't today, and this fix alone won't change that.

---

## I10. Apps have to build their own camera

- [ ] Added to idlens
- [ ] Arabic reviewed by a native speaker
- [ ] Adopted in the app

**Decision:** agreed on 2026-11-02. idlens owns the camera through a new capture API, and the camera supports Arabic.

**What happens**

idlens has two ways in. `scan*` opens the full flow, whose screens are in English only. `process*` only reads files. An app that needs its own language or flow must therefore write its own camera and copy idlens' numbers.

**Why it matters**

The MTN app did this, and its camera has already drifted from idlens' ([B27](SIM_REGISTRATION_OCR_BUGS.md#b27-the-apps-camera-skips-steps-from-idlens-camera)). Framing, crop, focus and flattening all affect how well idlens reads, so they should live with the reader.

**Recommended fix**

Add a capture method that opens the camera for one page and returns the finished photo. Don't add camera options to `process*`, because those methods never open a camera.

```dart
/// Returns the cropped photo, or null if the user left the camera.
/// Throws ScanException when the camera can't be used.
Future<File?> captureDocument(
  BuildContext context, {
  required DocumentKind kind,
  required DocumentSide side,
  CaptureOptions options = const CaptureOptions(),
});
```

Build it from the existing `card_camera_page.dart`, then make these changes:

- Replace its hardcoded English text with built-in English and Arabic, picked with `Localizations.localeOf(context)`, so that idlens doesn't need `easy_localization`.
- Let an app replace any text through `CaptureOptions(labels: ...)`, which also covers other languages. An app passes only the texts it wants to change.
- Support right-to-left layouts for the controls and instructions. The box and MRZ guide don't flip, because the document doesn't, and "MRZ" stays untranslated.
- Take the text style from the app's theme, so that each app keeps its own fonts.
- Shrink the box on short screens, as the app's `documentFrameRect` does. `CardFrame.centered` doesn't do this today.

Keep the options few, so that every app sends idlens the photo it's tuned for:

| Option | Fixed in idlens |
|---|---|
| Text and translations | Box size and shape |
| Colours and style | MRZ guide and crop margin |
| Whether flash is offered | Resolution, focus and orientation |

Keep `process*` as it is, so an app that doesn't want this camera can still pass its own files. Move the guide, crop and frame tests from the app (`test/features/sim/document_frame_test.dart`) to idlens with the code they cover.

**Expected behaviour after the fix**

- The photo is cropped to the box, with the same steps in `scan*` and `captureDocument`.
- A certificate is flattened as it is in `scan*` today, so the app uploads the flattened page too. Check that the backend accepts this.
- The uncropped photo is deleted after cropping, as idlens already does. The returned photo belongs to the app, which deletes it.
- The camera shuts down when the method returns, so nothing keeps running during the app's review.
- The app returning from the background restores the preview.
- If permission is denied or the camera fails, the method throws `ScanException` instead of leaving the user on an error screen.
- The whole camera image is shown with black bars where needed, so the box lines up with the real photo.
- An app in Arabic gets an Arabic, right-to-left camera with no setup, and any other language falls back to English.
- Text passed in `labels` always replaces the built-in text.
- `ScanException` stays as codes, so each app writes its own error message.
- The camera works in Arabic on a short screen, with the flash and close buttons on the correct sides.

**Known costs**

- The camera reopens between the ID's front and back, which adds a short delay.
- The thumbnail of the front on the back step goes away, unless it's added as an option later.
- Each camera change needs an idlens release. A local path dependency keeps this easy during development.

**What to change in the app after the fix**

- Replace the camera in [`document_scanner_camera_page.dart`](../../lib/features/sim/presentation/widgets/document_scanner_camera_page.dart) with `captureDocument`, and delete what's left of that file.
- Keep `DocumentCaptureSession`, [`document_photo_review.dart`](../../lib/features/sim/presentation/widgets/document_photo_review.dart), the problem dialogs and the translations.
- Pass the app's own camera text from `en.json` and `ar.json` through `labels`, so that all its copy stays in one place (`ai/rules.md` §9).
- Show a translated message and one call to action for settings when `ScanException` is thrown.
- Remove the app's `DocumentType` enum, and use `DocumentKind` and `DocumentSide` in place of its overlapping types (helps P6).
- Delete crops in the app when they leave the form or the flow ends.
- Update `docs/GOTCHAS.md`: remove the note about copying idlens' numbers, and note that the app uses `captureDocument` and `process*`, not `scan*`.
- Update rows 4a–4d in [`docs/testing/DEVICE_SMOKE.md`](../testing/DEVICE_SMOKE.md).
- Run the 20–30 document accuracy test after this, because the camera affects the results.
- Close [B21](SIM_REGISTRATION_OCR_BUGS.md#b21-the-crop-may-not-match-the-frame-the-dealer-sees), [B22](SIM_REGISTRATION_OCR_BUGS.md#b22-photos-arent-size-limited), [B23](SIM_REGISTRATION_OCR_BUGS.md#b23-the-camera-isnt-managed-properly) and [B27](SIM_REGISTRATION_OCR_BUGS.md#b27-the-apps-camera-skips-steps-from-idlens-camera) after checking them on a phone.

---

## I11. `scan*` has its own path and no clear role

- [ ] `scan*` uses `captureDocument`
- [ ] `options` removed from `process*`
- [ ] README updated
- [ ] Decided whether to keep `scan*` long term

**Decision:** agreed on 2026-11-02. Keep `scan*` as the English quick start, rebuild it on the new camera, and don't add features to it.

**What happens**

- `scan*` opens its own flow of tips, camera and review, with hardcoded English text. The MTN app can't use it.
- Its flow does work that `process*` skips, such as flattening a certificate (I9), so the two paths read different photos.
- `showTips` and `requireValidMrz` are accepted by `process*`, but documented as ignored there.

**Why it matters**

Two paths can give different accuracy for the same document, and options that do nothing mislead whoever calls them. Without a clear role, every new feature also has to be considered for `scan*`.

**Recommended fix**

1. **In 0.1.4:** make `scan*` call `captureDocument` for each photo, then the same code as `process*`. Have `scan*` force English on the camera until its whole flow is translated, so an Arabic phone doesn't show an Arabic camera inside English tips and dialogs.
2. **In 0.2.0:** remove the `options` parameter from `process*`, so these options only appear on `scan*`.
3. **In the README:** describe each level:

| API | Who it's for |
|---|---|
| `scan*` | Apps that want everything ready-made, in English |
| `captureDocument` + `process*` | Apps with their own flow or language, like MTN |
| `process*` alone | Apps that already have the photos |

**Long-term decision**

It isn't known yet whether any other app uses idlens. If MTN turns out to be the only real user, remove `scan*` and move the flow into the `example` app as sample code. If idlens will be promoted to other apps, keep it.

**Expected behaviour after the fix**

- The same document gives the same photo processing through `scan*` and through `captureDocument` + `process*`.
- `scan*` is fully in English on every phone until its flow is translated.
- `process*` has no options that do nothing.
- Results from `scan*` work as a fair reference when testing the app, for example to confirm that I8 isn't caused by the app.

**What to change in the app after the fix**

- Nothing for the `scan*` changes, because the app doesn't call it.
- Check that the app doesn't pass `options` to `process*` when it upgrades to 0.2.0. Today's [`document_reader_service.dart`](../../lib/core/services/document_reader/document_reader_service.dart) doesn't.
- Keep the `docs/GOTCHAS.md` note that the app uses `captureDocument` and `process*`, not `scan*`.

---

## Also listed in `docs/OCR.md`

`docs/OCR.md` says a release should "fix or remove the old passport date code that has a failing test". I didn't check this, so check idlens' test suite before 0.1.4 goes out.
