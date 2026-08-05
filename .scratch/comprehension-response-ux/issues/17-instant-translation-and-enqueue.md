# 17 — Tapping Translate is instant again

**What to build:** The single biggest change the reader feels. Tapping "Translate" now runs the **on-device translator first**, so a literal translation appears essentially immediately instead of after tens of seconds, and the deeper explanation is enqueued on the backend to be produced in the background. The reader can dismiss the sheet straight away without losing anything.

The explanation is not displayed yet — that is the next ticket. What is demoable here: the wait is gone, and a record appears on the backend for every translate.

This ticket also introduces the **one client seam** for the whole comprehension resource — a single protocol covering all six endpoints, environment-injected with a concrete production default, defined complete here so that later tickets consume it rather than concurrently editing it. It **replaces two existing seams** (the comprehender protocol and the translation repository), so the app ends with one fewer network protocol than it has today. Both old seams stay in place for now and are removed in the final ticket.

The flow inverts — translate on device, *then* enqueue — so there are two independently failing steps where there was one. From the domain modelling, the shape that produced:

```swift
enum SelectionEnqueueOutcome {
    case recorded(translation: String, record: ComprehensionRecord)
    case notRecorded(translation: String, reason: NotRecordedReason)
}

enum NotRecordedReason {
    case quotaExhausted   // permanent for today, no retry offered
    case transient        // network/server, retry offered
}
```

wrapped in the existing load-state type, where **failure means only that the on-device translation failed**. An enqueue failure is deliberately not modelled as failure: the reader does have their translation, so it is a variant of success — "translated, but not recorded" — and treating it as failure would make the screen discard something it actually has.

**Blocked by:** 13 (this reworks the screen that ticket moves), 15 (the enqueue endpoint it calls).

**Status:** ready-for-agent

- [ ] Tapping Translate shows the on-device translation with no perceptible wait; the cloud is not waited on.
- [ ] A record is created on the backend for every successful translate, carrying the source text, the on-device translation, target language, comic/chapter/page and the model tier.
- [ ] One protocol covers all six endpoints, environment-injected with a production default, and its request plumbing attaches the Cloudflare Access headers the same way the existing repository does.
- [ ] **If the on-device translation fails**, no record is created, the backend is never called, no quota is spent, and the existing translation-failure message and retry stand unchanged.
- [ ] A 429 from enqueue produces the quota-exhausted outcome; a network or server failure produces the transient outcome. In both, the translation is still shown.
- [ ] The manual "Save" control is gone from the screen.
- [ ] The translate-then-enqueue behaviour is a free function returning a load state, unit-tested against stub conformers with no SwiftUI involved — the convention the existing recognise/translate/save functions establish.
- [ ] Tests cover: on-device failure enqueues nothing; 429 yields the quota reason; transient failure yields the transient reason.
