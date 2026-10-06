# Web client — wayfinder map

## Destination

**The architecture of a browser-based vista_comic client, locked, and divided into parts.** Not a spec: this map settles the cross-cutting decisions — where the page is served, what OCR runs and where, which logic the web owns and which it takes from the backend — and then splits the work so each part gets its own `/grilling` session and its own spec afterwards.

The map is done when nothing architectural is left to decide and each part's boundary is sharp enough to grill. **That point has been reached** (see [The six-part split](issues/09-the-six-part-split.md)); the two tickets still open are cross-cutting unknowns that would otherwise be decided twice, in two different specs.

**Execution has since been re-scoped and started.** The first thing built is thinner than any one part — see [The MVP](issues/13-mvp-thin-display-path.md) — and lives in its own feature directory, `.scratch/web-reader-mvp/`. This map stays the architecture of record; it is not the tracker for that work.

## Notes

- **The iOS app is not modified by anything on this map.** This was the developer's explicit condition and it is load-bearing: the web is a second caller of endpoints that already exist. Anything the backend does not yet expose is an *added* endpoint, never a changed one. If a decision anywhere seems to require touching `vista_comic/`, that is the signal to stop and bring it back to the map.
- **Feature parity includes review**, which is the single largest commitment here — the phone holds 840 lines of question-generation logic with no backend counterpart at all.
- Consult `/grilling` and `/domain-modeling` for open questions; `/prototype` where the question is what a screen should look like.
- Every part's spec is grilled before it is written, one question at a time — the developer's standing preference, not a suggestion.
- Standing background: `CONTEXT.md` for the Library/Comic/Chapter/Page vocabulary, `docs/api-contract.md` for the endpoints, `.scratch/remote-access/spec.md` for how the tunnel and Access are set up today, and `ROADMAP.md` for what has been abandoned and why.
- The existing OCR pipeline lives **outside this repo**, at `~/Documents/vietnamese-ocr` — a fork with the developer's own timing instrumentation and a batch run over 803 real pages. Read it before specifying part ①.
- Conversation is in Traditional Chinese; this repo's documents stay in English.

## Decisions so far

- [Destination and scope](issues/01-destination-and-scope.md) — full feature parity with the iOS app including review; the destination is the architecture plus a split into parts, not a single spec, because one spec covering the whole client cannot be grilled honestly in one pass.
- [OCR and translation stay backend-side; iOS is not touched](issues/02-backend-side-ocr-ios-untouched.md) — a second, web-only implementation rather than moving both capabilities off the device and switching iOS over, which would have cost iOS its offline OCR. Accepted cost: the same line can recognize differently on the two clients.
- [Same-origin: FastAPI serves the built frontend](issues/03-same-origin-static-serving.md) — forced by the manga pages themselves, since an `<img>` cannot carry the Access Service Token headers and only a cookie on one hostname reaches it. A subdomain split is workable but buys a deployment split this stack has no use for; a second Python framework as a middle layer was rejected outright.
- [OCR engine and service topology](issues/04-ocr-engine-and-topology.md) — PaddleOCR's DB detector + VietOCR, reusing the developer's existing tuned pipeline, as a **fourth Compose service** rather than inside `api`, because it drags in both `paddlepaddle` and `torch`.
- [The OCR service interface: crop in the browser](issues/05-ocr-service-interface.md) — canvas crops at natural resolution and uploads a small image, so the service stays image-in/text-out and never mounts the library. The quality objection does not hold, and same-origin is what keeps the canvas untainted.
- [Question generation on the web, scheduling from the backend](issues/06-question-generation-and-scheduling.md) — the web writes its own questions and UI in TypeScript; scheduling always comes from `POST /cards/{id}/reviews`, since the web has no offline requirement and therefore none of iOS's justification for a second copy of the state machine.
- [No translation engine on the web](issues/07-no-translation-engine-on-the-web.md) — the reader fills an empty field, or takes the `translation` an explanation returns. This is the rule `.scratch/translation-editing/` just shipped with the draft step removed, and it needs no backend work at all.
- [Frontend stack and browser access](issues/08-frontend-stack-and-browser-access.md) — Vue 3 + Pinia + Tailwind, matching the three Vue specialists already in this repo's agent roster; a one-time-PIN browser policy is added beside the existing Service Token policy so the tunnel admits a browser.
- [The six-part split](issues/09-the-six-part-split.md) — ① OCR service, ② web foundation, ③ reader, ④ learning flow, ⑤ card library, ⑥ review. ① is takeable immediately and independently verifiable; ② is the foundation for the other four.
- [Measure OCR latency](issues/10-measure-ocr-latency.md) — on host CPU, one selection costs roughly **0.13s per line of text** (median 0.27s, p90 0.91s, max 1.41s over 60 realistic bubble crops); detection is near-free and recognition is the whole cost. Part ④ needs a spinner, not a queue; [the engine decision](issues/04-ocr-engine-and-topology.md) stands; and part ①'s real constraint is the **1,380MB resident** footprint plus a 150MB weight download that must be baked into the image. The in-container figure is deferred into part ① rather than run as a throwaway.
- [The MVP: one thin path to manga on screen](issues/13-mvp-thin-display-path.md) — the six parts are right and too much to take at once, so the first build is a slice **across** ② and ③: library, chapters, continuous reading, and nothing else. Progress is out in both directions. **Amended 2026-10-06:** it runs on `localhost` via a Vite proxy to the existing `api.vistabanana.com`, so it needs no server change, no new hostname and no Access policy. It goes before part ① because it is the only thing that tests what nothing has tested yet — same-origin serving, images in a browser, the Access cookie reaching `/media/...`.

