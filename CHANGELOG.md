## 0.4.1

Fixes for the stricter framing in 0.4.0. Every limit is now checked against a
set of real, labelled device scans, so a fix for one case can't quietly break
another. There are no API changes.

- **A good passport is no longer rejected as cut off.** In 0.4.0 the open
  booklet's facing page, running past the top and bottom of the photo, was
  taken for the data page running off the photo, so almost every passport
  scan failed. A bright area along two opposite edges is now read as
  something larger than the document, and the document counts as in frame.
  The area must still be as wide as the document on the other axis, so half
  a card running from top to bottom is still `documentNotInFrame`.
- **A document far from the camera is now rejected.** The "too far" limit
  goes from 0.42 to 0.60 of the photo. A document filling less than about
  87% of the guide box is now `documentNotInFrame`. Real far scans (76–83%
  of the box) were accepted with the old limit. Good scans filled 90% or
  more. This is stricter than 0.4.0: check it on your devices, and send
  scans that are rejected wrongly.
- **An MRZ name missing one `<` is no longer a cut MRZ.** When the name fills
  the whole line, OCR sometimes drops a `<` inside it, which leaves the line
  one character short and not ending in `<`. That was taken for a name cut
  at the photo's edge, so a well-framed ID back failed with
  `documentNotInFrame`. It now counts as a misread, as long as the other MRZ
  lines are complete. A real cut still shortens every line and is still
  caught.
- **The national number on an ID front is never the phone number.** When the
  "national number" label was lost (for example on a card cut at the top),
  the first 11-digit number on the card was taken, which could be the phone
  on the address line plus a stray digit. That line and any number starting
  `09` or `01` are now skipped. A number split by a space (`1197422 1992`)
  is joined.

## 0.4.0

A document that is not fully in the frame is now always a retake, and idlens
reads exactly what the user framed.

- **`documentNotInFrame` is always `failed`**, even when an MRZ, a name and a
  national number were read from the partial photo. 0.3.0 made it
  `needsReview` in that case; that let a cut card or half a front through.
- **The issue priority changed.** `documentNotInFrame` is now first on every
  page, before `wrongDocument`: nothing read from a partial photo is trusted,
  so the photo is always measured, even when the MRZ looks like another
  document's. For an ID back or a passport page a missing MRZ
  (`contentNotFound`) now comes before an unclear photo (`imageNotClear`);
  for an ID front or a certificate `imageNotClear` still comes first. When the
  two ID photos disagree the order is `documentNotInFrame`, `wrongDocument`,
  `readerUnavailable`, `timedOut`, `processingFailed`, `contentNotFound`,
  `imageNotClear`. The status rules follow: `needsReview` is now only an
  unclear photo or a field to check.
- **Cut-off detection fixed.** The check that measures the document's bright
  area never saw a page touching or crossing the photo's edge: its closing
  step eroded 7 px off every edge, so a page running off the photo ended 7 px
  inside it. A page that is cut off, such as an A4 off the left edge, is now
  `documentNotInFrame`. A half-photographed card (a front with a name and
  number read but a third of the card missing) is also caught by its shape.
  Limits are provisional: check good scans on your devices.
- **`process...` with `DocumentPhoto.camera` reads the guide box, not the box
  plus its strip,** for an ID card and a passport. An MRZ line half outside the
  box is cut for the reader too, and the photo is rejected instead of being
  rescued from the margin. The result's `images` are now the box crop (what
  your preview showed), not the wider crop. The wider crop is only used, then
  deleted, for the framing and clarity checks. A certificate and a file photo
  are read as before.
- New diagnostics: `framing.edgeGaps` (the room left between the document and
  each edge) and `photoCrop.<side>.readArea` (`box` or `box+strip`).

## 0.3.0

- A Sudan ID whose MRZ names another country (issuing country and nationality
  both not `SDN`) is now `wrongDocument`.
- Dates that contradict each other are now marked in `fieldsToCheck` for ID
  cards and passports: a birth date in the future, or on or after the issue or
  expiry date. An expired document is not flagged.

- New `ScanIssue.contentNotFound`: a page is in the frame and the photo is
  clear, but what it must hold was not found: the MRZ on a back or passport
  page, the required fields on an ID front or a certificate. It covers the front
  or the back photographed twice. Before, a missing MRZ and a certificate with
  nothing read were reported as `imageNotClear`, which wrongly blamed the photo,
  and a back photographed twice was only `needsReview` with no page to retake. A
  dark, blurry or glary photo still gives `imageNotClear`. An app with an
  exhaustive `switch` on `ScanIssue` must handle the new value.
