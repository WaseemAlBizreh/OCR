# Validation rules

Every check idlens makes on a scan, where it lives, and what it decides. Update
this file when a rule or a limit changes. The tests that pin the outcomes are in
[`test/scan_issue_matrix_test.dart`](../../test/scan_issue_matrix_test.dart).

## The order of the checks

```
photo checks ──► MRZ read ──► resolve (framing first) ──► merge ──► ScanReview
(per page)                                                   issue · issueSides
                                                             fieldsToCheck · status
```

1. Each page is measured: clarity, distance, cut-off.
2. The MRZ is read from the back (ID card) or the data page (passport).
3. `ScanIssueResolver.resolve` picks the one issue for the MRZ page.
4. An ID card's front issue and the back's issue are combined (`ScanReview.worse`).
5. `ScanReview` turns it all into `issue`, `issueSides`, `fieldsToCheck`, `status`.

## 1. Photo checks (`ImageQuality`, `DocumentFraming`)

Files: [`image_quality.dart`](../../lib/src/domain/image_quality.dart),
[`document_framing.dart`](../../lib/src/domain/document_framing.dart).

| Check | Limit | Issue |
|---|---|---|
| Distance: document's share of the photo | below `0.42` (about 72% of the box width) | `documentNotInFrame` |
| Sharpness | below `60` | `imageNotClear` |
| Brightness | below `110` | `imageNotClear` |
| Glare: share of white pixels | above `0.20` | `imageNotClear` |
| Cut-off: a corner or the bright area within `1.5%` of an edge | any one edge | `documentNotInFrame` |

- **The cut-off limit is measured against the photo's edge, not the guide
  box, and no edge limit can do better.** The camera crop is the box plus a 6%
  strip, so a card exactly in the box lies 5.4% inside each edge. Real users
  fit it loosely: a good ID back was about 1% past the box (bottom gap 0.043),
  a good passport page 2-3% past it (gaps 0.025 to 0.040). A limit of `3.5%`
  (tried 2026-11-09 to catch a card held low, so that its last MRZ line was
  half outside the box) rejected that passport, so it went back to `1.5%`. A
  card held low enough to cut its MRZ lies in the same 2-4% range, so telling
  them apart needs the MRZ lines' own positions (open item 8).
  `framing.edgeGaps` in the diagnostics shows the room left on each edge.
- **The bright-area check was blind to edges until 2026-11-09.** The closing
  step used opencv_dart's default black border, which eroded 7 px (half the
  15x15 kernel) off any area reaching the photo's edge, so the area always
  ended at least 7 px inside it (every real payload showed `7` on the touched
  sides: `[7,7,310,246]`, `left: 7`). That is more than the `1.5%` limit, so a
  page running off the photo was never cut off by this check. Fixed with
  `borderType: BORDER_REPLICATE`. Not run on a phone: the same scans should now
  show `0` on a side they touch.
- **Distance wins over clarity.** A far card is also dark and blurry, but that is
  not the real cause, so `documentNotInFrame` comes first. It also wins over
  everything else (see section 3).
- **Cut-off checks, strongest first:** the document outline (4 corners; trusted
  above `0.3` of the photo, measures distance down to `0.15`), then the bright
  area against the background (between `0.15` and `0.92` of the photo, touching
  an edge for at least `0.5` of its own side), then printed text running to an
  edge. A hand holding the card touches an edge over a much shorter stretch and
  doesn't count.
- **The bright area must also have the card's shape.** Touching no edge is not
  enough: half a card (the rest dark or outside the crop) has a box far from
  the card's width/height ratio (a quarter turn is accepted). Two limits: an
  area filling at least `90%` of its own box is an upright rectangle and must
  match within `10%`; one filling less (a tilted card fills about 64% at 15
  degrees) gets `25%`. Found on real payloads, both `verified` before: a half
  front of 254x239 (ratio 1.06) and one of 303x239 (ratio 1.27, which the first
  25% limit let through); a Sudan ID is 1.59, and the good back in the same
  scan was 1.62. The limits are provisional; a hand holding the card can widen
  the box.
- The sharpness, brightness and glare limits are **provisional**, tuned on few
  photos. A real back photo with brightness 102.6 and sharpness 221 was flagged
  `imageNotClear`; check new device payloads against them.

## 2. The MRZ

Files: [`mrz_reader.dart`](../../lib/src/data/mrz/mrz_reader.dart),
[`mrz_parser.dart`](../../lib/src/data/mrz/mrz_parser.dart),
[`mrz_validator.dart`](../../lib/src/domain/mrz_validator.dart).

