# vista_comic

`vista_comic` is a native iOS manga reader built with SwiftUI. Its goal is to let language learners understand unfamiliar content while reading — without constantly leaving the page to look up words or sentences.

## Product vision

Users import a manga source and read continuous images in the app. When they hit text they don't understand, they can recognize, translate, and save it right where they are — turning manga reading into a natural language-learning flow.

The intended end-to-end experience:

```text
Import a manga source
→ Browse manga and chapters
→ Read continuous manga images
→ Select a text region you don't understand
→ OCR recognition
→ Translation and meaning explanation
→ Save the word or sentence
```

## Long-term roadmap

### 1. Manga reading experience

- Manga library
- Manga and chapter navigation
- Vertical image reader
- Reading progress and basic controls

### 2. Content import

- Import from a URL or another legitimate source
- Manga and chapter metadata
- Image loading, caching, and failure handling

### 3. OCR

- Selecting text regions in manga
- Multi-language text recognition
- Correcting recognition results

### 4. Translation and language learning

- Original text and translation side by side
- Word, sentence, and context explanations
- LLM-assisted comprehension
- Saving and reviewing learning material

### 5. Profile and sync

- Reading history
- Saved content
- User settings
- Cross-device sync

## Technical direction

- Platform: iOS
- UI: SwiftUI
- Approach: progress in small, verifiable milestones
- Current priority: keep the architecture native, simple, and easy to learn

For the milestone roadmap and history, see [`PLAN.md`](PLAN.md); work currently in progress (specs and tickets) lives under `.scratch/`. For agent collaboration and development rules, see [`CLAUDE.md`](CLAUDE.md).
