//
//  SelectionTranslationFlowTests.swift
//  vista_comicTests
//
//  Exercises `ocr-translation` Ticket 04's wiring: `translateSelection(_:to:using:)`,
//  the free function `CroppedSelectionPreview` calls from its "Translate"
//  action to run the current (possibly user-corrected) recognized text
//  through `Translator` and map the outcome onto `LoadState`. Uses the same
//  `StubTranslator` as `TranslatorTests` (Ticket 01) so this suite stays
//  independent of the real on-device `Translation` framework — it proves the
//  translate-button → translate → display path, not translation quality.
//

import Testing
import Foundation
@testable import vista_comic

@Suite("Selection → translation flow")
struct SelectionTranslationFlowTests {
    private let traditionalChinese = Locale.Language(languageCode: "zh", script: "Hant")

    // MARK: - Success

    @Test func successfulTranslationYieldsLoadedText() async throws {
        let stub = StubTranslator()
        stub.result = .success("Xin chào bạn")

        let state = await translateSelection("Hello there", to: traditionalChinese, using: stub)

        guard case .loaded(let text) = state else {
            Issue.record("expected .loaded, got \(state)")
            return
        }
        #expect(text == "Xin chào bạn")
    }

    @Test func passesTheGivenTextAndTargetLanguageToTheTranslator() async throws {
        let stub = StubTranslator()
        stub.result = .success("ignored")

        _ = await translateSelection("Xin chào", to: traditionalChinese, using: stub)

        #expect(stub.lastText == "Xin chào")
        #expect(stub.lastTargetLanguage == traditionalChinese)
    }

    /// The whole reason `translateSelection` takes plain text rather than
    /// reaching into recognition state itself: a caller can pass the
    /// user-edited text (post-correction), not the original raw recognition.
    @Test func translatesTheCurrentEditedTextNotSomeOriginal() async throws {
        let stub = StubTranslator()
        stub.result = .success("ignored")

        _ = await translateSelection("corrected text", to: traditionalChinese, using: stub)

        #expect(stub.lastText == "corrected text")
    }

    // MARK: - Distinguishable failures

    @Test func languagePackUnavailableSurfacesAsFailedWithThatError() async throws {
        let stub = StubTranslator()
        stub.result = .failure(.languagePackUnavailable)

        let state = await translateSelection("Xin chào", to: traditionalChinese, using: stub)

        guard case .failed(let error) = state else {
            Issue.record("expected .failed, got \(state)")
            return
        }
        #expect(error as? TranslationError == .languagePackUnavailable)
    }

    @Test func underlyingFailureSurfacesWithItsDescription() async throws {
        let stub = StubTranslator()
        stub.result = .failure(.underlying("TranslationSession failed"))

        let state = await translateSelection("Xin chào", to: traditionalChinese, using: stub)

        guard case .failed(let error) = state else {
            Issue.record("expected .failed, got \(state)")
            return
        }
        #expect(error as? TranslationError == .underlying("TranslationSession failed"))
    }

    // MARK: - Retry / re-translate

    /// A retry (or re-translating after picking a different language) re-runs
    /// translation and can succeed after an earlier failure — the flow a
    /// "Retry" button, or changing the picker and tapping "Translate" again,
    /// drives.
    @Test func retryingAfterFailureCanSucceed() async throws {
        let stub = StubTranslator()

        stub.result = .failure(.languagePackUnavailable)
        let firstAttempt = await translateSelection("Xin chào", to: traditionalChinese, using: stub)
        guard case .failed = firstAttempt else {
            Issue.record("expected the first attempt to fail")
            return
        }

        stub.result = .success("你好")
        let retryAttempt = await translateSelection("Xin chào", to: traditionalChinese, using: stub)
        guard case .loaded(let text) = retryAttempt else {
            Issue.record("expected the retry to succeed")
            return
        }
        #expect(text == "你好")
    }

    @Test func translatingToADifferentLanguageAfterChangingThePickerPassesTheNewLanguage() async throws {
        let stub = StubTranslator()
        let english = Locale.Language(languageCode: "en")
        stub.result = .success("Hello")

        _ = await translateSelection("Xin chào", to: traditionalChinese, using: stub)
        #expect(stub.lastTargetLanguage == traditionalChinese)

        _ = await translateSelection("Xin chào", to: english, using: stub)
        #expect(stub.lastTargetLanguage == english)
    }
}
