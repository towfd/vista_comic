# 18 — The explanation arrives while the reader watches

**What to build:** A reader who stays on the result screen sees the explanation fill in beneath their translation when it lands, and sees honest, distinguishable messages when it does not. They also choose, **before** translating, how deep an explanation they want.

M9's verdict banner is deleted and its two jobs split. "Is more coming?" becomes a `深度解釋` section standing where the explanation will render, so the waiting indicator is exactly where the answer will appear. "Which translation am I reading?" becomes a small provenance chip on the translation column itself, flipping from on-device to cloud when the cloud version replaces it — which is what makes the text changing under the reader legible instead of startling.

The `深度解釋` section is built as a reusable piece: the history detail screen renders the same states, and the two screens should teach each other rather than each inventing a vocabulary.

M9's "request a stronger explanation" action is **removed**. Under a queue it would mean a second multi-minute wait on the very screen this work exists to unblock. It is replaced by a model-tier picker beside the existing target-language picker, persisted per device, copying the pattern that preference already establishes — this app has no settings screen and does not gain one here.

**Blocked by:** 16 (records must actually complete for these states to be real), 17 (the screen and seam it builds on).

**Status:** ready-for-agent

- [ ] While the record is `pending` or `running`, the section shows one shared "being produced, you can leave" message — the two states are deliberately **not** distinguished, since a queue position is not something the reader can act on.
- [ ] On `ok`, the section is replaced by the three note fields, the translation column swaps to the cloud wording, and the provenance chip flips.
- [ ] On `failed`, a message plus a **retry**. On `declined`, a different message and **no retry** — retrying would spend quota to receive the same verdict.
- [ ] Quota-exhausted and transient-enqueue-failure both render inline in that same slot, with different copy; only the transient one offers a retry.
- [ ] Where a cloud translation exists it is displayed; otherwise the on-device one is, so pending, failed and declined records need no extra flag.
- [ ] The screen polls the single-record endpoint while its record is unfinished, and marks the record read when the explanation lands while the reader is still watching.
- [ ] A model-tier picker sits beside the language picker, its choice persisted per device and sent with the enqueue.
- [ ] **The actual price ratio between the two model tiers is checked against current pricing and recorded in the repo next to the daily cap** — the tier is now one global picker, so the whole feature's cost profile moves with it.
- [ ] The `深度解釋` section is a reusable view, not inlined, so the history detail screen can render the identical states.
- [ ] XCUITest code for the changed path is written and build-verified; running it is handed off.
- [ ] One compact and one larger phone layout both checked.
