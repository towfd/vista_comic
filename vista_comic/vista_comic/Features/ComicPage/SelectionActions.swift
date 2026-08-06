//
//  SelectionActions.swift
//  vista_comic
//
//  The selection domain shared by the reader and its result sheet: the
//  confirmed-crop model plus the free functions the sheet's actions run
//  through (recognize, translate, comprehend-or-translate, upgrade, save).
//
//  Extracted verbatim from `ComicView.swift` (`comprehension-response-ux`
//  ticket 13) so the reader file keeps only reader/page/progress code and the
//  result-sheet rework lands in focused files. Behaviour is unchanged; the one
//  unavoidable difference is that `CroppedSelection` is no longer `private`,
//  because a top-level `private` in Swift is file-private and this type is
//  produced by `ReaderPage` in `ComicView.swift` and consumed by the sheet.
//
import SwiftUI
import UIKit

/// One completed selection crop, shown for confirmation. `Identifiable` so it
/// can drive `.sheet(item:)` directly — a fresh selection always presents a
/// fresh sheet instance, even if a prior one was dismissed without change.
/// No recognition, no editing, no persistence yet: that is Ticket 05.
struct CroppedSelection: Identifiable {
    let id = UUID()
    let image: UIImage
    /// The full decoded page this crop was drawn from, threaded through so
    /// `CroppedSelectionPreview` can send it to `Comprehender` as scene
    /// context (`llm-comprehension` ticket 14) — captured here, at crop time,
    /// rather than read from `ReaderPage`'s `decodedImage` state again later,
    /// so this selection's page image can never drift from the one it was
    /// actually cropped out of.
    let pageImage: UIImage
}

/// Runs OCR recognition for a confirmed crop and maps the outcome onto
/// `LoadState` (`ComicRepository.swift`'s established async-fetch pattern),
/// so `CroppedSelectionPreview` only has to render three cases instead of
/// re-deriving success/failure handling itself.
///
/// A free function rather than logic embedded directly in the view's
/// `.task`, specifically so the selection → recognize step is unit-testable
/// against a stub `OCRRecognizer` independent of any SwiftUI rendering —
/// mirroring why `SelectionCropMapping` (Ticket 02) and `OCRRecognizer`
/// (Ticket 04) both stayed pure.
func recognizeSelection(_ image: UIImage, using recognizer: any OCRRecognizer) async -> LoadState<String> {
    guard let cgImage = image.cgImage else {
        // Defensive boundary case: every crop produced by `produceCrop` comes
        // from `CGImage.cropping(to:)`, so this should be unreachable in
        // practice, but a `UIImage` isn't guaranteed to carry `cgImage`.
        return .failed(OCRRecognitionError.underlying("Selected image has no pixel data"))
    }
    do {
        let text = try await recognizer.recognizeText(in: cgImage)
        return .loaded(text)
    } catch {
        return .failed(error)
    }
}

/// Runs translation for `text` into `targetLanguage` through a `Translator`,
/// mapped onto `LoadState` — the same reasoning as `recognizeSelection`
/// above, kept as its own free function (not folded into recognition) since
/// translation is a separate, on-demand lifecycle rather than something that
/// runs automatically on appear. Unit-testable against a stub `Translator`
/// independent of any SwiftUI rendering or the real `Translation` framework.
func translateSelection(
    _ text: String,
    to targetLanguage: Locale.Language,
    using translator: any Translator
) async -> LoadState<String> {
    do {
        let translated = try await translator.translate(text, to: targetLanguage)
        return .loaded(translated)
    } catch {
        return .failed(error)
    }
}

/// The "Translate" action's unified result (`llm-comprehension` ticket 14):
/// either a full cloud comprehension (`Comprehender`, ticket 13) or a
/// translation-only result produced by falling back to the existing
/// on-device `Translator` — either because the cloud call was declined
/// (content policy) or failed for any other reason (network, backend error).
/// Kept as one type, rather than a `ComprehensionResult?` and a translation
/// `String?` as two separate optionals, so the view has exactly one state to
/// switch on and can't represent the nonsensical "both present"/"neither
/// present" combinations.
enum SelectionTranslateOutcome: Equatable {
    case comprehended(ComprehensionResult)
    case translatedOnly(translation: String, reason: FallbackReason)

    /// Why the flow fell back to on-device translation — drives which of the
    /// two distinct fallback banners (orange "declined" vs. gray "error") the
    /// result screen shows, per the spec's Testing Decisions: a content
    /// decline must never look like a generic connectivity problem.
    enum FallbackReason: Equatable {
        case declined
        case error
    }

    /// The translation text, present in every case — read by the
    /// always-shown translation column and by "Save" regardless of which
    /// banner is currently showing.
    var translation: String {
        switch self {
        case .comprehended(let result): return result.translation
        case .translatedOnly(let translation, _): return translation
        }
    }
}

