Status: done (2026-11-19) — tickets 01–02 merged in #162 and #163; phone check confirmed by the owner

# Card audio: one Vietnamese recording per card, made outside this repo

## Problem Statement

Raised by the repo owner, 2026-11-18, in the Text-To-Speech session: 「我打算選用 google cloud 的方式去將我現在 vista-comic 那邊資料庫的字卡都加上 tts」「我們這邊只要把音檔生出來就好了……然後我前端再把他接上去就好」.

A card holds its Vietnamese source text and a translation, and no sound. The owner wants to hear every card.

## Solution

The work is split between two repos:

- **The Text-To-Speech repo** (`/home/agent/Documents/Text-To-Speech`) makes the audio. The writer, an MCP server run by a global agent (`~/.claude/agents/card-tts.md`), reads the cards, sends their source text to Google Cloud Text-to-Speech, and writes one MP3 per card into a new `card_audio` table in this repo's Postgres. It runs when the owner asks, not on a schedule: new and corrected cards get their audio on the next run.
- **This repo** owns the table and everything that reads it: the migration that creates `card_audio`, a route that serves a card's audio, and the clients that play it.

The writer never changes `learning_card` and never creates tables. A dedicated Postgres role enforces this (see "The writer's role").

## Decisions

Made with the owner on 2026-11-18 in the Text-To-Speech session.

| Question | Decision |
|---|---|
| Where the audio lives | In this repo's Postgres, as bytes in a new table, not as files on disk. About 2.6 MB for today's 324 cards. |
| How many per card | Exactly one; `card_id` is the primary key. Slower playback comes from the client's playback rate, not from a second file. |
| Who creates the table | This repo, as an Alembic migration, so Alembic stays the only owner of the schema. |
| How the writer connects | As a dedicated role, `card_tts`, which can read three columns of `learning_card` and read, insert and update `card_audio`, and nothing else. |
| Voices | Google Chirp 3: HD `vi-VN-Chirp3-HD-Achernar` (female) for every card. Until 2026-11-19 odd ids got `vi-VN-Chirp3-HD-Enceladus` (male); the owner dropped it, and on 2026-11-19 those 163 rows were regenerated in place (same `card_id`, new `audio`, `voice` and `created_at`). Nothing changes on the read side. |
| Text sent to Google | The source text, lowercased. When it was sent in the comic's capitals, the recordings came out longer, and the owner preferred the lowercase ones. `card_audio.source_text` keeps the card's text exactly as it was, not lowercased, so it can be compared with the card directly. |
| Format | MP3 (`audio/mpeg`), which both iOS and browsers play. |
| Archived cards | Skipped by the writer. A card that is unarchived gets its audio on the next run. |

## The table

Create it in a migration after `b6e2f0c4a913` (today's head).

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `card_id` | `Integer` | no | Primary key. Foreign key to `learning_card.id` with `ON DELETE CASCADE`: a deleted card takes its audio with it, as it takes its reviews (`backend/app/db.py:279`). |
| `source_text` | `String` | no | The card's `source_text` at the moment the audio was made, unchanged. |
| `voice` | `String` | no | The Google voice name, e.g. `vi-VN-Chirp3-HD-Achernar`. |
| `mime_type` | `String` | no | `audio/mpeg` today. Serve it as the `Content-Type` rather than hard-coding one. |
| `audio` | `LargeBinary` (`bytea`) | no | The recording itself. |
| `created_at` | `DateTime(timezone=True)` | no | When the writer made it. |

Whether `backend/app/db.py` gets a matching model is up to this repo; the writer does not import anything from it.

**Stale audio.** When a card's source text is corrected (`PUT /cards/{card_id}/source-text`, `backend/app/main.py:1170`), its row still holds the old recording until the writer runs again. A row whose `source_text` differs from the card's is stale, and the card must be treated as having no audio. This repo may either compare the two on read or delete the row in the same transaction as the correction; the writer regenerates a missing row and a stale row alike.

## The writer's role

The owner runs this once, after the migration is deployed, in `psql` as the role that owns the tables. `\password` asks for the password at the prompt, so it is never written to a file:

```sql
CREATE ROLE card_tts LOGIN;
\password card_tts
GRANT SELECT (id, source_text, archived_at) ON learning_card TO card_tts;
GRANT SELECT, INSERT, UPDATE ON card_audio TO card_tts;
```

The writer never deletes: a row goes away when its card does, through the cascade, or when this repo deletes a stale one. If `card_audio` is ever dropped and created again (a downgrade and upgrade, say), the last `GRANT` has to be run again.

## Serving it (suggested)

`GET /cards/{card_id}/audio`:

- **200**, with `audio` as the body and `mime_type` as the `Content-Type`, when the card has a row and the row's `source_text` equals the card's.
- **404** when the card does not exist, has no row, or its row is stale.

The path is under `/cards`, so the web client's nginx already forwards it (`web/nginx.conf.template:14`).

Caching: the URL stays the same when the writer regenerates a card's audio, so a long `max-age` would keep playing the old recording after a correction. Use an `ETag` built from `card_id` and `created_at` (which changes on every regeneration) with `Cache-Control: no-cache`, so clients revalidate each time and download only when the audio has changed.

## Left to this repo

- Whether `LearningCardResponse` gains a field such as `hasAudio`, so a client knows which cards have audio without requesting each one and getting a 404. iOS caches that response as its deck snapshot, so a field added later is missing from older snapshots (`backend/app/models.py:271`).
- Where the play button goes, whether a session plays the audio automatically, and whether iOS keeps audio for offline use.
- The tickets.

## Out of scope

Generating audio from this repo, any Google credentials here, audio for text that is not a card (a speech bubble in the reader, for example), and a second voice per card.

## Contact

Questions about the writer or the table's shape: send a message to the Claude Code session named `text-to-speech` (its code is in `/home/agent/Documents/Text-To-Speech`). Once the writer is live, changing the table's shape means changing both repos, agreed with the owner first.

## Comments

2026-11-18, vista_comic session, decided with the owner after a screenshot preview of the play button:

| Question left to this repo | Decision |
|---|---|
| `hasAudio` on `LearningCardResponse` | Yes. True only when the card has a row **and** the row's `source_text` equals the card's, so a stale recording reads as no audio everywhere. |
| Stale audio after a source-text correction | Compared on read (in SQL), not deleted. The correction route is untouched; the writer overwrites the row on its next run. |
| Where the play button goes (web) | Practice: **only after answering** (option A), never on the question, because the recording is the answer. Beside 卡片 on a 整句題; on a 填空題, one beside 空格裡的字 (the answer word card's audio) and one beside 整句 (this card's). Card page: beside the source text. |
| Auto-play | No. Sound only on a press; a press while playing stops it. |
| A card without audio | Practice shows no button. The card page shows 「還沒有發音，下次產生發音時會補上。」 |
| iOS | Not now. The owner reads and practises on the web on both phones; the app can follow later. |

Tickets: `issues/01-store-and-serve-card-audio.md`, `issues/02-play-button-on-the-web.md`.
