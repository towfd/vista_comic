Type: prototype
Status: resolved

# Reader result screen states after the split

## Question

M9's result screen was designed around a single verdict delivered once: a persistent banner reading ☁️ blue "雲端深度解釋", 📱 gray "離線模式・僅逐字翻譯", or ⚠️ orange "內容政策・僅提供翻譯", always shown before any content. Splitting the wait in two (ticket 02) breaks that model — the screen now *starts* in a state M9 had no name for (translation present, explanation genuinely still coming) and may transition out of it while the reader watches.

Prototype the result screen across its new states and decide what the reader sees:

- Translation shown, explanation in flight — what signals "more is coming" without implying something is broken?
- Explanation arrives while the reader is still there — how does it appear? Does it animate/expand in place, and does the translation get replaced by the cloud's own version?
- Explanation fails or is declined while the reader is still there.
- What survives of the three-banner scheme, if anything? A banner that must now change mid-view is a different thing from a verdict stamped once.
- Where does M9's "request a stronger explanation" (Sonnet upgrade) action live now — still here, moved to the History detail view, or both?

Use `/prototype` to make something concrete to react to rather than deciding this in prose.

## Constraints from ticket 07

[Background comprehension task ownership and observation](07-background-task-ownership.md) put the call on a backend queue drained by a restart-recovering worker, observed by polling.

- **No "waited too long" state is needed.** Because the worker reclaims orphaned rows after a restart, `pending` genuinely means "still running" — the screen never has to guess whether a call silently died. This was the explicit reason that execution model was chosen over `BackgroundTasks`, so don't reintroduce a timeout affordance here.
- **The screen polls its own record while that record is pending**, rather than awaiting a `Task` it started. "Explanation arrives while the reader is still there" is therefore a poll landing, with the polling interval visible as perceived latency — prototype with a realistic interval, not an instant transition.
- **Queueing is now a visible reality.** With a concurrency cap of 3, translating several selections in a row means later ones sit in a queue before they even start. Decide whether "queued" is shown differently from "being explained", or whether one state covers both.
- **The wait can now be genuinely long, and leaving is safe.** The reader can background the app or close the reader and the work still completes. If the screen currently implies "stay here or lose it", that framing is wrong.

## Constraints from ticket 08

[History record data model and API shape](08-history-record-data-model.md) fixed the data this screen renders.

- **Five status values to render, not three banners:** `pending`, `running`, `ok`, `declined`, `failed`. `pending` vs `running` is deliberately left visible in the data so this ticket can choose whether "queued" and "being explained" look different — the data layer does not force either way.
- **The translation shown is `cloudTranslation` when present, else `translatedText`.** That precedence is decided; what this ticket owns is how the swap *reads* to someone watching — does the text visibly change, is it animated, is the cloud version marked as such, and is losing the device wording ever surprising. Both strings are on the record, so any of those is implementable.
- **A new failure case at the very start:** `POST /comprehensions` returns 429 when the daily cap is spent, and **no record is created at all**. The reader still has their on-device translation, but there is nothing in History and nothing to retry. Decide what that looks like — it is the one outcome where the auto-record promise silently does not hold.
- **The screen polls `GET /comprehensions/{id}`**, and marks read with `PATCH /comprehensions/{id} { "isRead": true }` when the explanation lands while the reader is watching (ticket 05).
- **Where M9's Sonnet upgrade action lives is still this ticket's call** — but note it is now necessarily another enqueue, subject to the same queue and quota, not an instant in-place re-request. `upgradeComprehension`'s current synchronous shape does not survive; see [12](12-client-removal-boundary.md).

## Answer

Three whole-screen variants were drawn and compared in
[Result screen variants](../assets/09-result-screen-variants.md) — the concrete
artifact standing in for the `/prototype` UI branch's usual runnable route,
because this project forbids touching the codebase before the implement phase.
A fourth shape — dismissing the sheet immediately and sending everything to
History — was excluded before drawing, since ticket 05 already confirmed the
live fill-in as desired behaviour.

**Variant B wins: the status lives where the content will appear.**

### M9's verdict banner is deleted, and its job is split in two

The capsule at `ComicView.swift:1247-1269` was a verdict stamped once, before
any content. That premise is gone — the screen now starts in a state M9 had no
name for and transitions out of it while the reader watches, and a banner that
changes meaning mid-view is a different object from a verdict. Its two jobs go
to two different places:

- **"Is more coming?"** goes to a `深度解釋` section placed where the
  explanation will actually render, so the waiting indicator stands exactly
  where the answer will appear and the reader's eye never travels.
- **"Which translation am I reading?"** becomes a small provenance chip on the
  Translation column itself — `📱` while it is the on-device text, flipping to
  `☁️` when the cloud version replaces it. This is what makes ticket 08's
  cloud-wins display precedence legible: the text changing under the reader is
  explained at the moment and the place it happens, rather than by a banner
  somewhere above it.

