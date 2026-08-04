//
//  SavedTranslationTests.swift
//  vista_comicTests
//
//  Exercises `SavedTranslation.hasExplanation` (`llm-comprehension` ticket
//  16) — the pure signal `SavedTranslationRow` uses to decide whether to
//  show its grammar/context/tone disclosure at all, independent of any
//  SwiftUI rendering.
//

import Testing
import Foundation
@testable import vista_comic

@Suite("SavedTranslation.hasExplanation")
struct SavedTranslationTests {
    private func makeSavedTranslation(
        grammarNotes: String? = nil,
        contextNotes: String? = nil,
        toneRegister: String? = nil
    ) -> SavedTranslation {
        func jsonStringOrNull(_ value: String?) -> String {
            guard let value else { return "null" }
            return "\"\(value)\""
        }
        let json = """
        {
            "id": 1,
            "originalText": "Xin chào",
            "translatedText": "你好",
            "grammarNotes": \(jsonStringOrNull(grammarNotes)),
            "contextNotes": \(jsonStringOrNull(contextNotes)),
            "toneRegister": \(jsonStringOrNull(toneRegister)),
            "targetLanguage": "zh-Hant",
            "comicId": "comic-1",
            "chapterId": "chapter-1",
            "pageNumber": 3,
            "savedAt": "2026-01-15T10:30:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(SavedTranslation.self, from: Data(json.utf8))
    }

    @Test func falseWhenAllThreeFieldsAreNil() {
        let translation = makeSavedTranslation()
        #expect(translation.hasExplanation == false)
    }

    @Test func trueWhenAllThreeFieldsArePresent() {
        let translation = makeSavedTranslation(
            grammarNotes: "SVO order",
            contextNotes: "Addressing a peer",
            toneRegister: "Casual"
        )
        #expect(translation.hasExplanation == true)
    }

    /// Degrades gracefully rather than assuming the three fields are always
    /// saved together — see `hasExplanation`'s doc comment.
    @Test func trueWhenOnlyOneFieldIsPresent() {
        let translation = makeSavedTranslation(grammarNotes: "SVO order")
        #expect(translation.hasExplanation == true)
    }

    @Test func decodesMissingExplanationKeysAsNil() throws {
        let json = """
        {
            "id": 1,
            "originalText": "Xin chào",
            "translatedText": "你好",
            "targetLanguage": "zh-Hant",
            "comicId": "comic-1",
            "chapterId": "chapter-1",
            "pageNumber": 3,
            "savedAt": "2026-01-15T10:30:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let translation = try decoder.decode(SavedTranslation.self, from: Data(json.utf8))

        #expect(translation.grammarNotes == nil)
        #expect(translation.contextNotes == nil)
        #expect(translation.toneRegister == nil)
        #expect(translation.hasExplanation == false)
    }
}