| Rule | Detail |
|---|---|
| Which documents have one | ID card and passport. A certificate has none. |
| Expected format | ID card = TD1 (3 lines of 30), passport = TD3 (2 lines of 44) |
| Wrong document | an MRZ was read but its format isn't the expected one (a passport shown for an ID card, or the reverse); or, for a Sudan ID, both the issuing country and the nationality differ from `SDN` (one misread field is forgiven). A passport is not tied to a country. A missing MRZ is **not** a wrong document. |
| Look-alike repair | by the expected character type per position: `O`/`0`, `I`/`1`, `S`/`5`, `B`/`8` |
| Check digits (ICAO 9303) | document number, date of birth, expiry date, composite; plus personal number on a passport |
| Best read kept | even if some digits fail, so `mrz.checks` shows the near miss |
| What is read | `process...` with `DocumentPhoto.camera` (ID card, passport): the photo is cropped to the guide box plus a 6% strip, then the **box** is cut out of that, and the box is what is read and returned (`images`), exactly what the app's preview showed. An MRZ line half outside the box is therefore cut for the reader too and does not read, instead of being rescued from the strip. The wider crop is kept only for the framing and clarity checks (they need the background) and is deleted after the read. A certificate reads the wider crop, because flattening its page needs the strip. A file photo is read as it is. `diagnostics.photoCrop.<side>.readArea` says `box` or `box+strip`. |
| Cut MRZ | a line missing its first or last characters sets `mrz.cutOff` and gives `documentNotInFrame` (a name has no check digit, so a cut name would pass unseen) |

`MrzValidator` only judges the format. Wrong values inside the MRZ are judged
later, as `fieldsToCheck`.

## 3. Choosing the issue (`ScanIssueResolver.resolve`)

File: [`scan_issue.dart`](../../lib/src/domain/scan_issue.dart). First match wins.
`documentNotInFrame` is first on every page, a wrong document included: nothing
read from a partial photo can be trusted, so the photo is always measured, even
when the MRZ looks like another document's.

Page without an MRZ (ID front, certificate):

| # | Condition | Issue |
|---|---|---|
| 1 | the photo check says `documentNotInFrame`, or the document is cut off | `documentNotInFrame` |
| 2 | the MRZ is of another document | `wrongDocument` |
| 3 | the photo is dark, blurry or glary | `imageNotClear` |
| 4 | the page lacks a required field | `contentNotFound` |
| 5 | otherwise | none |

Page read for its MRZ (ID back, passport): the MRZ comes before the photo
quality.

| # | Condition | Issue |
|---|---|---|
| 1 | not in frame, or the document or MRZ is cut off | `documentNotInFrame` |
| 2 | the MRZ is of another document | `wrongDocument` |
| 3 | no MRZ was read | `contentNotFound` |
| 4 | the photo is dark, blurry or glary (MRZ read) | `imageNotClear` |
| 5 | otherwise | none |

On an MRZ page a blurry photo with no MRZ read reports `contentNotFound`, not
`imageNotClear`: the quality limits are provisional, and a false "blurry" must
not hide a wrong side. Revisit once the limits are tuned on device payloads.

## 4. Combining the pages (`ScanReview`)

File: [`scan_review.dart`](../../lib/src/api/scan_review.dart).

**Which issue wins** when the two ID card photos differ, most serious first:

`documentNotInFrame` > `wrongDocument` > `readerUnavailable` > `timedOut` >
`processingFailed` > `contentNotFound` > `imageNotClear`

On a tie the front is kept.

**`issueSides`**, the pages to retake:

| Issue | Pages |
|---|---|
| none, `processingFailed`, `readerUnavailable`, `timedOut` | none (the photos are fine) |
| `wrongDocument` | every page of the document |
| `documentNotInFrame`, `contentNotFound`, `imageNotClear` | each page whose own check found a problem; if none did, the last page (the one read for the MRZ or fields) |

**Readable** (`isReadable`): nothing identifying was read when

- ID card or passport: no MRZ;
- ID card or certificate: none of the required fields (name, national number;
  certificate: national number, name, date of birth);
- a passport has no required fields, its MRZ is enough.

An ID front is judged like the back: with a good photo but no required field it
is `contentNotFound` on the front (a back photographed twice). An unreadable
document always has an issue, because the missing content is itself the issue
(`contentNotFound`); the tests assert it.

## 5. Fields (`fieldsToCheck`)

A field is listed (and its value kept, never cleared) when:

