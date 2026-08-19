# 03 — The already-learned marker, answered locally

**What to build:** Selecting a line the reader has collected before tells them so — and still shows the meaning in full, because they clearly did not remember it.

This is the smallest version of the reward the whole PRD is built around: being told, while reading, that you already know this. It exists this early because it costs almost nothing here, and because the lookup count it enables is what stage 3 reads as a forgetting signal.

**It is answered from a local snapshot, not an endpoint.** The deck is a few hundred short strings, so the phone can hold all of it. That is the only arrangement in which the marker survives the situation the reader is most often in — a downloaded chapter and no signal. The snapshot stores the **raw `GET /cards` bytes** for the reason `CatalogSnapshotStore` gives: the display models are `Decodable`-only and should stay that way.

**This ticket implements the normalisation a second time, in Swift.** It must pass `spec.md`'s vector table verbatim, the same one ticket 01 tested in Python. A disagreement between the two shows up as the app saying "not collected" while the server says "duplicate", which is a confusing failure to chase later and a cheap one to prevent now.

The marker is a courtesy, never a correctness requirement: when the snapshot is missing, empty or unreadable, the answer is "not collected" and nothing breaks.

**Blocked by:** 02.

**Status:** not started.

- [ ] The snapshot stores raw response bytes rather than re-encoded models
- [ ] Swift normalisation passes `spec.md`'s vector table verbatim, matching ticket 01's Python results
- [ ] Selecting a previously collected line shows the marker and still shows the full meaning
- [ ] The button starts in the collected state for a line already in the deck
- [ ] A missing, empty or malformed snapshot means "not collected", surfaces no error, and blocks nothing
- [ ] The snapshot refreshes after a successful list or add, and on app foreground
- [ ] The marker works with no network, from the snapshot alone
- [ ] A line collected with hard line breaks matches the same line without them
- [ ] No XCUITest is written; a device checklist is handed to the repo owner
