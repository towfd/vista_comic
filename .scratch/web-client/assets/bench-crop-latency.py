"""Measure per-selection OCR latency on realistic speech-bubble crops.

Ticket .scratch/web-client/issues/10-measure-ocr-latency.md

Input shape matches the web flow decided in ticket 05: the browser crops one
hand-drawn rectangle around a bubble at natural resolution and uploads it, so
the recognizer sees a small image with one or two lines of text -- never a page.
Selections here are built by clustering the batch run's detected boxes, which is
the closest available stand-in for where a reader would actually draw.
"""
import json, glob, os, sys, time, resource, statistics

t0 = time.perf_counter()
from PIL import Image
import torch, paddle
from vietocr.vietocr.tool.predictor import Predictor
from vietocr.vietocr.tool.config import Cfg
from PaddleOCR import PaddleOCR  # the repo-vendored one, as predict.py uses
from predict import predict
import_elapsed = time.perf_counter() - t0

def rss_mb():
    # macOS reports ru_maxrss in bytes.
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / (1024 * 1024)

print(f"imports: {import_elapsed:.1f}s, rss={rss_mb():.0f}MB", flush=True)

# --- model load, timed separately -----------------------------------------
t = time.perf_counter()
cfg = Cfg.load_config_from_name('vgg_transformer')
cfg['cnn']['pretrained'] = True
cfg['predictor']['beamsearch'] = False      # matches bench_pridict.py
cfg['device'] = 'cpu'                        # matches bench_pridict.py
paddle.set_device('cpu')
recognitor = Predictor(cfg)
vietocr_load = time.perf_counter() - t
print(f"vietocr load: {vietocr_load:.1f}s, rss={rss_mb():.0f}MB", flush=True)

t = time.perf_counter()
detector = PaddleOCR(lang='vi', use_angle_cls=False, use_gpu=False, show_log=False)
paddle_load = time.perf_counter() - t
print(f"paddleocr load: {paddle_load:.1f}s, rss={rss_mb():.0f}MB", flush=True)
rss_after_load = rss_mb()

# --- build realistic selections -------------------------------------------
PAD = 10          # the slop in a hand-drawn rectangle
CLUSTER_GAP = 28  # boxes closer than this belong to the same bubble

def cluster(boxes):
    """Group line boxes into bubble-sized selections."""
    rects = [(b['box'][0][0], b['box'][0][1], b['box'][1][0], b['box'][1][1]) for b in boxes]
    groups = []
    for r in sorted(rects, key=lambda r: (r[1], r[0])):
        for g in groups:
            gx0, gy0, gx1, gy1 = g
            if (r[0] < gx1 + CLUSTER_GAP and r[2] > gx0 - CLUSTER_GAP
                    and r[1] < gy1 + CLUSTER_GAP and r[3] > gy0 - CLUSTER_GAP):
                g[0], g[1] = min(gx0, r[0]), min(gy0, r[1])
                g[2], g[3] = max(gx1, r[2]), max(gy1, r[3])
                break
        else:
            groups.append(list(r))
    return groups

selections = []
for jf in sorted(glob.glob('runs/batch/chapter-*/0*.json')):
    page = jf.replace('runs/batch', 'comic').replace('.json', '.jpg')
    if not os.path.exists(page):
        continue
    boxes = json.load(open(jf))
    if not boxes:
        continue
    for g in cluster(boxes):
        w, h = g[2] - g[0], g[3] - g[1]
        if w < 40 or h < 18:          # detector noise, not a bubble
            continue
        selections.append((page, g))

# Spread the sample across the whole batch rather than taking the first N pages.
N = int(sys.argv[1]) if len(sys.argv) > 1 else 40
step = max(1, len(selections) // N)
sample = selections[::step][:N]
print(f"selections available={len(selections)}, sampled={len(sample)}", flush=True)

# --- warm up (first inference is never representative) ---------------------
p, g = sample[0]
img = Image.open(p).convert('RGB')
t = time.perf_counter()
predict(recognitor, detector, img.crop((max(0,g[0]-PAD), max(0,g[1]-PAD), g[2]+PAD, g[3]+PAD)), padding=2)
print(f"warmup: {time.perf_counter()-t:.2f}s", flush=True)

# --- measure ---------------------------------------------------------------
rows = []
for i, (p, g) in enumerate(sample, 1):
    img = Image.open(p).convert('RGB')
    crop = img.crop((max(0, g[0]-PAD), max(0, g[1]-PAD), g[2]+PAD, g[3]+PAD))
    t = time.perf_counter()
    boxes, texts, stats = predict(recognitor, detector, crop, padding=2)
    total = time.perf_counter() - t
    rows.append({
        'page': p, 'w': crop.size[0], 'h': crop.size[1],
        'det': stats['detection_seconds'], 'rec': stats['recognition_seconds'],
        'total': total, 'boxes': stats['box_count'],
        'chars': sum(len(str(x)) for x in texts),
    })
    if i % 10 == 0:
        print(f"  {i}/{len(sample)}", flush=True)

out = {
    'machine': 'Apple M2, 8 cores, 16GB',
    'config': 'cpu, beamsearch=False, use_gpu=False',
    'load': {'import': import_elapsed, 'vietocr': vietocr_load, 'paddleocr': paddle_load,
             'rss_after_load_mb': rss_after_load, 'rss_peak_mb': rss_mb()},
    'rows': rows,
}
dest = os.environ.get('BENCH_OUT', 'bench_crop_latency.json')
json.dump(out, open(dest, 'w'), indent=1)

def pct(vals, q):
    vals = sorted(vals)
    return vals[min(len(vals)-1, int(len(vals)*q))]

tot = [r['total'] for r in rows]
det = [r['det'] for r in rows]
rec = [r['rec'] for r in rows]
print("\n===== RESULT =====")
print(f"n={len(rows)}  crop px: median {int(statistics.median([r['w'] for r in rows]))}x{int(statistics.median([r['h'] for r in rows]))}")
print(f"boxes/selection: median {statistics.median([r['boxes'] for r in rows]):.0f}  max {max(r['boxes'] for r in rows)}")
print(f"total   median {statistics.median(tot):.2f}s   p90 {pct(tot,0.9):.2f}s   max {max(tot):.2f}s   min {min(tot):.2f}s")
print(f"detect  median {statistics.median(det):.2f}s   p90 {pct(det,0.9):.2f}s")
print(f"recog   median {statistics.median(rec):.2f}s   p90 {pct(rec,0.9):.2f}s")
print(f"cold start (load only): {vietocr_load+paddle_load:.1f}s   rss after load: {rss_after_load:.0f}MB   peak: {rss_mb():.0f}MB")
