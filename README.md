# vista_comic

**Read manga in a language you don't speak yet — and keep the words you had to look up.**

A native iOS manga reader for language learners. Point it at a folder of manga, read
continuously, and when a speech bubble stops you, drag a box around it: the app reads
the text off the page, translates it on-device, explains it if you ask, and turns it
into a card that comes back until you know it.

![Platform](https://img.shields.io/badge/platform-iOS%2018.1%2B-black)
![UI](https://img.shields.io/badge/UI-SwiftUI-orange)
![Backend](https://img.shields.io/badge/backend-FastAPI%20%2B%20PostgreSQL-009688)
![OCR](https://img.shields.io/badge/OCR-on--device%20Vision-blue)
![Tests](https://img.shields.io/badge/tests-541%20Swift%20%2F%20275%20Python-brightgreen)

---

## The problem this solves

Reading real material is the fastest way into a language, and it is also the thing
learners abandon first. Not because it is hard — because of the **interruption**. One
unfamiliar word means leaving the page, switching apps, typing a word you cannot spell
in a script you barely read, and coming back having lost the thread. Do that four times
on one page and you are no longer reading; you are doing data entry.

The other half of the problem is that none of it sticks. The word you looked up on
Tuesday is a word you look up again on Thursday, and the lookup leaves no trace that
would tell you so.

vista_comic closes both gaps **without leaving the page**: understanding happens where
you are reading, and everything you had to look up becomes something you will be asked
about again.

## The loop

```mermaid
graph LR
    A["📖 Read<br/>a chapter"] --> B["✏️ Drag a box<br/>round the text"]
    B --> C["🔍 OCR<br/>on device"]
    C --> D["🌐 Translate<br/>instantly"]
    D --> E["💡 Explain in depth<br/>optional · LLM"]
    D --> F["➕ Keep it<br/>as a card"]
    E --> F
    F --> G["🎮 Practise<br/>until you know it"]
    G --> A
```

Every arrow in that diagram happens inside the reader except the last one. The point of
the design is that reading is never suspended: translation is instant and on-device, so
tapping **Translate** costs no network call and no waiting. Only the explicit *deeper
explanation* reaches out to a model, and even then you can close the sheet and keep
reading while it is written.

---

## What it does

### 📚 Reading

| | |
|---|---|
| **A folder is the library** | Your manga stays where it is on disk. The backend scans it live into a catalog — nothing is imported, copied, or ingested, and re-organising your folders does not lose your progress. |
| **Vertical continuous reader** | Pages stream in a lazy column, prefetched ahead of where you are, so scrolling does not wait on the network. |
| **Pinch to zoom** | Zoom into dense panels with scroll anchoring that keeps the point under your fingers where you put it. |
| **Progress that survives** | The last page you read is kept per chapter and keyed on a stable path hash, so a library re-scan cannot orphan it. Chapters show as unread / reading / read, and each comic knows which chapter *Continue* should open. |
| **Offline download** | Keep up to 20 chapters on the device, oldest evicted first, covers included. Reading offline still records progress, which catches up on reconnect. |

### 🔍 Understanding

| | |
|---|---|
| **Select any region** | Drag a box over a speech bubble. Drag it back to the cancel zone if you missed. |
| **On-device OCR** | Apple's Vision framework reads the crop — no upload, no cost, works offline. v1 is tuned for **Vietnamese** source text (see below), and low-confidence results are withheld rather than shown as a likely-wrong guess. Recognition can always be corrected by hand before you act on it. |
| **Instant translation** | Apple's Translation framework runs on-device, into Traditional Chinese by default or any of six target languages. No request spent, no round trip. This is the fast path and it is the one you use constantly. |
| **Deeper explanation, on request** | Ask and the backend calls Claude for a structured explanation — meaning, context notes, and how the line actually works. Two tiers: Haiku 4.5 by default, Sonnet 5 when you ask for depth. It is written in the background, so closing the sheet does not cancel it. |
| **A daily cost ceiling** | The explanation route is capped per day on the backend. An LLM in a reading app is a running meter, and the cap is what makes it safe to leave on. |

> **Which languages?** v1 is built around the library it was built for:
> Vietnamese-subtitled Korean webtoon scanlations, read by a Traditional Chinese
> speaker. So recognition is fixed to Vietnamese and translation defaults to 繁體中文.
> Recognition sits behind an `OCRRecognizer` protocol and translation behind a
> `Translator` one, so a second source language is a new conformance rather than a
> rewrite of the reader.

### 🎮 Remembering

This is the half that most readers never get, and it is a full spaced-repetition system
rather than a saved-words list.

**Adding a card is the quality gate.** Nothing is collected automatically. A card exists
because you read the translation, agreed with it, and pressed add — which is why the
deck stays worth practising.

Four question types, drawn at random from whatever each card can actually support:

| Mode | What you see | What you do |
|---|---|---|
| **Cloze, four choices** | The sentence you collected, with one of *your own* words blanked, plus its meaning | Recognise the missing word among four |
| **Cloze, typed** | The same sentence and meaning | Produce the missing word from memory |
| **Rearrange** | The meaning, and the sentence's words scrambled into a tray | Assemble the sentence — tap to take back, hold to move |
| **Translate** | The meaning alone | Type the whole sentence |

Details that matter in use:

- **Blanks come from your deck, not a dictionary.** A word is only blanked if you
  collected it, and the least familiar candidate in the sentence is the one removed.
  Wrong options are drawn from your other cards and shape-matched by length, so the
  answer is never given away by being the only short one.
- **Tones are forgiven but named.** Typing Vietnamese diacritics on a phone is
  laborious; rejecting an otherwise perfect answer over one charges you for typing
  rather than testing recall. So it counts as correct — and then says *watch the tones*,
  because a lesson that stayed quiet would be teaching that tones are decoration.
- **Answering works with no network.** The scheduler is implemented twice on purpose —
  once in Python, once in Swift — so a session in airplane mode schedules correctly.
  Parity tests assert both against the same cases, and when an answer reaches the server
  the server's result wins.

### 🗓 The scheduler

Anki's model, which is SM-2's, with binary grading. New cards walk short **learning
steps** measured in minutes; clearing the last one graduates them onto an interval
table measured in days.

```mermaid
stateDiagram-v2
    [*] --> New
    New --> Learning: any answer
    Learning --> Learning: wrong → back to step 0
    Learning --> Review: cleared the last step
    Review --> Review: correct → next slot
    Review --> Relearning: wrong → keeps slot − 1
    Relearning --> Relearning: wrong → back to step 0
    Relearning --> Review: cleared the steps → the slot it kept
```

| | |
|---|---|
| **Learning steps** | 5, 7, 10 minutes by default — adjustable. Wider than Anki's 1m/10m because a session here is one sitting, not a queue to grind down. |
| **Interval table** | 1 → 3 → 7 → 21 → 60 → 150 → 365 days. |
| **A lapse costs one slot, not everything** | Miss a card on 60 days and it returns to 21, not to the beginning. Exact-match grading on production means one word out of place is *wrong*, and charging a year of progress for that teaches nothing. |
| **Days are days** | Intervals land on the start of a scheduling day, not 24 hours later — so a card finished at 23:59 does not come back at 23:59 tomorrow. The day rolls over at 04:00, because that is when this reader actually stops reading. |
| **Early answers move nothing** | The interval is the claim being tested. A card that graduated onto one day an hour ago has not survived a day, so answering it now can neither promote nor demote it. |
| **A session ends when it is finished** | Not after ten questions. The queue runs until it is empty and tells you how many cards are left; the closing screen reports what *graduated*, because "8 / 10" is a fact about tapping. |
| **Endless training** | A second mode over every card you have met, which deliberately **schedules nothing** — practice with no consequences for your intervals. |

### 🗂 The vocabulary workshop

Not a place to browse — a place to fix things. Cards fold into words and sentences with
counts, can be searched by text or meaning, edited when the translation was wrong,
reset back to new, or deleted. Each card shows where it was collected, how often you
looked it up again, and exactly where it stands in the schedule.

---

## How it fits together

```mermaid
graph TB
    subgraph device["📱 iPhone — SwiftUI"]
        R["Reader<br/>書庫 · 已下載"]
        P["Practice<br/>練習 · 單字庫"]
        V["Vision OCR"]
        T["Apple Translation"]
        O["Offline stores<br/>chapters · pending writes"]
        R --- V
        R --- T
        R --- O
        P --- O
    end

    subgraph server["🐳 docker compose — on your Mac"]
        API["FastAPI<br/>catalog · cards · scheduler"]
        DB[("PostgreSQL<br/>progress · cards · reviews")]
        W["Comprehension worker"]
        API --- DB
        W --- DB
    end

    LIB[("📁 Your manga folder<br/>read-only bind mount")]
    LLM["Claude<br/>Haiku 4.5 · Sonnet 5"]

    device -->|"HTTP"| API
    API -->|"scan · serve pages"| LIB
    W --> LLM
```

Three deliberate choices are visible in that picture:

1. **The folder is the source of truth, not a database.** The catalog is scanned into
   memory and rebuilt on demand; Postgres holds only what cannot be reconstructed from
   the folder — progress, cards, and answers. See
   [ADR 0001](docs/adr/0001-scan-and-serve-catalog-not-db-first.md).
2. **The fast paths never leave the phone.** OCR and translation are on-device, so the
   part of the loop you run dozens of times per chapter has no latency and no bill.
3. **The LLM is a background worker, not a blocking call.** Explanations are enqueued
   and written by a worker that reads the page from the library itself, so the reader is
   never waiting on a model.

---

## Getting started

### 1. The backend

```bash
# A gitignored .env at the repo root supplies the machine-specific bits.
cat > .env <<'EOF'
MANGA_LIBRARY_PATH=/absolute/path/to/your/manga
POSTGRES_PASSWORD=choose-something
DATABASE_URL=postgresql+psycopg://vista:choose-something@postgres:5432/vista
ANTHROPIC_API_KEY=sk-ant-...        # only needed for deeper explanations
EOF

docker compose up -d api postgres
curl localhost:8000/healthz          # → comic and chapter counts
```

The library is bind-mounted **read-only**, so the backend can never modify your files.
`MANGA_LIBRARY_PATH` and every secret live only in that gitignored `.env` — never in a
committed file.

**Expected folder shape** (three levels, natural-sorted pages):

```text
library/
└── some-comic/
    ├── cover.jpg              # optional — falls back to the first page
    └── 01-chapter-title/
        ├── 001.jpg
        └── 002.jpg
```

### 2. The app

```bash
open vista_comic/vista_comic.xcodeproj   # Xcode → run on a device or simulator
```

The UI follows the device language: English keys with Traditional Chinese
(繁體中文) translations, so the tabs read **書庫 · 已下載 · 練習 · 單字庫**.

### 3. Tests

```bash
cd backend && pytest                                  # 275 tests
xcodebuild test -scheme vista_comic \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:vista_comicTests                      # 541 tests
```

### Reading away from home

The backend is meant to run on your own Mac. To reach it from outside the house,
[`docs/moving-the-server.md`](docs/moving-the-server.md) and
[ADR 0005](docs/adr/0005-cloudflare-tunnel-for-public-connectivity.md) cover the
Cloudflare Tunnel + Access setup used here.

---

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| App | SwiftUI, iOS 18.1+ | Native, and the framework the project exists partly to learn |
| OCR | Vision (on device) | Private, free, works offline; fixed to `vi-VN` in v1 behind an `OCRRecognizer` protocol |
| Translation | Translation framework (on device) | Instant enough to use mid-sentence |
| API | FastAPI · Python 3.12 | Small, typed, fast to iterate on |
| Store | PostgreSQL · SQLAlchemy 2.0 · Alembic | Only for state the folder cannot hold; migrations own the schema |
| LLM | `anthropic` SDK — Haiku 4.5, Sonnet 5 | Two tiers so depth is opt-in and cost is bounded |
| Deployment | docker compose | One command, two services, your folder mounted read-only |

## Project layout

```text
vista_comic/          The iOS app
  Features/
    Favourite/        書庫 — library and chapter browsing
    ComicPage/        The reader: selection, zoom, OCR/translate sheet
    ChapterPage/      Chapter listing
    Downloads/        已下載 — offline chapters
    Study/            練習 + 單字庫 — cards, questions, scheduler
  Networking/         Repositories, OCR, translation, offline queues
  Shared/             Theme, fonts, shared sections
backend/
  app/                FastAPI app, scanner, stores, scheduler, worker
  alembic/            Migrations — the schema's owner
  tests/              275 pytest tests
docs/
  api-contract.md     API shape + folder format
  adr/                Architectural decisions, with the reasoning kept
  agents/             How the AI skills consume the tracker and domain docs
.scratch/<feature>/   Live specs and tickets — the current source of truth
```

## Status

Milestones M1–M10 are merged: shared UI foundation, library and chapter experience, the
reader, the local backend, OCR selection and recognition, tab navigation,
OCR-to-translation, LLM comprehension, and the comprehension response UX. Since then,
shipped as ticket-driven efforts: Alembic adoption, reader page prefetch, reader zoom,
offline download, and the vocabulary review system through stage 6 (Anki-style
scheduling, four question types, offline answering, and the settings behind them).

**Next up** — the game layer (stage 7) is parked partway through design: XP weighted
towards review, a two-tier "today is done" marker, and a pet that grows instead of
levels. Streaks were cut deliberately. It stopped on artwork, which is not a
programming problem. Longer range, profile and cross-device sync remain the one major
direction with no milestone yet.

[`ROADMAP.md`](ROADMAP.md) records milestone history and known issues;
[`.scratch/<feature>/`](.scratch/) holds the live specs and tickets and is the source of
truth for what is in progress. [`CLAUDE.md`](CLAUDE.md) is the collaboration and
engineering contract for AI agents working in this repo, and
[`CONTEXT.md`](CONTEXT.md) defines the backend's domain vocabulary.

---

<sub>A personal project, built in small verifiable increments. The manga library is
whatever is already on the owner's disk; nothing is bundled or distributed with the
app.</sub>
