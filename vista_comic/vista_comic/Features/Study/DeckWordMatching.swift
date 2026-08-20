//
//  DeckWordMatching.swift
//  vista_comic
//
//  Finding the reader's own words inside a sentence.
//
//  **This exists instead of a tokeniser, and the reasoning is the point.** Cloze
//  was planned behind an LLM breaking each sentence into its words. It does not
//  need one, because the blank in a cloze is always a word the reader
//  collected — blanking something they never chose is not testing them. So the
//  question is not "what words is this sentence made of", which for Vietnamese
//  is a genuine problem (spaces separate *syllables*, so `đạo luật` is one word
//  in two pieces), but "which of my cards are in here" — a search against a list
//  already in hand.
//
//  Verified against the real deck before it was written: 6 of 7 sentence cards
//  yielded a blank, 12 in total.
//

import Foundation

/// One place a deck word occurs in a sentence.
struct DeckWordMatch: Hashable {
    let card: LearningCard
    /// A range in the **original** sentence, so blanking it leaves everything
    /// else byte-for-byte intact — including the doubled spaces and line breaks
    /// OCR carries in.
    let range: Range<String.Index>
}

/// `text` normalised for comparison, plus a map from each character of the
/// result back to where it came from.
///
/// The map is what makes a match usable. Comparison happens on a form with
/// whitespace stripped, so a hit at offset *i* there is **not** offset *i* in
/// the sentence; without this, a blank lands in the wrong place the moment the
/// source has a double space — which the reader's own cards already do.
private func normalizedWithOrigins(_ text: String) -> (key: String, origins: [String.Index]) {
    var key = ""
    var origins: [String.Index] = []
    var index = text.startIndex
    while index < text.endIndex {
        for scalar in String(text[index]).precomposedStringWithCompatibilityMapping {
            guard !scalar.isWhitespace else { continue }
            key.append(contentsOf: String(scalar).lowercased())
            origins.append(index)
        }
        index = text.index(after: index)
    }
    return (key, origins)
}

/// Every occurrence of a deck word in `sentence`.
///
/// Matching is on the normalised form — the same `normalizedKey` the deck's
/// identity and 單字庫's search use, because there is one definition of "the
/// same text" in this app and it stays that way. So case, width, doubled spaces
/// and line breaks cannot hide a word, while a changed tone still can:
/// `THÂN THỂ` does not match `THÂN THÊ`, which is correct, since in Vietnamese
/// those are different words.
///
/// **A hit must sit on a boundary** — the characters either side must not be
/// alphanumeric. That is what stops a card holding `AN` matching inside `THÂN`,
/// and it works because Vietnamese puts spaces between syllables.
///
/// **It cannot work for a language written without spaces.** Every Japanese
/// character is alphanumeric, so the test can never pass there, and dropping it
/// would let a deck word match inside a longer one. The library is Vietnamese;
/// a tokeniser belongs here, and only once a non-spaced source language actually
/// matters.
func deckWords(in sentence: String, from deck: [LearningCard]) -> [DeckWordMatch] {
    let (haystack, origins) = normalizedWithOrigins(sentence)
    guard !haystack.isEmpty else { return [] }

    var matches: [DeckWordMatch] = []
    for card in deck {
        let needle = normalizedKey(card.sourceText)
        guard !needle.isEmpty else { continue }

        var searchStart = haystack.startIndex
        while let found = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let firstOffset = haystack.distance(from: haystack.startIndex, to: found.lowerBound)
            let lastOffset = haystack.distance(from: haystack.startIndex, to: found.upperBound) - 1
            let start = origins[firstOffset]
            let end = sentence.index(after: origins[lastOffset])

            if isOnABoundary(start..<end, in: sentence) {
                matches.append(DeckWordMatch(card: card, range: start..<end))
            }
            searchStart = haystack.index(after: found.lowerBound)
        }
    }
    return matches.sorted { $0.range.lowerBound < $1.range.lowerBound }
}

/// Whether `range` is a whole word rather than part of a longer one.
private func isOnABoundary(_ range: Range<String.Index>, in text: String) -> Bool {
    let beforeOK = range.lowerBound == text.startIndex
        || !text[text.index(before: range.lowerBound)].isLetter
        && !text[text.index(before: range.lowerBound)].isNumber
    let afterOK = range.upperBound == text.endIndex
        || !text[range.upperBound].isLetter && !text[range.upperBound].isNumber
    return beforeOK && afterOK
}

extension String {
    /// This sentence with `range` replaced by a blank.
    func blanking(_ range: Range<String.Index>, with placeholder: String = "____") -> String {
        replacingCharacters(in: range, with: placeholder)
    }
}
