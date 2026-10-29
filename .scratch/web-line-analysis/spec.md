Status: ready-for-agent

# Web line analysis: a word-by-word breakdown of a tapped bubble

## Problem Statement

The web reader shows a bubble's reviewed translation and can send the whole line to 收卡 (`web-bubble-collect`). What it cannot do is explain the line: which Vietnamese words make it up, what each one means here, which are Sino-Vietnamese, and why the translation reads the way it does. Collecting a single word means working it out elsewhere and typing it by hand. Vietnamese makes this harder than it looks — a space separates syllables, not words, so `thanh toán` is one word, and the pronouns and sentence-final particles that carry the most meaning are the easiest to miss.

## Solution

The bubble translation card gains a 深入查詢 button (only for a bubble that has a translation). It opens a line-analysis panel in the reader that asks Claude — Sonnet 5.5 by default, Opus 5.5 or Fable 5.1 on request — to break the line into words, explained against the reviewed translation rather than re-translating it. The result lists each word with its meaning in this line, part of speech, Sino-Vietnamese characters when there are any, and a short note when one helps, followed by a grammar note and a tone note. Each word has an 加入 button that opens 收卡 filled with the word and its meaning, on top of the analysis panel, which is still there afterwards.

The backend runs the call in the background and keeps the result, so a line already analysed with a model opens instantly and is paid for once.

## User Stories

### Asking

1. As a reader, I want a 深入查詢 button on a bubble's translation card, so I can study the line I am looking at.
2. As a reader, I want the button only on bubbles that have a reviewed translation, so every analysis explains a translation I trust.
3. As a reader, I want the translation card to close and an analysis panel to open where 收卡 opens (beside the page on a wide window, along the bottom on a phone).
4. As a reader, I want to choose Sonnet 5.5, Opus 5.5 or Fable 5.1 in the panel, defaulting to Sonnet, and have my last choice remembered in this browser.

### Waiting

5. As a reader, I want to see that the analysis is running, with the model and how long it has been waiting, because Fable can take a minute or more.
6. As a reader, I want to be able to close the panel and keep reading while it runs, and find the result when I open the same bubble again.
7. As a reader, when the analysis fails — an error, a refusal, an unusable answer, or the server restarting mid-call — I want to be told which, and a 重試 button; a failure is not kept as a result and does not use up the day's allowance.

### Reading the result

8. As a reader, I want every word of the line in reading order, multi-syllable words and set phrases kept together, including pronouns, particles and sentence-final words.
9. As a reader, I want each word shown in upper case with its meaning in this line, worded to match the reviewed translation, and its part of speech.
10. As a reader, I want the Sino-Vietnamese characters next to a word when it is one (`VIỆN PHÍ` → 院費), and nothing when it is not or the model is unsure.
11. As a reader, I want a one-line note under a word only when it adds something — who a pronoun points to and the attitude it shows, a particle's nuance, why the translation words it this way.
12. As a reader, I want a short grammar note and a tone note after the words.
13. As a reader, I want names from the work's name table glossed with their official names, matching the batch translation.

### Reusing and refreshing

14. As a reader, I want a line I already analysed with a model to open at once without another call, wherever the same line appears.
15. As a reader, I want switching models to show that model's stored result if there is one, and otherwise run it, keeping the others.
16. As a reader, I want a 重新查詢 button that runs the current model again and replaces its stored result, after a reminder that it costs another call.
17. As a reader, I want a line whose translation has since been re-done to be analysed afresh, not shown an analysis of the old translation.

### Collecting a word

18. As a reader, I want an 加入 button on each word that opens 收卡 on top of the analysis panel, filled with the word in upper case and its meaning — with the characters in brackets when it has them (`住院費（院費）`) — and the bubble's page.
19. As a reader, I want 收卡 to behave exactly as it does for a bubble line: editable, replaced if something was typed, added with 加入單字 / 加入句子.
20. As a reader, I want the analysis panel still open, at the same scroll position, after a card is added or 收卡 is collapsed, so I can collect the next word.

## Implementation Decisions

### What is and is not touched

- Backend: a new line-analysis resource, its table and migration, its Claude client, and its worker. The existing `/comprehensions` resource, its prompt and its worker are not changed. The global daily cap (`comprehend_usage_store`, 300/day) is shared.
- Web: the reader's translation card, a new analysis panel and its store, the API client. The collecting store is reused through its existing fill action (`fillFromBubble`).
- iOS: nothing.

### The resource (API contract)

