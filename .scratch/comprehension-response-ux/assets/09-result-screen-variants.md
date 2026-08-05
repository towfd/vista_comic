# Result screen variants — asset for ticket 09

> **Verdict: Variant B.** See
> [Reader result screen states after the split](../issues/09-reader-result-screen-states.md)
> for the reasoning and the full resolution. Four things changed after the
> variants below were drawn and reacted to:
>
> 1. A second inline picker joins the language picker — `解釋深度 [ 標準 ▾ ]` —
>    replacing M9's per-result "request a stronger explanation" action entirely.
>    Every variant's `[ ✨ 請求更深入的解釋 ]` button is therefore **gone**.
> 2. `declined` gets **no retry button**; only `failed` does.
> 3. `pending` and `running` share one message, so B's "no obvious place for
>    the queue position" cost was accepted rather than solved.
> 4. The quota-exhausted message renders inline in the same slot as the
>    `深度解釋` box, not as an alert.


Text mockups standing in for the runnable prototype the `/prototype` UI branch
would normally produce. This project forbids touching the codebase before the
implement phase, so the concrete artifact to react to is drawn rather than run.

Sample content throughout: source `お前、なかなかやるじゃないか`, device
translation `你這家伙，還挺有兩下子的嘛`, cloud translation `你小子，挺有一套的嘛`.

Baseline for comparison — **M9 as shipped today** (`ComicView.swift:1203-1235`):
one verdict capsule stamped once, then Original/Translation side by side, then
the three note columns, then upgrade, then Save. Everything appears together
after one long wait. Save is removed by ticket 03, so it is gone from every
variant below.

---

## Variant A — the banner survives, but it becomes a live status strip

The M9 capsule stays exactly where it is and keeps its job of answering
"what am I looking at" before any content — but it now mutates as the record
moves through `pending` → `running` → terminal.

```
┌──────────────────────────────────────────────┐
│                Selected text            Done │
├──────────────────────────────────────────────┤
│  ┌────────────────────────────────────────┐  │
│  │          [ crop of the selection ]     │  │
│  └────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────┐  │
│  │ お前、なかなかやるじゃないか            │  │
│  └────────────────────────────────────────┘  │
│  ────────────────────────────────────────    │
│  Translate to   [ 繁體中文 ▾ ]                │
│  ┌────────────────────────────────────────┐  │
│  │                Translate               │  │
│  └────────────────────────────────────────┘  │
│                                              │
│   ( ⏳ 排隊中，前面還有 2 筆 )                 │  ← mutates
│                                              │
│   Original            │  Translation         │
│   お前、なかなか       │  你這家伙，還挺有     │
│   やるじゃないか       │  兩下子的嘛           │
└──────────────────────────────────────────────┘
```

The capsule then walks through:

```
   ( ⏳ 排隊中，前面還有 2 筆 )        status = pending
   ( ☁️ 解釋產生中…            )        status = running
   ( ☁️ 雲端深度解釋           )        status = ok        → notes appear below
   ( ⚠️ 內容政策・僅提供翻譯    )        status = declined
   ( 📱 僅逐字翻譯・可重試      )        status = failed    → retry button below
```

On `ok`, the translation column swaps to the cloud wording and the notes
expand in below it:

```
│   Original            │  Translation         │
│   お前、なかなか       │  你小子，挺有一套     │
│   やるじゃないか       │  的嘛                 │
│                                              │
│   Grammar notes                              │
│   なかなか + 否定形…                          │
│   Context notes                              │
│   對手在打鬥中認可主角實力的場面…              │
│   Tone & register                            │
│   粗魯但帶敬意的男性口吻…                      │
│                                              │
│   [ ✨ Request deeper explanation ]           │
```

**What this bets on:** the reader keeps one place to look for "where is this
up to", and the M9 vocabulary the reader already learned stays intact.

**What it costs:** the capsule now means two different things over its
lifetime — progress, then verdict — and it sits at the top while the thing it
describes appears at the bottom. The translation text also changes with no
local explanation for why.

---

## Variant B — no banner; the status lives where the content will appear

The capsule is deleted. The translation is shown plainly and immediately, and
a labelled `深度解釋` section below it holds its own state — spinner, then
content, then failure message. Provenance moves from a global banner to a
small chip on the column it actually describes.