Variant A (keep the capsule, let it mutate) was rejected for making one element
carry progress and verdict across its lifetime while sitting far from what it
describes. Variant C (collapse the explanation into a tap-to-expand drawer) was
rejected for hiding the expensive thing this whole feature exists to deliver,
even though its never-rearranges property and its shared vocabulary with the
History tab were genuinely attractive.

### The `深度解釋` box, state by state

| `status` | What the box shows |
| --- | --- |
| `pending` / `running` | "解釋產生中，可以先離開／完成後會出現在歷史紀錄" |
| `ok` | the box is replaced by the three note sections |
| `failed` | "沒能取得深度解釋" + a **retry** button |
| `declined` | "這段內容模型不提供解釋" — **no retry button** |
| 429 at enqueue | "今日次數已用完，這筆不會存進歷史紀錄" |

**`pending` and `running` deliberately share one message.** With a concurrency
cap of 3, a single reader only ever queues by selecting a fourth passage in
quick succession, and "there are 2 ahead of you" is an implementation detail
rather than something the reader can act on. The distinction stays in the data
(ticket 08) for the History tab and for debugging; this screen just does not use it.

**`declined` and `failed` stay distinguishable, but through copy and available
actions rather than colour.** M9 made them visually distinct on purpose so a
content-policy decline is never mistaken for a connectivity problem
(`ComicView.swift:1252-1255`), and that intent survives. Retrying a decline
would spend quota to receive the same verdict, so the button is simply absent —
the distinction is carried by what the reader *can do*, which is the more honest
signal.

**Two further states, added by [ticket 12](12-client-removal-boundary.md) after this ticket was resolved:**

- **The on-device translation itself fails** (e.g. the language pack isn't downloaded). No record is created and the backend is never called — the existing translation-failure UI with its retry stands unchanged (`ComicView.swift:1281-1311`). There is no `深度解釋` box at all, because there is no translation to attach one to.
- **The enqueue fails transiently** (network/server, not 429). The translation is shown as normal, but nothing was recorded — same slot as the 429 message, different copy, and **this one does offer a retry** since retrying can actually help. The 429 case does not, following the same "distinguish by whether retrying can possibly help" rule this ticket applied to `declined` vs `failed`.

**The 429 case is the one place the feature's promise does not hold.** Ticket 08
has `POST /comprehensions` return 429 with no record created, so the reader
keeps their on-device translation but there is nothing in History and nothing to
retry. It renders inline in the same slot as the box, rather than as an alert,
so it reads as "this is the outcome" rather than "something went wrong".

### The Sonnet upgrade action is removed and replaced by a pre-selected model tier

`upgradeComprehension` (`ComicView.swift:1336-1361`) is a synchronous in-place
re-request that swaps the displayed result and alerts on failure. That shape
cannot survive: an upgrade is now another enqueue, with the same queue wait and
the same quota cost. Rebuilding it as an async per-record re-request would put a
second multi-minute wait on the exact screen this map exists to stop blocking.

Instead, **the model tier becomes a per-device preference chosen before
translating**, as a picker sitting alongside the existing language picker:

```
Translate to   [ 繁體中文 ▾ ]
解釋深度        [ 標準 ▾ ]
```

This has an exact precedent to copy rather than inventing a pattern: this app has
**no settings screen at all**, and its only preference — `LastUsedTargetLanguage`
(`ComicView.swift:1478-1484`) — is a `UserDefaults`-backed string set by an
inline picker at the point of use, documented there as "a lightweight per-device
UI preference". A dedicated settings screen was considered and rejected as scope
expansion for a map whose destination is a comprehension-UX spec.

The trade this accepts: the tier is now **global**, so choosing the stronger
model applies to every call rather than to the few results worth deepening.
Sonnet 5 is materially more expensive than Haiku 4.5 — **the spec must state the
actual multiplier, checked rather than assumed, next to the 300/day cap**, since
the cost profile of the whole feature now moves with one picker.

### Observation behaviour

The screen polls `GET /comprehensions/{id}` while its record is `pending` or
`running`, and issues `PATCH /comprehensions/{id} { "isRead": true }` when the
explanation lands while the reader is still watching (ticket 05). Polling
interval is left to implementation, but the prototype's premise is that a landing
is a poll result and therefore not instantaneous.

## Comments

Resolved via a `/prototype` + `/grilling` session on 2026-08-05. The variants
asset is at
[`assets/09-result-screen-variants.md`](../assets/09-result-screen-variants.md).

Consequences pushed onto other tickets:

- **[08](08-history-record-data-model.md)** — the model tier must be stored on the
  row and accepted in the enqueue body, because the worker runs minutes later and
  has to know which model to call. This was a genuine gap in 08.
- **[10](10-history-tab-ui.md)** — the History detail view does **not** get an
  upgrade action; the tier is a reader-side preference set before translating.
- **[12](12-client-removal-boundary.md)** — unblocked. `upgradeComprehension` and
  its alert state are deleted outright rather than rewritten.
