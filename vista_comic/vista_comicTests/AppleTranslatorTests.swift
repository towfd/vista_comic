//
//  AppleTranslatorTests.swift
//  vista_comicTests
//
//  Exercises `AppleTranslator`'s plumbing — text + target language in,
//  translated text/error out — following `VisionOCRRecognizerTests`'s
//  intent. Unlike that file, though, these tests cannot actually run to
//  completion in this environment: Apple's `Translation` framework does not
//  function in the iOS Simulator, only on a real device (a known,
//  documented SDK limitation, distinct from `Vision`, which does work in
//  Simulator). Every test below that would need a real `TranslationSession`
//  is marked `.disabled(...)` with that reason, so it stays correct and
//  ready to run unmodified the first time someone executes this suite on a
//  real device — see `.scratch/ocr-translation/issues/01-...md`.
//

import Testing
import Foundation
@testable import vista_comic

@Suite("AppleTranslator")
struct AppleTranslatorTests {
    private let traditionalChinese = Locale.Language(languageCode: "zh", script: "Hant")

    // MARK: - Protocol conformance

    /// A compile-time check that `AppleTranslator` satisfies `Translator`'s
    /// shape — the one thing about this conformer that's verifiable without
    /// a real device.
    @Test func conformsToTranslator() {
        func requiresTranslator(_ translator: some Translator) -> Bool { true }
        #expect(requiresTranslator(AppleTranslator()))
    }

    // MARK: - Real on-device translation (device-only)

    @Test(
        "translates real Vietnamese text on a real device",
        .disabled(
            """
            Apple's Translation framework does not function in the iOS \
            Simulator, only on a real device (documented SDK limitation). \
            `LanguageAvailability` and `TranslationSession` calls either \
            hang or fail to establish a session under Simulator, so this \
            can't run to completion here — verify manually on-device instead.
            """
        )
    )
    func translatesRealVietnameseTextOnADevice() async throws {
        let translator = AppleTranslator()

        let translated = try await translator.translate("Xin chào", to: traditionalChinese)

        #expect(!translated.isEmpty)
    }

    @Test(
        "throws .languagePackUnavailable when the target pack isn't installed",
        .disabled(
            """
            Requires a real device to observe `LanguageAvailability`'s actual \
            `.supported`/`.unsupported` status for an uninstalled pack; the \
            Translation framework does not function in the iOS Simulator.
            """
        )
    )
    func throwsLanguagePackUnavailableWhenNotInstalled() async throws {
        let translator = AppleTranslator()
        // A language pairing very unlikely to be pre-installed on a fresh
        // device, to exercise the not-installed path without relying on
        // whatever happens to already be downloaded.
        let unlikelyInstalled = Locale.Language(languageCode: "mn")

        await #expect(throws: TranslationError.languagePackUnavailable) {
            _ = try await translator.translate("Xin chào", to: unlikelyInstalled)
        }
    }
}
