//
//  AppleTranslator.swift
//  vista_comic
//
//  v1's only concrete `Translator`: Apple's on-device `Translation`
//  framework, fixed to Vietnamese as the source language — this app's only
//  OCR output language (see `VisionOCRRecognizer`). A future backend-hosted
//  translator conforms to the same `Translator` protocol without any change
//  to it or its callers.
//
//  SDK shape, verified directly against the `Translation` module's public
//  interface (not secondhand documentation) rather than assumed:
//  `TranslationSession` has **no public initializer** — the only member of
//  its public interface besides methods is `deinit`. The sole documented way
//  to obtain a session is SwiftUI's `.translationTask(_:action:)` /
//  `.translationTask(source:target:action:)` view modifiers (declared in the
//  `_Translation_SwiftUI` cross-import overlay, `@available(iOS 18.0, *)`),
//  which vend a session to a live, rendered view and re-invoke their action
//  closure whenever the session's configuration changes.
//
//  `AppleTranslator` bridges that view-modifier shape into `Translator`'s
//  plain `async throws -> String` interface by momentarily hosting an
//  invisible view carrying `.translationTask` inside the app's key window,
//  and resuming a continuation from within the modifier's action closure
//  once the session responds.
//
//  Apple's `Translation` framework does not function in the iOS Simulator —
//  only on a real device (a known, documented SDK limitation). Real
//  on-device translation is therefore unverified in this environment; see
//  `AppleTranslatorTests` for what could and couldn't be exercised here.
//

import SwiftUI
import Translation

struct AppleTranslator: Translator {
    /// This app's only OCR output language (see `VisionOCRRecognizer`);
    /// hard-coded here, in the conformer, not in the `Translator` protocol.
    private static let sourceLanguage = Locale.Language(languageCode: "vi")

    func translate(_ text: String, to targetLanguage: Locale.Language) async throws -> String {
        // Checking availability first, rather than only reacting to a thrown
        // error, gives a caller a distinguishable "not available yet" reason
        // (`LanguageAvailability.Status`) instead of guessing at what a
        // generic `Translation` framework error meant.
        let status = await LanguageAvailability().status(from: Self.sourceLanguage, to: targetLanguage)
        guard status == .installed else {
            throw TranslationError.languagePackUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                TranslationSessionHost.shared.translate(
                    text,
                    source: Self.sourceLanguage,
                    target: targetLanguage,
                    continuation: continuation
                )
            }
        }
    }
}

// MARK: - Hosting a `TranslationSession`

/// Momentarily hosts an invisible view carrying `.translationTask` inside
/// the app's key window, so `AppleTranslator` can obtain a
/// `TranslationSession` despite it having no public initializer. Torn down
/// again as soon as that one translation resolves.
@MainActor
private final class TranslationSessionHost {
    static let shared = TranslationSessionHost()

    private var hostingController: UIHostingController<TranslationTaskView>?

    func translate(
        _ text: String,
        source: Locale.Language,
        target: Locale.Language,
        continuation: CheckedContinuation<String, Error>
    ) {
        guard let window = Self.keyWindow else {
            continuation.resume(
                throwing: TranslationError.underlying("No key window available to host a TranslationSession")
            )
            return
        }

        var isResolved = false
        let view = TranslationTaskView(text: text, source: source, target: target) { [weak self] result in
            guard !isResolved else { return }
            isResolved = true
            self?.tearDown()
            switch result {
            case .success(let translated):
                continuation.resume(returning: translated)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }

        let controller = UIHostingController(rootView: view)
        controller.view.frame = .zero
        controller.view.isHidden = true
        controller.view.backgroundColor = .clear

        window.addSubview(controller.view)
        hostingController = controller
    }

    private func tearDown() {
        hostingController?.view.removeFromSuperview()
        hostingController = nil
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

/// The invisible view that carries `.translationTask`, the only documented
/// way to obtain a `TranslationSession`. Reports its result exactly once via
/// `onComplete`, never updating any UI (the app never actually shows this
/// view — it exists purely to give the modifier a live view to attach to).
private struct TranslationTaskView: View {
    let text: String
    let source: Locale.Language
    let target: Locale.Language
    let onComplete: (Result<String, Error>) -> Void

    var body: some View {
        Color.clear
            .translationTask(source: source, target: target) { session in
                do {
                    let response = try await session.translate(text)
                    onComplete(.success(response.targetText))
                } catch {
                    onComplete(.failure(TranslationError.underlying(String(describing: error))))
                }
            }
    }
}