| Rule | Example |
|---|---|
| a required field wasn't read | ID card: `arabicName`, `nationalNumber`. Certificate: `nationalNumber`, `name`, `dateOfBirth`. Passport: none. |
| the pipeline doubted it | a printed value that disagrees with the MRZ; `DateRules` (ID card and passport): birth date in the future, birth date on or after the issue or expiry date, issue date on or after the expiry date; on a certificate, a birth date not before the issue date |
| a failed MRZ check digit covers it | `documentNumber`, `dateOfBirth`, `expiryDate`, `personalNumber` → `nationalNumber`; `composite` → document number, birth and expiry |
| a date isn't a real calendar date | `parseScanDate` accepts only `yyyy-MM-dd` or `yyyy/MM/dd` and rejects `31 Feb` |

Merging: an MRZ value wins when its own check digit passed; printed text fills
the rest.

Other fields not read are `null`, are not listed, and don't change the status.

## 6. Status (`ScanReview.statusFor`)

| Status | When |
|---|---|
| `failed` | not readable, or `documentNotInFrame`, `wrongDocument`, `processingFailed`, `readerUnavailable`, `timedOut` |
| `needsReview` | readable, and an issue of `imageNotClear`, or at least one field in `fieldsToCheck` |
| `verified` | no issue and nothing to check |
| `incomplete` | the user left before every page was captured (set by the flow, nothing read) |

So `contentNotFound` is always `failed` (it means unreadable). So is
`documentNotInFrame`, even when a valid MRZ, a name and a national number were
read: a card cut at an edge, or half of a front, must be retaken, and nothing
read from it is accepted. (Before 2026-11-09 a fully read card cut at an edge
was `needsReview`.)

## 7. Failures that aren't about the photo

| Issue | Cause | Retake? |
|---|---|---|
| `processingFailed` | unexpected error while reading | yes, but images are returned |
| `readerUnavailable` | the text reader couldn't start (for example no storage) | no, read the same photos again |
| `timedOut` | reading passed the `timeout` (`ScanDeadline`) | no, read the same photos again |

All three give `failed` and no `issueSides`.

## Known gaps (updated 2026-11-06)

Fixed on 2026-11-06: any TD1 passing as a Sudan ID (needs `SDN`); impossible
dates (`DateRules`); date comparison on raw text; a back photographed twice
(front `contentNotFound`); a certificate with nothing read (`contentNotFound`,
not `imageNotClear`); a fully read card cut at an edge (`needsReview`, not
`failed`). Simplified: a missing MRZ is judged by `issue` and `issueSides` only
(the notice text no longer inspects `mrz`); certificates use the same resolver
as the other documents; the "fewer than 2 fields read" rule and
`recognizedFieldCount` are gone, so the distance check alone decides whether the
card is in the frame.

Still open:

1. **Quality is measured on the bottom band only.** `ImageQualityChecker.check`
   crops the bottom 42% (ID) or 32% (passport) of the photo, so brightness and
   glare describe that strip, including any dark table in it, not the card.
   This probably explains a sharp back photo with brightness 102.6 being
   flagged. Needs device payloads to fix.
2. **The limits (sharpness 60, brightness 110, glare 0.20) are provisional**,
   tuned on few photos.
3. **An empty photo relies on the distance check.** With the field-count rule
   gone, a photo with no card whose frame could not be measured gives
   `imageNotClear` or `contentNotFound` and not `documentNotInFrame`.
4. ~~National number is never validated against the MRZ.~~ **Closed
   2026-11-06**: a Sudan TD1 does not carry it, so there is nothing to compare.
   The printed number is accepted only as exactly 11 digits
   (`SudanCardParser`).
5. **Two-digit birth years.** `_isoDate` reads `yy <= current yy` as 20yy, so
   someone born in 1920-1926 is read as born 2020-2026. Mitigated: a differing
   printed birth date is flagged. Not fixable from the MRZ alone.
6. **The country check** needs both the issuing country and the nationality to
   differ from `SDN`, so a genuine card with both misread would be rejected.
7. **No end-to-end test** with real photos; the tests cover the decision rules.
8. ~~An MRZ cut at the guide box edge is accepted~~ **Fixed 2026-11-09, not
   verified on a phone**: the box is cropped first and that is what is read
   (section 2). Reported on an ID back whose third line was half outside the
   box and a passport whose second line was; the reader saw both in the 6%
   strip. An edge limit could not tell these from a loosely framed card
   (section 1). Two things remain: such a photo now fails as `contentNotFound`
   (no MRZ read), not `documentNotInFrame`; and the built-in camera still
   reads its wider crop, since only `process...` knows the box.
