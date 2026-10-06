Type: grilling
Status: resolved

# OCR engine and service topology

## Question

Which OCR engine does the backend run for Vietnamese, and where does it sit in the Compose stack?

## Answer

**PaddleOCR's DB detector plus VietOCR for recognition, as a fourth Compose service.**

The engine is not a new choice — the developer already has this pipeline working at `~/Documents/vietnamese-ocr`, a fork of `bmd1905/vietnamese-ocr` with timing instrumentation added to `predict.py` and a `bench_pridict.py` that is already a complete clipboard-in, text-out tool. It has been run over **803 real manga pages** (chapters 03–10), and the tuning is visible in the committed state: device forced to CPU (the MPS line is commented out), `beamsearch=False`, `use_gpu=False`, images downscaled to 1600px on the long side. Detected boxes per page: median 5, maximum 46.

Claude vision was the alternative and was rejected by the developer on cost, with a reason that holds up: the flow does not need high precision, because the recognized text is editable before anything downstream uses it (`.scratch/ocr-recognition/spec.md`, user story 6). A cloud OCR API was rejected as a third vendor to keep.

**A separate service, not an addition to `api`.** The pipeline needs both `paddlepaddle` and `torch`, which is an order of magnitude more image than the current `python:3.12-slim` `api`. Folding it in would mean every one-line API change rebuilds several gigabytes, model loading would delay API startup, and the healthcheck and restart policy of the reading path would be tied to the OCR path. Running it uncontainerised on the Mac (which would allow MPS) was rejected because it takes `docker compose up` away as the single command that brings the stack up — and the developer had already given up MPS in the existing tuning anyway.

Latency in a container on CPU is **not yet measured** — see [Measure OCR latency](10-measure-ocr-latency.md).

## Comments

Resolved via the `/grilling` session on 2026-09-16 that created this map.
