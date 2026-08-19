//
//  TextNormalization.swift
//  vista_comic
//
//  The Swift half of the rule that decides when two collected lines are the
//  same card. The other half is `backend/app/normalization.py`, and **the two
//  must agree**.
//
//  Implemented twice on purpose rather than asked of the server on every
//  selection: the marker this feeds has to work with no connection, which is
//  exactly when the reader is looking words up most. The cost of that choice is
//  this file, and the risk it carries is drift — if the two sides disagree, the
//  app reports "not collected" while the server reports "duplicate", and the
//  reader sees an add button that never seems to finish anything.
//
//  The guard against drift is a vector table shared verbatim by both test
//  suites, listed in `.scratch/vocabulary-review/01-card-storage/spec.md`.
//  Change the rule in one place and the other suite fails.
//

import Foundation

/// The comparison key for `text`; empty when it holds nothing to learn.
///
/// Three steps, in this order — the order matters, and it matches the Python:
///
/// 1. **NFKC**, folding half-width forms onto their canonical ones, so OCR
///    reading `ﾀﾞｲｼﾞｮｳﾌﾞ` matches a card stored as `ダイジョウブ`.
/// 2. **Remove every whitespace character.** This matters most for Japanese:
///    OCR carries the speech bubble's line breaks into the text, so
///    `大丈夫\nですか` has to be the same card as `大丈夫ですか`. NFKC has already
///    turned the ideographic space into an ordinary one by this point.
/// 3. **Lowercase**, so `Good Morning` and `good morning` are one card.
///
/// Inflected forms are deliberately **not** merged: `食べた` and `食べる` produce
/// different keys and are different cards. Merging them needs a tokeniser,
/// which the PRD excludes — but the split is also right on its own terms. A
/// form the reader can already read never gets collected again, so a form that
/// keeps coming back is one they keep failing, and that repetition is precisely
/// the signal that it matters.
func normalizedKey(_ text: String) -> String {
    text
        // Foundation's compatibility mapping *is* NFKC — the composed variant,
        // matching Python's `unicodedata.normalize("NFKC", ...)`.
        .precomposedStringWithCompatibilityMapping
        .filter { !$0.isWhitespace }
        // Locale-independent, so a reader whose device is set to Turkish does
        // not get a different key for the same word than the server computed.
        .lowercased()
}
