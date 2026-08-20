//
//  DeckWordMatchingTests.swift
//  vista_comicTests
//
//  Finding the reader's own words inside a sentence (vocabulary stage 3,
//  ticket 01).
//
//  Every case below came from running the rule against the real deck before the
//  Swift was written, so these are not invented edge cases — they are what
//  actually turned up in 30 hand-collected Vietnamese cards.
//

import Foundation
import Testing

@testable import vista_comic

private func card(_ id: Int, _ text: String, ladderStage: Int = 0) -> LearningCard {
    .preview(id: id, sourceText: text, ladderStage: ladderStage)
}

private func matched(_ sentence: String, _ deck: [LearningCard]) -> [String] {
    deckWords(in: sentence, from: deck).map { String(sentence[$0.range]) }
}

@Suite("Finding deck words in a sentence")
struct DeckWordMatchingTests {

    private let sentence = "SAU KHI THÔNG QUA ĐẠO LUẬT CẤM TRỪNG PHẠT THÂN THẾ VÀO NĂM 2011"

    @Test("A deck word is found, and blanking it leaves the rest untouched")
    func aDeckWordIsFoundAndBlanksCleanly() {
        let hits = deckWords(in: sentence, from: [card(1, "ĐẠO LUẬT")])

        #expect(hits.count == 1)
        let blanked = sentence.blanking(hits[0].range)
        #expect(blanked == "SAU KHI THÔNG QUA ____ CẤM TRỪNG PHẠT THÂN THẾ VÀO NĂM 2011")
    }

    @Test("Case does not hide a word")
    func caseDoesNotHideAWord() {
        #expect(matched("sau khi thông qua", [card(1, "SAU KHI")]) == ["sau khi"])
    }

    @Test("Doubled spaces and line breaks do not hide a word, and the blank still lands right")
    func spacingDoesNotHideAWord() {
        // The reader's own cards contain OCR line breaks. Comparison happens on
        // a whitespace-stripped form, so without the index map the blank would
        // land somewhere else entirely.
        let messy = "Sau  khi\nthông qua đạo luật"

        let hits = deckWords(in: messy, from: [card(1, "SAU KHI"), card(2, "ĐẠO LUẬT")])

        #expect(hits.count == 2)
        #expect(String(messy[hits[0].range]) == "Sau  khi")
        #expect(messy.blanking(hits[1].range) == "Sau  khi\nthông qua ____")
    }

    @Test("Full-width forms match their half-width equivalents")
    func widthDoesNotHideAWord() {
        #expect(matched("ｓａｕ ｋｈｉ rồi", [card(1, "SAU KHI")]).count == 1)
    }

    @Test("A short word does not match inside a longer one")
    func aShortWordDoesNotMatchInsideALongerOne() {
        // The specific failure this rule exists to prevent: `AN` sitting inside
        // `THÂN`. It works because Vietnamese separates syllables with spaces.
        #expect(matched(sentence, [card(1, "AN")]).isEmpty)
    }

    @Test("A different tone is a different word")
    func aDifferentToneIsADifferentWord() {
        // Found in the real deck: THÂN THỂ / THÂN THÊ / THÂN THẾ are separate
        // cards because OCR read the tones differently. Folding tones away would
        // merge words that genuinely differ — cấm (forbid) is not câm (mute).
        #expect(matched(sentence, [card(1, "THÂN THỂ")]).isEmpty)
        #expect(matched(sentence, [card(1, "THÂN THẾ")]) == ["THÂN THẾ"])
    }

    @Test("A word occurring twice is found twice")
    func aWordOccurringTwiceIsFoundTwice() {
        let repeated = "LỢI ÍCH cho bản thân, LỢI ÍCH cho mọi người"

        #expect(matched(repeated, [card(1, "LỢI ÍCH")]).count == 2)
    }

