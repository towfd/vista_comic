//
//  TranslatorTests.swift
//  vista_comicTests
//
//  Exercises the `Translator` protocol boundary itself — a stub conformer,
//  independent of `AppleTranslator` — so the shape a caller (the OCR result
//  screen's "Translate" action, wired in a later ticket) depends on is
//  verified without invoking the real `Translation` framework. In
//  particular: `TranslationError`'s two cases are distinguishable outcomes a
//  caller can branch on and message from.
//

import Testing
import Foundation
@testable import vista_comic

/// A stub `Translator`: returns or throws whatever the test configures, and
/// records the last text/target language it was asked to translate, so
/// tests can assert on the protocol boundary without a real translator.
final class StubTranslator: Translator {
    var result: Result<String, TranslationError> = .success("")
    private(set) var lastText: String?
    private(set) var lastTargetLanguage: Locale.Language?

    func translate(_ text: String, to targetLanguage: Locale.Language) async throws -> String {
        lastText = text
        lastTargetLanguage = targetLanguage
        switch result {
        case .success(let translated):
            return translated
        case .failure(let error):
            throw error
        }
    }
}

@Suite("Translator protocol boundary")
struct TranslatorTests {
    private let traditionalChinese = Locale.Language(languageCode: "zh", script: "Hant")

    // MARK: - Success

    @Test func returnsTranslatedTextOnSuccess() async throws {
        let stub = StubTranslator()
        stub.result = .success("Xin chào bạn")

        let translated = try await stub.translate("Hello there", to: traditionalChinese)

        #expect(translated == "Xin chào bạn")
    }

    @Test func passesTheGivenTextAndTargetLanguageThrough() async throws {
        let stub = StubTranslator()
        stub.result = .success("ignored")

        _ = try await stub.translate("Xin chào", to: traditionalChinese)

        #expect(stub.lastText == "Xin chào")
        #expect(stub.lastTargetLanguage == traditionalChinese)
    }

    // MARK: - Distinguishable failures

    /// A stand-in for a caller (the OCR result screen) that must show a
    /// different message per error case. Its exhaustive `switch` over
    /// `TranslationError` is itself a compile-time guarantee that both
    /// cases stay distinguishable as the type evolves.
    private func message(for error: TranslationError) -> String {
        switch error {
        case .languagePackUnavailable: return "language-pack-unavailable"
        case .underlying: return "underlying"
        }
    }

    @Test func languagePackUnavailableIsDistinguishableFromUnderlying() async throws {
        let stub = StubTranslator()
        stub.result = .failure(.languagePackUnavailable)

        do {
            _ = try await stub.translate("Xin chào", to: traditionalChinese)
            Issue.record("expected .languagePackUnavailable to be thrown")
        } catch let error as TranslationError {
            #expect(error == .languagePackUnavailable)
            #expect(message(for: error) == "language-pack-unavailable")
        }
    }

    @Test func underlyingFailureCarriesTheOriginalErrorsDescription() async throws {
        let stub = StubTranslator()
        stub.result = .failure(.underlying("TranslationSession failed"))

        do {
            _ = try await stub.translate("Xin chào", to: traditionalChinese)
            Issue.record("expected .underlying to be thrown")
        } catch let error as TranslationError {
            #expect(error == .underlying("TranslationSession failed"))
            #expect(message(for: error) == "underlying")
        }
    }
}