- One rule now picks the issue for every document. The "fewer than 2 printed
  fields read" shortcut is removed: whether the card is in the frame is decided
  by its measured distance and edges alone.
- `documentNotInFrame` is now `needsReview` when everything identifying was
  still read (for example a valid MRZ on a card cut at an edge). It stays
  `failed` when nothing was read.

## 0.2.0

**Breaking release.** `process...` now take a `DocumentPhoto`, and a result says
what to do in two members instead of text to read. The first part of this entry
is a short guide to upgrading; the full list of changes follows it.

### Upgrading from 0.1.x

**1. Wrap the photos you pass to `process...`.** A `File` is no longer accepted.

```dart
// Before (0.1.x)
final result = await const IdLens().processIdCard(front: frontFile, back: backFile);

// After, for photos your own camera just took: idlens crops them.
final guide = DocumentGuide.forPreview(
  kind: DocumentKind.sudanId,
  side: DocumentSide.front,
  previewSize: cameraArea, // the area the camera image fills on screen
); // draw guide.box over your camera, and the same for the back
final result = await const IdLens().processIdCard(
  front: DocumentPhoto.camera(frontFile, box: guide.box, previewSize: cameraArea),
  back: DocumentPhoto.camera(backFile, box: backGuide.box, previewSize: cameraArea),
);

// After, for finished photos (a server, the gallery, a scan read again).
final result = await const IdLens().processIdCard(
  front: DocumentPhoto.file(frontFile),
  back: DocumentPhoto.file(backFile),
);
```

The `options` parameter of `process...` is removed: it was ignored.

**2. Read `issue`, `fieldsToCheck` and `status` instead of `issues` and `warnings`.**

```dart
// Before                          // After
result.issues                      result.issue          // one ScanIssue, or null
result.warnings                    result.fieldsToCheck  // keys of the fields to look at
ScanIssue.mrzNotFound              ScanIssue.imageNotClear (or documentNotInFrame)
ScanIssue.mrzCheckDigitsFailed     the fields the digit covers are in fieldsToCheck
result.confidence                  removed (use fieldsToCheck)
```

**3. Check `result.images` before `dispose()`.** For a `DocumentPhoto.camera`, the
images are the cropped photos: temporary files that `dispose()` deletes, so
upload them first. A `DocumentPhoto.file` image is your own file and is never
deleted.

**4. Optional:** pass a `timeout` to `process...` (or in the `scan...` options),
and use `issueSides` to retake only the page that caused an issue.

### All changes

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
  margin always fits. For `process...`, use `DocumentPhoto.camera` so idlens
  makes the same margin, or keep a thin strip of background around the
  document yourself for a `DocumentPhoto.file` (see the README).
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
- **Breaking:** the `process...` methods take a `DocumentPhoto` instead of a
  `File`, and no longer take an `options` parameter (it was ignored). Wrap each
  photo as `DocumentPhoto.camera(file, box:, previewSize:)` for a raw photo
  from your own camera, which idlens now crops inside the call, or as
  `DocumentPhoto.file(file)` for a finished photo, which is read as it is (the
  old behaviour). The cut-off and "too far" checks were tuned on photos with a
  thin strip of background around the document, which idlens' own camera makes
  and other cameras usually don't; cropping inside `process...` gives the same
  photo whichever way an app scans. For a camera photo, the result's `images`
  are the cropped photos (temporary files that `dispose()` deletes), and
  `diagnostics['photoCrop']` says how each was cropped.
- New `DocumentGuide.forPreview`: the box (and, for an ID back or a passport,
  the MRZ guide) to draw on your own camera screen, with idlens' own numbers,
  so the app doesn't copy them. An optional `maxHeight` makes the box smaller
  when buttons need room.
- The built-in camera and `process...` share one crop. The built-in camera no
  longer flattens a certificate: a flat copy is made when the page is read, so
  the margin the framing checks need stays in the photo.
- On a phone whose photos have a different shape from the camera preview, the
  crop could land in the wrong place. The box is now mapped onto the photo.
- `processCivilRegistry` now straightens a tilted or distant page to a flat A4
  sheet before reading it (the built-in flow reads a flat copy the same way).
  A photo with no clear page outline is read as before. The file passed in isn't changed and is
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
