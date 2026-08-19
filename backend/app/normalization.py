"""The rule that decides when two collected lines are the same card.

Defined in its own module because it is implemented **twice**: here, backing the
uniqueness constraint on ``learning_card``, and again in Swift, backing the
app's local "already learned" match against its deck snapshot. The two must
agree — a disagreement shows up as the app saying "not collected" while the
server says "duplicate", which is a confusing failure to chase and a cheap one
to prevent. The vector table in
``.scratch/vocabulary-review/01-card-storage/spec.md`` is shared verbatim by
both test suites.

Three steps, in this order:

1. **NFKC** — folds half-width forms onto their canonical ones, so OCR reading
   ``ﾀﾞｲｼﾞｮｳﾌﾞ`` matches a card stored as ``ダイジョウブ``.
2. **Remove every whitespace character.** This matters most for Japanese: OCR
   carries the speech bubble's line breaks into the text, so ``大丈夫\nですか``
   has to be the same card as ``大丈夫ですか``. NFKC has already turned the
   ideographic space into an ordinary one by this point.
3. **Lowercase**, so ``Good Morning`` and ``good morning`` are one card.

**Inflected forms are deliberately not merged.** ``食べた`` and ``食べる``
produce different keys and are different cards. Merging them needs a tokeniser,
which the PRD excludes — but the split is also right on its own terms: a form
the reader can already read never gets collected again, so a form that keeps
coming back is one they keep failing, and that repetition is precisely the
signal that it matters.
"""

from __future__ import annotations

import unicodedata


def normalized_key(text: str) -> str:
    """The comparison key for ``text``; ``""`` when it holds nothing to learn.

    An empty result is the caller's cue to reject the input: whitespace alone,
    or a string that normalises away entirely, is not a card.
    """
    folded = unicodedata.normalize("NFKC", text)
    return "".join(ch for ch in folded if not ch.isspace()).lower()
