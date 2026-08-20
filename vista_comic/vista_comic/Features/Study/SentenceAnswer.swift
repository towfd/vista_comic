//
//  SentenceAnswer.swift
//  vista_comic
//
//  Judging what the reader produced, for both typing and rearranging.
//
//  The direction is the point: the prompt is the card's translation and the
//  answer is its source text, so the reader **produces** Vietnamese rather than
//  recognising it. That is what reading the comic actually asks of them, and it
//  is not what four choices measure.
//

import Foundation

/// Judges a produced sentence against the card it came from.
///
/// Punctuation and spacing never matter. Spacing because the deck's own
/// normalisation removes it; punctuation because judging strips it too — the
/// deck's sentences end in full stops and commas, and marking a perfect answer
/// wrong over one would charge the reader for punctuation rather than test
/// recall. **That stripping is only here**: `normalizedKey` keeps punctuation,
/// because it backs card identity and two lines differing by a full stop are two
/// things the reader framed differently. Spelling and **word order** do — order is the whole point of
/// this question type, and is where Vietnamese grammar lives.
///
/// **A missing tone counts and is named**, exactly as cloze settled it: typing
/// tones on a phone is laborious, and rejecting an otherwise perfect answer over
/// one charges the reader for typing rather than testing recall — while
/// silently accepting it would teach that Vietnamese tones are decoration.
///
/// That leniency lives here and in cloze's judging, and nowhere else. Card
/// identity and the search for deck words inside a sentence stay strict, since
/// two words differing only by tone are two words.
func judgeSentenceAnswer(_ produced: String, for card: LearningCard) -> TypedVerdict {
    let given = punctuationInsensitiveKey(produced)
    guard !given.isEmpty else { return .wrong }

    if given == punctuationInsensitiveKey(card.sourceText) { return .correct }
    return punctuationInsensitiveKey(toneInsensitiveKey(produced))
        == punctuationInsensitiveKey(toneInsensitiveKey(card.sourceText))
        ? .correctApartFromTones
        : .wrong
}

/// The pieces a rearrangement offers, and what putting them together produces.
///
/// **Split on whitespace**, which for Vietnamese means splitting on *syllables*:
/// `ĐẠO LUẬT` becomes two pieces even though the reader collected it as one
/// word. Keeping deck words whole is the alternative — it needs the deck as a
/// word list, and this rule needs nothing. The deck's sentences are long, so a
/// rearrangement offers twelve to fifteen pieces; if that proves miserable, this
/// function is the only thing that changes.
func sentencePieces(of card: LearningCard) -> [String] {
    card.sourceText.split(whereSeparator: \.isWhitespace).map(String.init)
}

/// Whether `card` can be asked as a rearrangement at all.
///
/// **Word cards cannot.** Six in the deck are a single syllable, leaving one
/// piece and nothing to arrange, and most of the rest are two — where guessing
/// is right half the time. A card in that difficulty band is typed instead:
/// question types follow from what a card can support.
func canRearrange(_ card: LearningCard) -> Bool {
    card.kind == .sentence && sentencePieces(of: card).count > 1
}

/// The pieces in an order that is **not** the answer.
///
/// A shuffle that happens to land in order would show the reader a finished
/// sentence and ask them to arrange it, which is not a question. Retried a
/// bounded number of times rather than looped, so a pathological input — a
/// sentence of two identical words, say — cannot hang the screen.
func shuffledPieces(of card: LearningCard, attempts: Int = 8) -> [String] {
    let ordered = sentencePieces(of: card)
    guard ordered.count > 1 else { return ordered }
    for _ in 0..<attempts {
        let candidate = ordered.shuffled()
        if candidate != ordered { return candidate }
    }
    // Every attempt matched, which means the pieces are effectively identical
    // and no arrangement of them differs. Reversing changes nothing about the
    // answer either, so it is as good as any and terminates.
    return ordered.reversed()
}

/// Judges an assembled arrangement.
///
/// **Compares the produced string, never which piece went where.** Two sentences
/// in the deck repeat a word — `CÒN` and `MÌNH` in one, `LỢI` in another — so
/// the screen shows identical pieces the reader cannot tell apart, and both
/// placements are correct. Checking positions would mark a right answer wrong.
func judgeArrangement(_ pieces: [String], for card: LearningCard) -> TypedVerdict {
    judgeSentenceAnswer(pieces.joined(separator: " "), for: card)
}
