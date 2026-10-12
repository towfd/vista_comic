# 12 — A translate session that saves

**What to build:** Pressing start on the overview begins a real session. Each question shows a card's meaning; the reader types the Vietnamese and presses Enter; the verdict appears at once with their answer above the card's text; the answer is saved to the backend and moves the card for both devices; Enter again brings the next question, which never appears before the save has returned. It runs until the queue is empty. Every card is asked by translation in this ticket — cloze comes later.

This is the tracer bullet for answering, judging and writing, and the first `POST` the dev proxy has carried.

See the spec's *Judging*, *Answering and saving* and *Feedback*, and the measured input-method behaviour in the map's *Typing Vietnamese at a desk*.

**Blocked by:** 10 — Today's deck on the overview.

**Status:** ready-for-agent

- [ ] The session route asks the queue's next card as a translate question: the card's translation as the prompt, a text field, the count remaining
- [ ] Enter submits; Enter while the input method is composing does not; nothing is judged before submission
- [ ] An empty or whitespace-only field cannot be submitted
- [ ] Judging ignores case, whitespace, punctuation and symbols; word order counts
- [ ] A wrong tone, a missing tone, and a missing circumflex, breve or horn are each wrong
- [ ] Both tone placements of a syllable are the same answer; a different tone on that syllable is not
- [ ] The text keys use the forms the spec names, and precomposed and combining input give the same verdict
- [ ] The verdict shows without waiting for the network; when wrong, the reader's answer and the card's text are shown one above the other, with no tone label
- [ ] The review is posted on submit with `sentence_typed`, the verdict, a token made once per question, the local date, the moment of answering and the review context
- [ ] The response's scheduling fields are written onto that card in the held deck
- [ ] The next question is not offered until the response arrives; Enter on the feedback screen advances, and shows it is waiting if pressed early
- [ ] After advancing, focus is in the field without a click
- [ ] When the queue is empty the session ends and returns to the overview (the closing screen is a later ticket)
- [ ] Reloading the session route starts again from the server
- [ ] Unit tests cover judging and the session store's answer → verdict → save → next sequence with the client mocked
- [ ] The `POST` is confirmed once through the dev proxy against the real backend, and the result reported
- [ ] Hand-off: a list for the developer covering the two-Enter case, an empty Enter, a toneless answer, both tone placements, a missing full stop, focus after advancing, one `POST` per answer in the network panel, and the card having moved on the phone
