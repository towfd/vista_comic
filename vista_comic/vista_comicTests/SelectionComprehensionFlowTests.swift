//
//  SelectionComprehensionFlowTests.swift
//  vista_comicTests
//
//  Exercises `llm-comprehension` Ticket 14's wiring:
//  `comprehendOrTranslateSelection(...)`, the free function
//  `CroppedSelectionPreview`'s "Translate" action now calls first — trying
//  `Comprehender` (Ticket 13), and automatically falling back to the
//  existing `Translator` (unchanged, `ocr-translation` Ticket 04's
//  `translateSelection`) on a declined outcome or any other failure. Uses a
//  stub `Comprehender` alongside the existing `StubTranslator`
//  (`TranslatorTests.swift`), mirroring `SelectionTranslationFlowTests`'s own
//  pattern — independent of the real backend and the real on-device
//  `Translation` framework.
//

import Testing
import Foundation
import UIKit
@testable import vista_comic

/// A stub `Comprehender`: returns or throws whatever the test configures,
/// and records the last arguments it was called with, so tests can assert
/// on the protocol boundary without a real backend call.
final class StubComprehender: Comprehender {
    var result: Result<ComprehensionResult, ComprehensionError> = .failure(.underlying("not configured"))
    private(set) var lastCropImage: UIImage?
    private(set) var lastPageImage: UIImage?
    private(set) var lastSourceText: String?
    private(set) var lastTargetLanguage: String?
    private(set) var lastUseStrongerModel: Bool?
    private(set) var callCount = 0

    func comprehend(
        crop cropImage: UIImage,
        page pageImage: UIImage,
        sourceText: String,
        targetLanguage: String,
        useStrongerModel: Bool
    ) async throws -> ComprehensionResult {
        callCount += 1
        lastCropImage = cropImage
        lastPageImage = pageImage
        lastSourceText = sourceText
        lastTargetLanguage = targetLanguage
        lastUseStrongerModel = useStrongerModel
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}

@Suite("Selection → comprehension flow")
struct SelectionComprehensionFlowTests {
    private let traditionalChinese = Locale.Language(languageCode: "zh", script: "Hant")
    private let cropImage = UIImage()
    private let pageImage = UIImage()

    // MARK: - Success

    @Test func successfulComprehensionYieldsComprehendedOutcome() async throws {
        let comprehender = StubComprehender()
        let expected = ComprehensionResult(
            translation: "Xin chào bạn",
            grammarNotes: "Subject-verb-object order",
            contextNotes: "Speaker is addressing a peer",
            toneRegister: "Casual"
        )
        comprehender.result = .success(expected)
        let translator = StubTranslator()

        let state = await comprehendOrTranslateSelection(
            "Hello there",
            crop: cropImage,
            page: pageImage,
            to: traditionalChinese,
            targetLanguageCode: "zh-Hant",
            using: comprehender,
            fallbackTranslator: translator
        )

        guard case .loaded(.comprehended(let result)) = state else {
            Issue.record("expected .loaded(.comprehended), got \(state)")
            return
        }
        #expect(result == expected)
    }

    @Test func passesTheGivenTextImagesAndTargetLanguageCodeToTheComprehender() async throws {
        let comprehender = StubComprehender()
        comprehender.result = .success(
            ComprehensionResult(translation: "ignored", grammarNotes: "", contextNotes: "", toneRegister: "")
        )
        let translator = StubTranslator()

        _ = await comprehendOrTranslateSelection(
            "corrected text",
            crop: cropImage,
            page: pageImage,
            to: traditionalChinese,
            targetLanguageCode: "zh-Hant",
            using: comprehender,
            fallbackTranslator: translator
        )

        #expect(comprehender.lastSourceText == "corrected text")
        #expect(comprehender.lastCropImage === cropImage)
        #expect(comprehender.lastPageImage === pageImage)
        #expect(comprehender.lastTargetLanguage == "zh-Hant")
        #expect(comprehender.lastUseStrongerModel == false)
    }

    /// A successful cloud call never touches the fallback `Translator` — the
    /// whole point of trying `Comprehender` first.
    @Test func successfulComprehensionNeverCallsTheFallbackTranslator() async throws {
        let comprehender = StubComprehender()
        comprehender.result = .success(
            ComprehensionResult(translation: "ignored", grammarNotes: "", contextNotes: "", toneRegister: "")
        )
        let translator = StubTranslator()

        _ = await comprehendOrTranslateSelection(
            "Hello there",
            crop: cropImage,
            page: pageImage,
            to: traditionalChinese,
            targetLanguageCode: "zh-Hant",
            using: comprehender,
            fallbackTranslator: translator
        )

        #expect(translator.lastText == nil)
    }