```
┌──────────────────────────────────────────────┐
│                Selected text            Done │
├──────────────────────────────────────────────┤
│  ┌────────────────────────────────────────┐  │
│  │          [ crop of the selection ]     │  │
│  └────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────┐  │
│  │ お前、なかなかやるじゃないか            │  │
│  └────────────────────────────────────────┘  │
│  ────────────────────────────────────────    │
│  Translate to   [ 繁體中文 ▾ ]                │
│  ┌────────────────────────────────────────┐  │
│  │                Translate               │  │
│  └────────────────────────────────────────┘  │
│                                              │
│   Original            │  Translation  📱     │
│   お前、なかなか       │  你這家伙，還挺有     │
│   やるじゃないか       │  兩下子的嘛           │
│                                              │
│   深度解釋                                    │
│   ┌──────────────────────────────────────┐   │
│   │  ◌  解釋產生中，可以先離開            │   │
│   │     完成後會出現在歷史紀錄            │   │
│   └──────────────────────────────────────┘   │
└──────────────────────────────────────────────┘
```

When it lands, that box is replaced by the notes, and the Translation column's
chip flips `📱` → `☁️`:

```
│   Original            │  Translation  ☁️     │
│   お前、なかなか       │  你小子，挺有一套     │
│   やるじゃないか       │  的嘛                 │
│                                              │
│   深度解釋                                    │
│   Grammar notes                              │
│   なかなか + 否定形…                          │
│   Context notes                              │
│   對手在打鬥中認可主角實力的場面…              │
│   Tone & register                            │
│   粗魯但帶敬意的男性口吻…                      │
│                                              │
│   [ ✨ 請求更深入的解釋 ]                      │
```

Failure and decline replace the same box, in place:

```
│   深度解釋                                    │
│   ┌──────────────────────────────────────┐   │
│   │  這段內容沒有取得深度解釋。            │   │
│   │  逐字翻譯仍然可用。      [ 重試 ]      │   │
│   └──────────────────────────────────────┘   │
```

**What this bets on:** the reader's eye never has to travel; the waiting
indicator is standing exactly where the answer will be, and the chip explains
the translation swap at the moment and place it happens.

**What it costs:** loses M9's "verdict before content" ordering, and
`pending` vs `running` has nowhere obvious to show — the box would say the
same thing for both unless the copy changes.

---

## Variant C — the explanation is a secondary drawer

The translation is treated as the whole answer. The explanation arrives as a
collapsed row pinned under it, marked with a dot when it lands, and expands
only on tap. The visible layout never rearranges itself while the reader reads.

```
┌──────────────────────────────────────────────┐
│                Selected text            Done │
├──────────────────────────────────────────────┤
│  ┌────────────────────────────────────────┐  │
│  │          [ crop of the selection ]     │  │
│  └────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────┐  │
│  │ お前、なかなかやるじゃないか            │  │
│  └────────────────────────────────────────┘  │
│  ────────────────────────────────────────    │
│  Translate to   [ 繁體中文 ▾ ]                │
│  ┌────────────────────────────────────────┐  │
│  │                Translate               │  │
│  └────────────────────────────────────────┘  │
│                                              │
│   Original            │  Translation         │
│   お前、なかなか       │  你這家伙，還挺有     │
│   やるじゃないか       │  兩下子的嘛           │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │  深度解釋              產生中…      ◌  │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

Landed, still collapsed — nothing has moved, one dot has appeared:

```
│  ┌────────────────────────────────────────┐  │
│  │  深度解釋                      ●    ›  │  │
│  └────────────────────────────────────────┘  │
```

Tapped:

```
│  ┌────────────────────────────────────────┐  │
│  │  深度解釋                           ⌄  │  │
│  ├────────────────────────────────────────┤  │
│  │  Grammar notes                         │  │
│  │  なかなか + 否定形…                     │  │
│  │  Context notes                         │  │
│  │  對手在打鬥中認可主角實力的場面…         │  │
│  │  Tone & register                       │  │
│  │  粗魯但帶敬意的男性口吻…                 │  │
│  │  [ ✨ 請求更深入的解釋 ]                 │  │
│  └────────────────────────────────────────┘  │
```

**What this bets on:** nothing ever moves under the reader's eyes, and the
row's collapsed/expanded/dot vocabulary is the same one the History tab needs
anyway — the two screens would teach each other.

**What it costs:** the explanation is the expensive thing this whole feature
exists for, and this variant hides it behind a tap by default. Also makes the
translation swap awkward — either it happens silently in a section with no
status of its own, or it doesn't happen at all in the reader.

---

## The state every variant has to answer for: quota exhausted

Ticket 08 decided `POST /comprehensions` returns 429 with **no record
created**. The reader still gets their on-device translation, but nothing goes
to History and there is nothing to retry — the only case where the
"every translate is recorded" promise silently does not hold.

```
│   Original            │  Translation  📱     │
│   お前、なかなか       │  你這家伙，還挺有     │
│   やるじゃないか       │  兩下子的嘛           │
│                                              │
│   ┌──────────────────────────────────────┐   │
│   │  今日的雲端解釋次數已用完，            │   │
│   │  這筆不會存進歷史紀錄。                │   │
│   └──────────────────────────────────────┘   │
```
