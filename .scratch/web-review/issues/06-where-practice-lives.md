Type: grilling
Status: resolved

# Where practice lives

## Question

The web is three routes and no navigation: a library, a comic, a reader. Where does practice go, and how does the reader get to it?

Its route; what the library page shows to lead there, and whether that carries a count of what is due (which means fetching the deck before practice is ever opened); and whether a session is one route or the questions are addressable. This is the first thing on the web that is not about a comic, so it is also the first decision about a shell.

## Answer

**A top navigation bar reaches practice from everywhere but the reader; it carries the count of what is waiting; and practice opens on an overview, with the questions one press further in.**

**The shell.** The web gets its first: a bar across the top of the library, the comic page and practice, reading 書庫 · 練習. The reader does not show it and stays full-bleed. A link beside the library's heading was the smaller change and was declined — it leaves the comic page with no way to practice except back through the library, and every later section (the card library, part ⑤) would need its own links threaded in by hand.

```
┌────────────────────────────────────┐
│ vista   書庫    練習 12            │
├────────────────────────────────────┤
```

**The count.** 練習 carries the number of cards waiting, computed by the ported `remainingCards` — the same figure the session shows as what is left, so the two can never disagree. It means every page with the bar fetches the deck and settings in the background. If that fetch fails the bar simply reads 練習 with no number; the library is never held up by it and never shows an error on its account.

**The overview.** `/practice` is not the first question. It shows today's standing — due, new, and in learning — a way into settings, and a button that starts the session.

```
│  今天                        ⚙ 設定 │
│                                    │
│   到期 7    新卡 3    學習中 2       │
│                                    │
│        ┌────────────────┐          │
│        │   開始複習      │          │
│        └────────────────┘          │
```

Opening straight onto a question was the recommendation, since the web has one entrance and nothing to choose between. The developer chose the overview: one more screen and one more press, in exchange for not being met by a question on arrival, and a place for statistics to live later.

**Routes.**

- `/practice` — the overview. Also where the two empty states belong: nothing collected, and done for the day.
- `/practice/session` — the questions. One route; a question has no address of its own. Reloading it starts the queue again from the server, which loses nothing, because every answer was saved before the next was shown.
- `/practice/settings` — the settings page.

**The three numbers add up to the one in the bar.** Due is review cards due now; new is new cards capped by what is left of the day's allowance; in learning is learning and relearning cards due now or inside the twenty-minute learn-ahead window. That is `remainingCards` taken apart, not a second calculation.

## Comments

Resolved 2026-10-12 via `/grilling`. The route names, the bar staying visible during a session, and the breakdown of the three numbers were filled in by the agent rather than put to the developer as choices. Whether a finished session shows a closing screen of its own or returns to the overview is left with the session's edges, in the map's fog.
