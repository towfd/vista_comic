Type: grilling
Status: resolved

# The six-part split

## Question

With the architecture locked, how does the web client divide into parts, each small enough to be grilled into its own spec?

## Answer

**Six parts.**

```
① OCR service ──────────────────┐
                                ↓
② Web foundation ──→ ③ Reader ──→ ④ Learning flow
                 ├──→ ⑤ Card library
                 └──→ ⑥ Review
```

- **① OCR service** — the fourth Compose service. Packaging the PaddleOCR + VietOCR pipeline, getting model weights into the image, and the image-in/text-out interface. Pure backend, depends on no frontend work, and independently verifiable by posting an image and reading the text back. **Takeable immediately.**
- **② Web foundation** — the `web/` project skeleton, FastAPI mounting the build output, the Access browser-login policy, the API client layer (the web's counterpart to `Networking/`), routing and the application shell. Everything else stands on it.
- **③ Reader** — library, comic, chapter, continuous reading, progress read/write, page loading and prefetch.
- **④ Learning flow** — select a region, crop on canvas, call OCR, editable source text beside an empty translation field, optional explanation, add to the card library. **This is the thing the request was actually about.**
- **⑤ Card library** — listing, detail, editing, deletion, reset.
- **⑥ Review** — the TypeScript question-generation engine (cloze, distractors, matching, sentence rebuild, round assembly), the practice screens, and study settings. The largest part by some margin.

Splitting ⑥ into an engine spec and a UI spec was offered — its iOS counterpart really is 840 lines of pure logic plus ~900 of UI — and declined for now; it can still be split when its own grilling session shows what it holds. Merging ③ and ④ was offered and declined, because keeping them apart means "the web can read manga" can be verified on its own before selection is built on top.

## Comments

Resolved via the `/grilling` session on 2026-09-16 that created this map. This is the map's destination: with the split agreed and the eight decisions above locked, each part proceeds to its own `/grilling` session and its own spec.
