Type: grilling
Status: resolved

# The OCR service interface: crop in the browser

## Question

What does the web send to the OCR service — a cropped image, a rectangle plus page identifiers for the backend to crop from the library, or the whole page?

## Answer

**The browser crops and uploads the image. The OCR service stays pure: image in, text out.**

It never mounts the library and never learns what a Comic, Chapter or Page is, which keeps its interface identical to the shape `bench_pridict.py` already has — so the existing code transfers rather than being rewritten.

A quality objection was raised against browser-side cropping and does not survive checking: an `<img>` decodes at full resolution and CSS only scales the display, so a canvas crop taken against `naturalWidth`/`naturalHeight` is original pixels. That is the same mapping `SelectionCropMapping` performs on iOS (screen rectangle to source-image pixel space), and it satisfies the same requirement `.scratch/ocr-recognition/spec.md` states as user story 11 — a small, tightly-drawn selection must still reach the recognizer at good quality.

The one real prerequisite is already satisfied: a canvas that has drawn a cross-origin image is tainted and `toBlob()` fails outright. [Same-origin serving](03-same-origin-static-serving.md) is what prevents that.

Sending coordinates for the backend to crop was the runner-up — smallest upload — and was rejected because it couples the OCR service (or a proxy in `api`) to the manga data model for no gain; the upload is a few tens of kilobytes either way. Sending the whole page for full-page detection was rejected on cost and on direction: it is the whole-book precompute model, abandoned on 2026-08-07 (see `ROADMAP.md`).

## Comments

Resolved via the `/grilling` session on 2026-09-16 that created this map.