- `POST /line-analyses` with `{ sourceText, translation, model, names, refresh }`.
  - `model` is `sonnet` | `opus` | `fable`; the backend maps it to `claude-sonnet-5-5` / `claude-opus-5-5` / `claude-fable-5-1`. The client never sends a model ID.
  - `names` is the name-table entries relevant to this line: `{ source, target }` pairs. Context only — not part of the identity of an analysis.
  - The identity of an analysis is **(the source text's normalised key, the translation as sent, the model)**. The source key reuses the backend's existing normalisation, so case and spacing do not split one line into several.
  - A `done` or `pending` analysis with that identity is returned as it is, with no call and no cap reservation — unless `refresh` is true, which re-queues it (a cap reservation, the old result discarded).
  - A `failed` one is re-queued (a reservation), as is a new one (created `pending`, a reservation). An exhausted cap is a 429 and nothing is created or re-queued.
- `GET /line-analyses/{id}` returns one analysis; the panel polls it every 2 seconds while it is `pending`.
- Response shape: `{ id, status: pending|done|failed, model, sourceText, translation, failure?: error|refused|invalid|interrupted, result?: { words: [{ text, meaning, partOfSpeech, hanViet, note }], grammar, tone }, updatedAt }`.

### The worker

- The row is the queue, the same shape as the comprehension worker (a daemon thread around a synchronous, directly testable `process_pending`; a small concurrency limit; orphaned claims released at startup and marked `interrupted`).
- A run that does not end in a valid result marks the row `failed` with its reason and refunds its reservation.

### The Claude call

- Structured output via `output_config.format` with a JSON schema — not forced tool use, which these three models reject. The schema: `words` (array of objects with `text`, `meaning`, `partOfSpeech`, `hanViet`, `note`, all required strings, `additionalProperties: false`), `grammar`, `tone`. `partOfSpeech` is an enum: 名詞 動詞 形容詞 副詞 代名詞 介詞 連詞 助詞 語氣詞 數詞 量詞 感嘆詞 狀聲詞 人名 地名 片語.
- The prompt (system), agreed in grilling:

  > You are a Vietnamese tutor for a reader in Taiwan who is learning Vietnamese by reading Korean webtoons in Vietnamese translation. Write every explanation in Traditional Chinese as used in Taiwan.
  >
  > You get one speech-bubble line in Vietnamese and its reviewed Traditional Chinese translation. The translation is final: do not retranslate, correct it, or offer alternatives. Explain the Vietnamese so the reader can see how it becomes that translation.
  >
  > Split the line into words, not syllables. Vietnamese puts a space between every syllable, so a multi-syllable word (thanh toán, viện phí) is one unit, and a fixed expression that carries one meaning stays together. A name from the name table is one unit, glossed with its official name.
  >
  > Cover every unit in reading order, including pronouns, particles and sentence-final words (à, nhé, đi) — those are where a learner gets lost.
  >
  > For each unit: text exactly as written in the line; meaning in this line, worded to match the given translation; partOfSpeech from the list; hanViet — the Traditional Chinese characters if it is a Sino-Vietnamese word (viện phí → 院費), empty if it is not or you are not sure; note — one short sentence only when it helps (who a pronoun points to and the relationship or attitude it shows, a particle's nuance, why the translation words it this way), otherwise empty.
  >
  > Then grammar: 2–4 sentences on how the line is built, referring to the units; and tone: 1–2 sentences on emotion, register and politeness.

- The user message carries the name table, the line, and the translation. No image.
- Adaptive thinking (the default on all three); effort and `max_tokens` are tuned in ticket 02. Streaming with the final-message helper so a long Fable call is not cut by the SDK's HTTP timeout.
- A `refusal` stop reason is a `failed`/`refused` row. Server-side refusal fallback (`fallbacks: "default"`) is used if the installed SDK supports it; otherwise not, and noted.
- After parsing, the backend checks the result is usable: at least one word, and every word's `text` found in the line (ignoring case and spacing). Otherwise `failed`/`invalid`.
- The API key comes from the existing config (never logged).

### The web side

- The name table comes from `/ocr-data/<folder>/bible.json`; the reader sends only the entries whose source name or an alias appears in the line.
- An analysis store owns the panel: open/closed, the bubble it is for, the chosen model (remembered in `localStorage`, read and written defensively), the current analysis, polling, and the elapsed time. The panel renders it.
- The panel sits where 收卡 does, below it in stacking order and clear of the collapsed ＋收卡 button; 收卡 opens on top of it and closing 收卡 reveals it unchanged.
- A word's 加入 calls the collecting store's existing `fillFromBubble` with the word, `meaning（hanViet）` or `meaning`, and the bubble's page. The word is upper-cased by the same rule as a bubble line.

## Testing Decisions

- Backend (pytest, existing seams): the resource's identity and reuse rules, `refresh`, failed re-queue, cap reservation and refund on every path; the worker's `process_pending` with a stubbed client — success, error, refusal, invalid result, orphan release; the request the client builds (model mapping, schema, prompt inputs) without calling Claude; the migration test.
- Web (vitest): the analysis store — opening, model choice and its persistence, polling until done/failed, reuse on reopen, refresh, failure and retry; the name filter; the word-to-收卡 fill text.
- No component or browser tests; a device checklist is handed to the developer (CLAUDE.md, Verification rule 4).
- Real Claude calls happen only in ticket 02, a handful of lines, with the developer's go-ahead on the cost.

## Out of Scope

- A history or list page of past analyses; editing an analysis.
- Target languages other than Traditional Chinese.
- Analysing a bubble without a reviewed translation.
- Sending the page image.
- Opus fast mode (can be added later as a fourth choice).
- Changes to `/comprehensions`, its prompt, or iOS.
- Marking words already in the deck.

## Further Notes

- Prices at spec time ($/MTok in/out): Sonnet 5.5 2/10, Opus 5.5 4/20, Fable 5.1 10/50.
- **Measured in ticket 02** (six real lines, 2026-10-29): about 1,250–1,400 input and 260–1,800 output tokens a line, thinking included. Per line on average: Sonnet US$0.011 (6–17 s), Opus US$0.025 (4–19 s), Fable US$0.069 (6–24 s). No refusals, every answer usable. Settings kept: `max_tokens` 8000 (the most used was 1,784), effort at each model's default.
- The prompt's `hanViet` instruction gained one clause after ticket 02 (Sonnet was giving native words such as yêu, mới, mùa characters): *only give characters when every syllable is Sino-Vietnamese and you know the standard characters; native words such as có, yêu, mới, mùa stay empty.* Re-checked on Sonnet: those are gone; `có thể → 可體` remains.
- Web requests pass through Cloudflare, which drops a request after about 100 seconds — the reason for the background run and polling.
- Deploying this needs the `api` container rebuilt as well as `web`; the API key is already in the server's `.env`.