    @Test("A sentence with none of the reader's words yields nothing")
    func noDeckWordYieldsNothing() {
        // Not an error: it means this card cannot carry a cloze, and the round
        // takes another one. With a small deck this is common.
        #expect(deckWords(in: sentence, from: [card(1, "食べる")]).isEmpty)
    }

    @Test("A card that normalises to nothing matches nothing")
    func anEmptyCardMatchesNothing() {
        // Otherwise an empty needle would match at every position.
        #expect(deckWords(in: sentence, from: [card(1, "   ")]).isEmpty)
    }

    @Test("Matches come back in the order they appear")
    func matchesAreInSentenceOrder() {
        let deck = [card(1, "VÀI"), card(2, "TÌNH HÌNH"), card(3, "XẤU")]
        let real = "TÌNH HÌNH XẤU LẮM. THEO LỜI BÁC SĨ NÓI CÔ ẤY CHỈ CÓ THỂ SỐNG ĐƯỢC VÀI THÁNG NỮA THÔI."

        #expect(matched(real, deck) == ["TÌNH HÌNH", "XẤU", "VÀI"])
    }

    @Test("A word at the very start or end is still on a boundary")
    func edgesCountAsBoundaries() {
        #expect(matched("SAU KHI", [card(1, "SAU KHI")]) == ["SAU KHI"])
        #expect(matched("rồi SAU KHI", [card(1, "SAU KHI")]) == ["SAU KHI"])
    }

    @Test("Punctuation counts as a boundary")
    func punctuationIsABoundary() {
        // Real sentences end in full stops and commas; a word touching one must
        // still be findable.
        #expect(matched("CHO BẢN THÂN.", [card(1, "BẢN THÂN")]) == ["BẢN THÂN"])
        #expect(matched("MÌNH NỮA, MÌNH CÒN", [card(1, "MÌNH NỮA")]) == ["MÌNH NỮA"])
    }
}

@Suite("The real deck, as collected")
struct RealDeckMatchingTests {

    /// Cards and sentences taken verbatim from the developer's own deck, so a
    /// regression shows up as something that stopped working on real data
    /// rather than on a fixture someone invented.
    @Test("Sentences from the deck yield the blanks they yielded in the spike")
    func realSentencesYieldTheirBlanks() {
        let words = [
            card(1, "KHÔNG"), card(2, "CHỊU"), card(3, "TÌNH HÌNH"), card(4, "XẤU"),
            card(5, "VÀI"), card(6, "ĂN MÒN"), card(7, "TRONG KHI"), card(8, "CÁCH"),
            card(9, "MANG LẠI"), card(10, "LỢI ÍCH"),
        ]

        #expect(matched("ĐÃ VẬY CÒN KHÔNG CHỊU Ở BÊN CẠNH MÌNH NỮA", words) == ["KHÔNG", "CHỊU"])
        #expect(matched("TRONG KHI MÌNH BỊ TẾ BÀO UNG THƯ ĂN MÒN", words) == ["TRONG KHI", "ĂN MÒN"])
        #expect(
            matched("CHÚNG BIẾT CÁCH LỢI DỤNG LUẬT ĐÊ MANG LẠI LỢI ÍCH CHO BẢN THÂN.", words)
                == ["CÁCH", "MANG LẠI", "LỢI ÍCH"]
        )
    }

    @Test("An OCR tone slip means no match, and that is correct")
    func anOCRToneSlipMeansNoMatch() {
        // The one sentence card in the real deck that yields nothing: OCR read
        // `XÂM PHẠM` as `XÂM PHAM` and `THẨM QUYỀN` as `THẤM QUYỀN`. Refusing
        // these is right — the fix is correcting the card in 單字庫, not
        // loosening the rule until wrong words match.
        let sentence = "NGAY CẢ KHI HỌC SINH CÓ NHỮNG HÀNH VI XÂM PHAM ĐẾN THẤM QUYỀN GIÁO DỤC"

        #expect(matched(sentence, [card(1, "XÂM PHẠM"), card(2, "THẨM QUYỀN")]).isEmpty)
    }
}
