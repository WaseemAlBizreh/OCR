## Unreleased

**Breaking:** the result says what to do in two members instead of reading
text.

- `issues` (a list) is now `issue`: one `ScanIssue` or `null`, always set when
  the status is `failed`.
- `warnings` is removed from the result. Fields to look at are in the new
  `fieldsToCheck`, and the English text is in `diagnostics['warnings']`, for
  logs only.
- `ScanIssue.mrzNotFound` is removed. An MRZ that can't be read gives
  `imageNotClear`, or `documentNotInFrame` when nothing is in the frame, and
  the status is still `failed`.
- `ScanIssue.mrzCheckDigitsFailed` is removed. The fields a failed check digit
  covers are listed in `fieldsToCheck`.
- `ScanOutcome.statusFor` is removed.
- `CivilRegistryResult.confidence` is removed. Values found without their
  label had no score, and values read by ML Kit always showed 1.0, so the
  scores weren't reliable. Use `fieldsToCheck` for every document instead.
- A certificate with none of its required fields read is now `failed`.
- A date that can't be right is kept as read and listed in `fieldsToCheck`. That
  covers an ID card or passport issue date on or after the expiry date, which
  used to be cleared with no warning, and a certificate birth date that isn't
  before its issue date, which used to be cleared.
- Only required fields lower the status. A certificate needs its national
  number, name and date of birth; an ID card needs its Arabic name and national
  number; a passport needs nothing beyond its MRZ. Any other field not read is
  `null` and not listed, so more scans return `verified`.
- An ID card phone number without ten digits is now `null`, instead of a
  partial number that caused `needsReview`.
- README: a guide to handling a result, with every issue and every case that
  lists a field, for each document.
- New `ScanIssue.readerUnavailable`: the text reader couldn't start on the
  phone, for example with too little free storage. The status is `failed`, the
  photos are fine, and reading them again may work. The built-in flow offers
  "Try again" for it instead of "Retake".
- Fixed: a text reader that failed to load made every later scan fail until
  the app restarted. A failed load is now retried on the next read, anything
  partly loaded is closed, and scans that start together share one load.
- Scans no longer hold up the app's frames as much. Image decoding, resizing
  and contrast work run on OpenCV's background threads; the detector's input
  and its text-box search run on a short-lived worker isolate; the
  recognizer's output is read as a float list instead of being copied value by
  value. Results are the same for the same photo, and no API changes.
- Fixed: a document cut off on one side of the photo was accepted, on every
  document. A cut-off document now gives `documentNotInFrame` (status
  `failed`). idlens looks for the document's outline first, then for its
  bright area against the background, and only then for printed text at the
  photo's edges. One edge is now enough; it used to take two. The ID back is
  now checked too.
- The built-in camera keeps a margin of background around the frame for every
  document, not only on MRZ pages, and the frame is a little smaller so that
  margin always fits. For `process...`, keep a thin strip of background
  around the document too (see the README).
- Fixed: an MRZ cut off by the photo was padded and accepted, so a name could
  lose its last letters with no warning (names have no check digit). An MRZ
  line that is missing its first or last characters now gives
  `documentNotInFrame`. `MrzData` has a new `cutOff` flag.
- The "too far" limit is now 0.42 of the photo, set for the new margin: a
  document filling at least 80% of the box is accepted, one at 60% is too
  far.
- Fixed: a document far from the camera on a light table, or next to
  something bright, was accepted, because "too far" was measured from the
  brightest area of the photo. It's now measured from the document's outline
  when one is found, and from the bright area only when it isn't the
  background. `diagnostics['framing']['coverage']` gives the share and what
  measured it.
- New `issueSides` on every result: the pages to retake because of `issue`.
  An ID card with a blurry back and a good front gives `[back]`, so the app
  can ask for that photo only. It is empty when no photo is to blame
  (`processingFailed`, `readerUnavailable`). `toJson()` includes it.
- The built-in flow names the side in its dialog after a scan ("Back: Image
  not clear"). A problem on the ID back is no longer hidden when the user
  already chose "Use anyway" for the same problem on the front.
- New optional `timeout` on every method: a parameter on `process...`, and in
  the options of `scan...`. When it passes, the result is `failed` with the
  new `ScanIssue.timedOut` and still has the images; nothing is thrown. The
  steps left are skipped, so the read doesn't keep running to the end in the
  background. `null` (the default) means no limit, as before. The built-in
  flow offers "Try again" for it.
- `diagnostics` has a new `framing` entry (and `frontFraming` for an ID card)
  saying how the framing was judged.
- `processCivilRegistry` now straightens a tilted or distant page to a flat A4
  sheet before reading it, as the built-in camera does. A photo with no clear
  page outline is read as before. The file passed in isn't changed and is
  still the result's image; `diagnostics['pageFlattened']` says whether the
  page was straightened.

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
