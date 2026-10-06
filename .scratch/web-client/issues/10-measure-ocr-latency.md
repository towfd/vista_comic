Type: task
Status: resolved

# Measure OCR latency in the container, on CPU

## Question

How long does one selection actually take, end to end, with PaddleOCR + VietOCR running on CPU inside a Docker container?

Nothing on this map has a real number for this. What exists is the pipeline tuned on the host (`~/Documents/vietnamese-ocr`: CPU, `beamsearch=False`, long side capped at 1600px) and a batch run over 803 pages that recorded boxes and text but **no timings** — `runs/batch/` has no timing log. A container adds its own penalty and removes any possibility of MPS.

What to measure, on inputs that match the real flow — a single speech-bubble crop, not a whole page, so typically one or two detected boxes:

- Cold start: how long until the service can answer its first request, with the models loaded.
- Steady-state per-crop latency: detection and recognition separately, since `predict.py` already reports both.
- Resident memory with both models loaded, since this service sits beside `api` and `postgres` on one machine.
- The image size the models are actually fed after downscaling, because that is the main lever if the number is bad.

Why it is worth its own ticket rather than a line in part ①'s spec: the answer decides whether part ④'s selection flow needs a progress indicator, a cancel, or a queue — and if the number is bad enough, it reopens [the engine decision](04-ocr-engine-and-topology.md), which is why it should be known before part ① is specced rather than after it is built.

## Answer

**Measured on the host first (Apple M2, 8 cores, 16GB, CPU only, `beamsearch=False`), over 60 selections sampled across all eight batched chapters.** The container half is still outstanding — see "What is not measured yet" below.

Selections were built by clustering the batch run's detected line-boxes into bubble-sized groups and padding by 10px, which is the closest available stand-in for a hand-drawn rectangle. Median crop: 282x139px.

### Per-selection latency

| Lines detected | n | Median total | Max | Median crop |
|---|---|---|---|---|
| 0 | 3 | 0.01s | 0.01s | 187x44 |
| 1 | 24 | 0.12s | 0.29s | 190x67 |
| 2 | 6 | 0.27s | 0.33s | 292x131 |
| 3 | 12 | 0.42s | 0.91s | 327x175 |
| 4 | 9 | 0.64s | 1.15s | 392x225 |
| 5 | 4 | 0.90s | 1.41s | 396x285 |
| 6+ | 2 | 1.17s | 1.18s | 411x404 |

Across all 60: **median 0.27s, p90 0.91s, max 1.41s.**

**The shape is linear in lines of text, not in crop area.** Recognition costs **~0.129s per detected line** and accounts for essentially all of it; detection ranges 0.006-0.104s regardless of how big the crop is. A selection with no recognizable text returns in 0.007s, because the recognizer never runs.

So the usable rule for part ④: **latency is roughly `0.13s x lines`.** A one- or two-line bubble lands at 0.1-0.3s; a generous rectangle over a dense bubble reaches ~1s.

### Cold start and residency

- Python imports alone: **4.9s, 537MB RSS**, before any model is touched.
- Model load with weights already cached: **2.4s** (VietOCR 2.0s, PaddleOCR 0.4s).
- **RSS after load: 1380MB. Peak during inference: 1444MB.**

### Model weights — the finding that matters most for part 1

They arrive from two places and only one of them is durable:

- PaddleOCR's detection/recognition models: **31MB**, cached under `~/.paddleocr/whl`.
- VietOCR's `vgg_transformer.pth`: **~150MB**, and `vietocr/tool/utils.py` downloads it into **`tempfile.gettempdir()`**. On the first run here that download took **160 seconds**.

A container's temp directory does not survive recreation, so an image that does not bake the weights in pays that download **every time the container is recreated**, and the service is unavailable until it finishes. Baking both into the image is part 1's job.

### Platform wheels (checked, because it would have blocked containerisation outright)

Both frameworks publish `linux/arm64` wheels at the versions in use, so Apple Silicon needs no emulation. **But `paddlepaddle` must be pinned to 3.1.0**: it is the last release publishing a `manylinux2014_aarch64` wheel, and the current 3.3.1 ships Linux x86_64 only. `torch` 2.2.2 has `manylinux2014_aarch64`.

### What it means for the map

- **[The engine decision](04-ocr-engine-and-topology.md) holds.** Nothing here reopens it. Sub-second recognition for a typical bubble is well inside what the flow needs.
- **Part 4 needs a spinner, not a queue.** There is no case for a cancel button, a job id, or polling: the worst realistic selection measured was 1.41s. Something should appear above roughly half a second so a dense selection does not look frozen, and that is the whole requirement.
- **Part 1's real constraint is memory, not speed.** ~1.4GB resident, alongside `api` and `postgres` on a 16GB machine, is what decides whether the models stay loaded between requests (they must -- reloading costs 2.4s against a 0.27s inference) and how many workers the service can afford. One worker with resident models is the shape the numbers point at.
- Weights baked into the image, per the section above.

### Incidental finding, unrelated to this ticket

**`bench_pridict.py` is currently broken on this machine.** It imports the *installed* `paddleocr` (2.7.3), whose `ocr(det=True, rec=False)` path runs `if not dt_boxes:` against a numpy array and raises `ValueError` as soon as anything is detected. `predict.py` is unaffected because it imports the repo's *vendored* `PaddleOCR/` directory instead -- the two scripts have been using different PaddleOCRs. This measurement used the vendored one, matching `predict.py`. Worth knowing before part 1 pins dependencies: the vendored copy is what the pipeline was written against.

### What is not measured yet, and why that is fine

Everything above is the **host**. Docker Desktop was not running, and a measurement image (paddlepaddle + torch, several GB) has not been built, so the container's penalty is unmeasured. Both wheels are native arm64 and this is CPU-bound numeric work, so the expected penalty is modest -- but that is a prediction, not a measurement.

**Deliberately deferred into part 1 rather than run as a throwaway.** The host numbers already settled both decisions this ticket existed to unblock: part 4 gets a spinner rather than a queue, and [the engine decision](04-ocr-engine-and-topology.md) stands. A container figure refines the memory and cold-start budget; it changes nothing. Part 1 builds the real image anyway, and the number comes for free at that point.

**What part 1 must therefore still measure**, once its image exists: steady-state per-selection latency against the host's `0.13s x lines`, resident memory against 1380MB, and cold start with the weights baked in (which should remove the 150MB download entirely rather than merely speeding it up).

### Artifacts

Kept in this map's `assets/` so part 1 inherits them rather than rebuilding them:

- `assets/bench-crop-latency.py` -- the measurement. Builds bubble-sized selections by clustering the batch run's line boxes, warms up, then times each selection. Run it from `~/Documents/vietnamese-ocr` with that directory on `PYTHONPATH`.
- `assets/host-cpu-latency.json` -- the 60 per-selection rows behind every number above.
- `assets/Dockerfile.ocr-bench` -- an unbuilt, unverified draft for the container run, with the paddlepaddle 3.1.0 pin and its reason recorded. It installs dependencies only; source and samples are meant to be bind-mounted. Treat it as a starting point for part 1's real image, not as a tested artifact.
