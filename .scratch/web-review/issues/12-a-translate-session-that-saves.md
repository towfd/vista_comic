# 12 — A translate session that saves

**What to build:** Pressing start on the overview begins a real session. Each question shows a card's meaning; the reader types the Vietnamese and presses Enter; the verdict appears at once with their answer above the card's text; the answer is saved to the backend and moves the card for both devices; Enter again brings the next question, which never appears before the save has returned. It runs until the queue is empty. Every card is asked by translation in this ticket — cloze comes later.

This is the tracer bullet for answering, judging and writing, and the first `POST` the dev proxy has carried.

See the spec's *Judging*, *Answering and saving* and *Feedback*, and the measured input-method behaviour in the map's *Typing Vietnamese at a desk*.

**Blocked by:** 10 — Today's deck on the overview.

**Status:** done (2026-10-12) — merged in #109; the browser checklist below is still the developer's to run

- [x] The session route asks the queue's next card as a translate question: the card's translation as the prompt, a text field, the count remaining
- [x] Enter submits; Enter while the input method is composing does not; nothing is judged before submission
- [x] An empty or whitespace-only field cannot be submitted
- [x] Judging ignores case, whitespace, punctuation and symbols; word order counts
- [x] A wrong tone, a missing tone, and a missing circumflex, breve or horn are each wrong
- [x] Both tone placements of a syllable are the same answer; a different tone on that syllable is not
- [x] The text keys use the forms the spec names, and precomposed and combining input give the same verdict
- [x] The verdict shows without waiting for the network; when wrong, the reader's answer and the card's text are shown one above the other, with no tone label
- [x] The review is posted on submit with `sentence_typed`, the verdict, a token made once per question, the local date, the moment of answering and the review context
- [x] The response's scheduling fields are written onto that card in the held deck
- [x] The next question is not offered until the response arrives; Enter on the feedback screen advances, and shows it is waiting if pressed early
- [x] After advancing, focus is in the field without a click
- [x] When the queue is empty the session ends and returns to the overview (the closing screen is a later ticket)
- [x] Reloading the session route starts again from the server
- [x] Unit tests cover judging and the session store's answer → verdict → save → next sequence with the client mocked
- [x] The `POST` is confirmed once through the dev proxy against the real backend, and the result reported
- [x] Hand-off: a list for the developer covering the two-Enter case, an empty Enter, a toneless answer, both tone placements, a missing full stop, focus after advancing, one `POST` per answer in the network panel, and the card having moved on the phone

## Comments

Implemented 2026-10-12. 169 unit tests pass; the type check and production build are clean. The page was not opened in a browser, and **no real review was posted**.

**The `POST` through the dev proxy** was confirmed with a body the API refuses: an empty object sent to `/cards/1/reviews` came back as FastAPI's own 422 naming the missing fields. That proves the proxy carries the method and the body to the backend, and writes nothing. The first real review is the developer's first answer in the browser.

**One rule beyond the spec's wording.** Spacing is ignored and tone placement is folded, but not both in the same answer: spacing is forgiven when the tones sit where the card has them, and placement is forgiven when the syllables are spaced as the card has them. Folding a tone needs to know where a syllable ends, and removing the spaces removes exactly that. An answer that both runs words together and uses the other tone convention is marked wrong.

A failed save holds the session with a message to reload; ticket 13 replaces that with retries. A finished session returns to the overview; ticket 16 adds the closing screen.

**For the developer to check in the browser.** The first answer posts a real review and moves a real card.

- 開始複習 on the overview opens a question: a meaning, an empty field with the cursor in it, and 還剩 N 張.
- With the Vietnamese input method on, type an answer ending in a word with no punctuation: the first Enter finishes the syllable, the second submits. No half-typed syllable is ever submitted.
- Enter on an empty field, and on a field of spaces, does nothing.
- A correct answer shows 正確 and the card's text. A wrong one shows 不對, your answer, and the card's text below it.
- Type an answer without its tones (input method off): 不對.
- For a card containing a word like hoà / hòa, thuý / thúy or khoẻ / khỏe, type it with the other placement from the card: 正確.
- Leave off a closing full stop or question mark: 正確.
- After the verdict, Enter moves to the next question and the cursor is in the field without a click. Holding Enter down does not skip a question.
- In the network panel each answer is exactly one `POST /cards/{id}/reviews` with status 201, to `localhost:5173`, and the next question never appears before it returns. With the network throttled to Slow 3G, pressing Enter early turns the button to 儲存中… and the next question arrives by itself.
- The number beside 練習 goes down as cards leave the queue.
- Open the phone: the card just answered has moved (its detail shows the new stage or step).
- Answer the last card: the page returns to the overview, which says 今天做完了.
- Reload the page mid-session: a question appears again and nothing already answered is asked twice.
- A narrow window (about 375 wide) and a wide one: the prompt, field and feedback fit without overflow.