/// Runs the "Translate" action's real end-to-end behavior (`llm-comprehension`
/// ticket 14): calls `Comprehender` first, and only falls back to the
/// existing on-device `Translator` (unchanged — `translateSelection` above)
/// when the cloud call is declined or fails for any other reason. A free
/// function, mirroring `translateSelection`'s/`recognizeSelection`'s own
/// reasoning: unit-testable against stub `Comprehender`/`Translator`
/// conformers independent of any SwiftUI rendering.
func comprehendOrTranslateSelection(
    _ text: String,
    crop cropImage: UIImage,
    page pageImage: UIImage,
    to targetLanguage: Locale.Language,
    targetLanguageCode: String,
    using comprehender: any Comprehender,
    fallbackTranslator: any Translator
) async -> LoadState<SelectionTranslateOutcome> {
    do {
        let result = try await comprehender.comprehend(
            crop: cropImage,
            page: pageImage,
            sourceText: text,
            targetLanguage: targetLanguageCode,
            useStrongerModel: false
        )
        return .loaded(.comprehended(result))
    } catch {
        // Any thrown error other than a declined outcome — including a
        // `ComprehensionError.underlying` or a conformer throwing something
        // else entirely — falls back the same way, per the AC's "any other
        // Comprehender failure (network, backend error)" wording.
        let reason: SelectionTranslateOutcome.FallbackReason =
            (error as? ComprehensionError) == .declined ? .declined : .error
        let fallback = await translateSelection(text, to: targetLanguage, using: fallbackTranslator)
        switch fallback {
        case .loaded(let translated):
            return .loaded(.translatedOnly(translation: translated, reason: reason))
        case .failed(let translationError):
            return .failed(translationError)
        case .loading:
            // Unreachable: `translateSelection` never returns `.loading`.
            return .loading
        }
    }
}

/// Re-requests a stronger-tier (Sonnet 5, via `useStrongerModel: true`)
/// comprehension for `text` (`llm-comprehension` ticket 17's manual upgrade
/// action), calling `Comprehender` directly. Deliberately does **not** fall
/// back to `Translator` on failure, unlike `comprehendOrTranslateSelection`
/// above: this is only ever called while a valid (Haiku-tier) comprehended
/// result is already showing, and the AC requires a failed upgrade to leave
/// that original result exactly as it was — falling back here would replace
/// it with a translation-only result instead, which is strictly less than
/// what the reader already had.
func upgradeComprehension(
    _ text: String,
    crop cropImage: UIImage,
    page pageImage: UIImage,
    targetLanguageCode: String,
    using comprehender: any Comprehender
) async -> LoadState<ComprehensionResult> {
    do {
        let result = try await comprehender.comprehend(
            crop: cropImage,
            page: pageImage,
            sourceText: text,
            targetLanguage: targetLanguageCode,
            useStrongerModel: true
        )
        return .loaded(result)
    } catch {
        return .failed(error)
    }
}

/// Persists an original/translated text pair and its source reference
/// through a `TranslationRepository`, mapped onto `LoadState` — the same
/// reasoning as `recognizeSelection`/`translateSelection` above: kept as its
/// own free function so `CroppedSelectionPreview`'s "Save" action is
/// unit-testable against a stub `TranslationRepository` independent of any
/// SwiftUI rendering or the real backend.
///
/// `grammarNotes`/`contextNotes`/`toneRegister` default to `nil`
/// (`llm-comprehension` ticket 15) — the caller passes them only when saving
/// a full cloud comprehension result; a fallback (translation-only) save
/// simply omits them, persisting `NULL` on the backend rather than failing.
func saveSelection(
    originalText: String,
    translatedText: String,
    grammarNotes: String? = nil,
    contextNotes: String? = nil,
    toneRegister: String? = nil,
    targetLanguage: String,
    comicID: String,
    chapterID: String,
    pageNumber: Int,
    using repository: any TranslationRepository
) async -> LoadState<SavedTranslation> {
    do {
        let saved = try await repository.save(
            originalText: originalText,
            translatedText: translatedText,
            grammarNotes: grammarNotes,
            contextNotes: contextNotes,
            toneRegister: toneRegister,
            targetLanguage: targetLanguage,
            comicID: comicID,
            chapterID: chapterID,
            pageNumber: pageNumber
        )
        return .loaded(saved)
    } catch {
        return .failed(error)
    }
}

/// The "Translate" action's result under `comprehension-response-ux`: the
/// reader always gets a translation, and the deeper explanation is enqueued on
/// the backend to arrive later.
///
/// The flow now has **two independently failing steps** where M9 had one, so
/// this deliberately does not collapse them into success/failure. An enqueue
/// failure is a variant of *success*: the reader does have their translation,
/// and modelling it as failure would make the screen throw away something it
/// actually has. Only the on-device translation failing is a real failure —
/// see `translateAndEnqueueSelection`.
enum SelectionEnqueueOutcome: Equatable {
    /// Translated, and the backend is now producing the explanation.
    case recorded(translation: String, record: ComprehensionRecord)
    /// Translated, but nothing was recorded — so no explanation is coming and
    /// there is nothing in 歷史紀錄 for this selection.
    case notRecorded(translation: String, reason: NotRecordedReason)

