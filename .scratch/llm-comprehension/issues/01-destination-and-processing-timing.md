Type: grilling
Status: resolved

# Destination and processing timing

## Question

What does "reaching the end of this map" produce (a spec, a locked decision, or an in-place change), and should comprehension processing run in real time (per user selection) or as a batch pipeline precomputed when a manga is downloaded?

## Answer

**Destination**: a `spec.md` under `.scratch/llm-comprehension/`, matching every prior feature in this repo (M6/M7/M8/remote-access) — ready to hand to `/to-tickets` once this map's remaining tickets resolve.

**Processing timing**: real-time, triggered by the existing per-selection flow (extends M6's selection UI and M8's Translate button) — not a batch/precompute pipeline. A batch approach (OCR + LLM over an entire chapter at download time, scheduled via Celery on a new recognition server) was considered and rejected: it replaces M6's on-device-selection design rather than extending it, it spends real (now paid, cloud-billed) processing on content the reader never asks to have explained, and it requires a much larger new-infrastructure bet (job queue, broker, standalone service) than this project's "minimum architecture for current acceptance criteria" precedent supports. The context-precision benefit that motivated batch (the LLM seeing more than an isolated crop) is captured instead by widening what's sent per real-time request (see ticket 02).

## Comments

Resolved via a `/grilling` session on 2026-08-01, in the same conversation that created this map.
