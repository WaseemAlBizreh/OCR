# Validation rules

Every check idlens makes on a scan, where it lives, and what it decides. Update
this file when a rule or a limit changes. The tests that pin the outcomes are in
[`test/scan_issue_matrix_test.dart`](../../test/scan_issue_matrix_test.dart).

## The order of the checks

```
photo checks ──► MRZ read ──► wrong document? ──► merge ──► ScanReview
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

- **Distance wins over clarity.** A far card is also dark and blurry, but that is
  not the real cause, so `documentNotInFrame` comes first.
- **Cut-off checks, strongest first:** the document outline (4 corners; trusted
  above `0.3` of the photo, measures distance down to `0.15`), then the bright
  area against the background (between `0.15` and `0.92` of the photo, touching
  an edge for at least `0.5` of its own side), then printed text running to an
  edge. A hand holding the card touches an edge over a much shorter stretch and
  doesn't count.
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
| Cut MRZ | a line missing its first or last characters sets `mrz.cutOff` and gives `documentNotInFrame` (a name has no check digit, so a cut name would pass unseen) |

`MrzValidator` only judges the format. Wrong values inside the MRZ are judged
later, as `fieldsToCheck`.

## 3. Choosing the issue (`ScanIssueResolver.resolve`)

File: [`scan_issue.dart`](../../lib/src/domain/scan_issue.dart). One rule for
every page of every document. First match wins:

| # | Condition | Issue |
|---|---|---|
| 1 | the MRZ is of another document | `wrongDocument` |
| 2 | the photo check says `documentNotInFrame`, or the document or MRZ is cut off | `documentNotInFrame` |
| 3 | the photo is dark, blurry or glary | `imageNotClear` |
| 4 | the page lacks what it must hold | **`contentNotFound`** |
| 5 | otherwise | none |

"What it must hold": the MRZ on a back or passport page; a required field (name
or national number) on an ID front; a required field on a certificate. An unclear
photo (3) comes before missing content (4) because it is the first thing to
retake. Row 4 is the case of a page that was photographed twice (the front twice
or the back twice).

## 4. Combining the pages (`ScanReview`)

File: [`scan_review.dart`](../../lib/src/api/scan_review.dart).

**Which issue wins** when the two ID card photos differ, most serious first:

`wrongDocument` > `readerUnavailable` > `timedOut` > `processingFailed` >
`documentNotInFrame` > `contentNotFound` > `imageNotClear`

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
| `failed` | not readable, or `wrongDocument`, `processingFailed`, `readerUnavailable`, `timedOut` |
| `needsReview` | readable, and an issue of `imageNotClear` or `documentNotInFrame`, or at least one field in `fieldsToCheck` |
| `verified` | no issue and nothing to check |
| `incomplete` | the user left before every page was captured (set by the flow, nothing read) |

So `contentNotFound` is always `failed` (it means unreadable). `documentNotInFrame`
is `failed` only when nothing identifying was read, for example no MRZ on a far
card; a valid MRZ on a card cut at an edge is `needsReview`.

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

By design: a wrong **side** is not detected as such. It shows as
`contentNotFound` on the page that lacks its content, the only claim idlens can
make.