    // MARK: - Declined fallback

    @Test func declinedComprehensionFallsBackToTranslatorWithDeclinedReason() async throws {
        let comprehender = StubComprehender()
        comprehender.result = .failure(.declined)
        let translator = StubTranslator()
        translator.result = .success("Xin chào bạn")

        let state = await comprehendOrTranslateSelection(
            "Hello there",
            crop: cropImage,
            page: pageImage,
            to: traditionalChinese,
            targetLanguageCode: "zh-Hant",
            using: comprehender,
            fallbackTranslator: translator
        )

        guard case .loaded(.translatedOnly(let translation, let reason)) = state else {
            Issue.record("expected .loaded(.translatedOnly), got \(state)")
            return
        }
        #expect(translation == "Xin chào bạn")
        #expect(reason == .declined)
        #expect(translator.lastText == "Hello there")
        #expect(translator.lastTargetLanguage == traditionalChinese)
    }

    // MARK: - Other-failure fallback

    @Test func underlyingComprehensionFailureFallsBackToTranslatorWithErrorReason() async throws {
        let comprehender = StubComprehender()
        comprehender.result = .failure(.underlying("HTTP 502"))
        let translator = StubTranslator()
        translator.result = .success("Xin chào bạn")

        let state = await comprehendOrTranslateSelection(
            "Hello there",
            crop: cropImage,
            page: pageImage,
            to: traditionalChinese,
            targetLanguageCode: "zh-Hant",
            using: comprehender,
            fallbackTranslator: translator
        )

        guard case .loaded(.translatedOnly(let translation, let reason)) = state else {
            Issue.record("expected .loaded(.translatedOnly), got \(state)")
            return
        }
        #expect(translation == "Xin chào bạn")
        #expect(reason == .error)
    }

    /// The declined case must map to a distinct reason from every other
    /// failure — never collapsed into one generic fallback, per the AC's
    /// requirement that a content-policy decline shows a different banner
    /// than an offline/error fallback.
    @Test func declinedAndUnderlyingFailuresProduceDifferentReasons() async throws {
        let comprehender = StubComprehender()
        let translator = StubTranslator()
        translator.result = .success("ignored")

        comprehender.result = .failure(.declined)
        let declinedState = await comprehendOrTranslateSelection(
            "Hello there", crop: cropImage, page: pageImage, to: traditionalChinese,
            targetLanguageCode: "zh-Hant", using: comprehender, fallbackTranslator: translator
        )

        comprehender.result = .failure(.underlying("network down"))
        let errorState = await comprehendOrTranslateSelection(
            "Hello there", crop: cropImage, page: pageImage, to: traditionalChinese,
            targetLanguageCode: "zh-Hant", using: comprehender, fallbackTranslator: translator
        )

        guard case .loaded(.translatedOnly(_, let declinedReason)) = declinedState,
              case .loaded(.translatedOnly(_, let errorReason)) = errorState
        else {
            Issue.record("expected both to be .loaded(.translatedOnly)")
            return
        }
        #expect(declinedReason == .declined)
        #expect(errorReason == .error)
        #expect(declinedReason != errorReason)
    }

    // MARK: - Fallback itself failing

    /// If the fallback `Translator` also fails (e.g. the language pack isn't
    /// downloaded), the whole action surfaces as `.failed` — there's no
    /// third fallback, so the existing translation-failure UI (Ticket 04)
    /// takes over.
    @Test func fallbackTranslatorFailureSurfacesAsFailed() async throws {
        let comprehender = StubComprehender()
        comprehender.result = .failure(.underlying("network down"))
        let translator = StubTranslator()
        translator.result = .failure(.languagePackUnavailable)

        let state = await comprehendOrTranslateSelection(
            "Hello there",
            crop: cropImage,
            page: pageImage,
            to: traditionalChinese,
            targetLanguageCode: "zh-Hant",
            using: comprehender,
            fallbackTranslator: translator
        )

        guard case .failed(let error) = state else {
            Issue.record("expected .failed, got \(state)")
            return
        }
        #expect(error as? TranslationError == .languagePackUnavailable)
    }

    // MARK: - SelectionTranslateOutcome.translation

    @Test func outcomeTranslationReturnsTheComprehendedTranslationField() {
        let outcome = SelectionTranslateOutcome.comprehended(
            ComprehensionResult(translation: "你好", grammarNotes: "", contextNotes: "", toneRegister: "")
        )
        #expect(outcome.translation == "你好")
    }

    @Test func outcomeTranslationReturnsTheFallbackTranslationText() {
        let outcome = SelectionTranslateOutcome.translatedOnly(translation: "你好", reason: .declined)
        #expect(outcome.translation == "你好")
    }
}