    /// Why no record exists. Split by whether retrying can possibly help,
    /// which is the same rule the result screen applies to a declined versus a
    /// failed explanation — and it decides whether a retry is offered at all.
    enum NotRecordedReason: Equatable {
        /// Today's request budget is spent. Permanent until tomorrow, so no
        /// retry. The one case where "every translate is recorded" does not
        /// hold, and the reader should be told plainly.
        case quotaExhausted
        /// A connection or server problem. Worth retrying.
        case transient
    }

    /// The translation to show, present in every case — the reader is never
    /// left with nothing once the on-device step has succeeded.
    var translation: String {
        switch self {
        case .recorded(let translation, _): return translation
        case .notRecorded(let translation, _): return translation
        }
    }

    /// The record to poll for an explanation, if one was created.
    var record: ComprehensionRecord? {
        switch self {
        case .recorded(_, let record): return record
        case .notRecorded: return nil
        }
    }
}

/// Runs the "Translate" action: translate on device **first**, then enqueue the
/// deeper explanation on the backend.
///
/// This inverts M9's order, where the cloud ran first and the on-device
/// translator was only a fallback. The reader now sees a literal translation
/// essentially immediately, and never waits on the cloud at all — the backend
/// owns that call from the moment this returns, and completes it whether or not
/// the reader stays on the screen.
///
/// **If the on-device translation fails, nothing is enqueued**, the backend is
/// never called and no request is spent. The fast translation *is* the product
/// here; when it does not arrive there is nothing immediate to record, and
/// leaving the reader in front of an empty screen for minutes is the exact
/// experience this work removes.
///
/// A free function, mirroring `translateSelection`'s/`recognizeSelection`'s own
/// reasoning: unit-testable against stub `Translator`/`ComprehensionRepository`
/// conformers independent of any SwiftUI rendering.
func translateAndEnqueueSelection(
    _ text: String,
    to targetLanguage: Locale.Language,
    targetLanguageCode: String,
    comicID: String,
    chapterID: String,
    pageNumber: Int,
    useStrongerModel: Bool,
    using translator: any Translator,
    repository: any ComprehensionRepository
) async -> LoadState<SelectionEnqueueOutcome> {
    let translated: String
    switch await translateSelection(text, to: targetLanguage, using: translator) {
    case .loaded(let value):
        translated = value
    case .failed(let error):
        // The only genuine failure: without a translation there is nothing to
        // show and nothing to record.
        return .failed(error)
    case .loading:
        // Unreachable: `translateSelection` never returns `.loading`.
        return .loading
    }

    do {
        let record = try await repository.enqueue(
            sourceText: text,
            translatedText: translated,
            targetLanguage: targetLanguageCode,
            comicID: comicID,
            chapterID: chapterID,
            pageNumber: pageNumber,
            useStrongerModel: useStrongerModel
        )
        return .loaded(.recorded(translation: translated, record: record))
    } catch ComprehensionEnqueueError.dailyCapReached {
        return .loaded(.notRecorded(translation: translated, reason: .quotaExhausted))
    } catch {
        // Any other enqueue failure is transient — including a conformer
        // throwing something unexpected — so a retry is worth offering.
        return .loaded(.notRecorded(translation: translated, reason: .transient))
    }
}

/// Polls one record until the backend has finished with it, then marks it read
/// if an explanation actually landed.
///
/// Polling rather than a push channel is the deliberate choice recorded in the
/// spec: one reader, minutes-long work, and a screen that is allowed to be
/// closed at any moment — cancelling a `.task` is the entire teardown story.
///
/// Marking read is part of *this* function because "read" means the reader saw
/// the explanation arrive, which is only knowable here. It is best-effort: a
/// failed `PATCH` must never cost the reader the explanation itself, so the
/// record is returned either way and 歷史紀錄 simply still shows it as unread.
///
/// Transient fetch failures do not end the poll — a dropped connection mid-wait
/// is exactly the case worth surviving. The caller's cancellation is the only
/// exit besides a terminal status, which is why `sleep` is injected: it makes
/// the loop testable in real time instead of in real minutes.
///
/// Returns `nil` when cancelled before the record finished.
func awaitExplanation(
    for id: Int,
    using repository: any ComprehensionRepository,
    pollInterval: Duration = .seconds(3),
    sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
) async -> ComprehensionRecord? {
    while !Task.isCancelled {
        if let record = try? await repository.record(id: id), !record.status.isInProgress {
            if record.hasExplanation {
                _ = try? await repository.setRead(id: id, isRead: true)
            }
            return record
        }
        // A throw here is cancellation during the wait, not a poll failure.
        guard (try? await sleep(pollInterval)) != nil else { return nil }
    }
    return nil
}