## Not yet specified

- **Whether the web needs an offline-download counterpart.** Parity was agreed as *including review*; offline download (`.scratch/offline-download/`) was never put to the developer either way, so it is genuinely undecided rather than ruled out. It is listed here rather than as a part, because a browser's answer to it (a service worker, a PWA) is a different mechanism from the phone's, not a port of it — and the web page is served by the very API it would need to work without.
- **Everything inside each part.** Reader form (continuous scroll, page turns, keyboard), selection interaction, how OCR results and their correction are laid out, the card library screens, the practice screens and round structure. Each of the six parts carries its own fog; it graduates in that part's own grilling session, not here.
- **How the OCR service behaves under a second request** — one worker or several. [The measurement](issues/10-measure-ocr-latency.md) narrowed this without closing it: models must stay resident (2.4s to load against a 0.27s inference), and at ~1.4GB each alongside `api` and `postgres` on a 16GB machine, a second resident worker is expensive enough to need justifying. One worker with a queue in front is where the numbers point; part ① decides it, with a real in-container memory figure rather than this host one.

## Out of scope

- **Any change to the iOS app.** The condition the whole map is built on. Consequences the web cannot fix from its side — differing recognition between the two clients, the phone's offline deck snapshot going stale — are accepted, not worked around.
- **Moving OCR or translation off the iOS device.** Considered while resolving [OCR and translation stay backend-side](issues/02-backend-side-ocr-ios-untouched.md) and rejected: it would cost iOS its offline recognition, which works today with no connection at all.
- **Pushing question generation down into the backend.** Recommended while resolving [Question generation on the web](issues/06-question-generation-and-scheduling.md), and declined by the developer in favour of two parallel implementations sharing only the database and the API. The drift cost was stated and accepted; do not reopen it inside a part's spec.
- **A translation engine for the web** — no Claude text translation tier, no local MT model, no DeepL or Google. See [No translation engine on the web](issues/07-no-translation-engine-on-the-web.md).
- **Whole-book or whole-chapter OCR precompute.** Already abandoned repo-wide on 2026-08-07 (`ROADMAP.md`); full-page detection was raised again here while resolving [the OCR service interface](issues/05-ocr-service-interface.md) and rejected for the same reason plus its cost per selection.
