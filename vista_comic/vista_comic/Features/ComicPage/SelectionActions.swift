//
//  SelectionActions.swift
//  vista_comic
//
//  The selection domain shared by the reader and its result sheet: the
//  confirmed-crop model plus the free functions the sheet's actions run
//  through (recognize, translate, translate-and-enqueue, await the
//  explanation).
//
//  Extracted verbatim from `ComicView.swift` (`comprehension-response-ux`
//  ticket 13) so the reader file keeps only reader/page/progress code and the
//  result-sheet rework lands in focused files. `CroppedSelection` is not
//  `private` because a top-level `private` in Swift is file-private, and this
//  type is produced by `ReaderPage` in `ComicView.swift` and consumed by the
//  sheet.
//
//  M9's cloud-first functions are gone (ticket 21): the app no longer calls
//  Claude at all, so there is nothing here that comprehends, upgrades a result,
//  or saves one by hand.
//
import SwiftUI
import UIKit

/// One completed selection crop, shown for confirmation. `Identifiable` so it
/// can drive `.sheet(item:)` directly — a fresh selection always presents a
/// fresh sheet instance, even if a prior one was dismissed without change.
///
/// The crop is the whole model now. It used to carry the full decoded page
/// alongside it, because the app uploaded both to Claude; the backend fetches
/// the page from the library itself, so nothing on this side needs to hold a
/// second full-size image per selection.
///
/// It carries `pageNumber` because the confirmation sheet is presented by the
/// **reader**, not by the page the crop was drawn on: a page inside a
/// `LazyVStack` is destroyed when it scrolls out of the viewport, taking any
/// `@State` — and therefore any sheet bound to it — with it. So the one fact
/// the sheet needed from the page has to travel with the crop instead.
struct CroppedSelection: Identifiable {
    let id = UUID()
    let image: UIImage
    /// The 1-based page index within the chapter this crop was drawn on,
    /// matching `ComprehensionRecord.pageNumber`'s convention.
    let pageNumber: Int
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

/// Polls one record until the backend has finished with it.
///
/// Polling rather than a push channel is the deliberate choice recorded in the
/// spec: one reader, minutes-long work, and a screen that is allowed to be
/// closed at any moment — cancelling a `.task` is the entire teardown story.
///
/// Transient fetch failures do not end the poll — a dropped connection mid-wait
/// is exactly the case worth surviving. Cancellation is the only exit besides a
/// terminal status, which is why `sleep` is injected: it makes the loop testable
/// in real time instead of in real minutes.
///
/// Two callers wait on the same thing from different places, and they differ in
/// exactly one respect, which is why this loop is separate from
/// `awaitExplanation`: the result screen's wait means the reader is watching, so
/// an arrival counts as read; the badge's wait (`UnreadExplanationBadge.watch`)
/// means they are not, so it must not.
///
/// Returns `nil` when cancelled before the record finished.
func awaitRecordFinishing(
    for id: Int,
    using repository: any ComprehensionRepository,
    pollInterval: Duration = .seconds(3),
    sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
) async -> ComprehensionRecord? {
    while !Task.isCancelled {
        if let record = try? await repository.record(id: id), !record.status.isInProgress {
            return record
        }
        // A throw here is cancellation during the wait, not a poll failure.
        guard (try? await sleep(pollInterval)) != nil else { return nil }
    }
    return nil
}

/// Waits for one record on behalf of a reader who is looking at it, marking it
/// read if an explanation actually landed.
///
/// Marking read belongs here rather than in the loop above because "read" means
/// the reader saw the explanation arrive, which is only knowable at this call
/// site. It is best-effort: a failed `PATCH` must never cost the reader the
/// explanation itself, so the record is returned either way and 歷史紀錄 simply
/// still shows it as unread.
///
/// Returns `nil` when cancelled before the record finished.
func awaitExplanation(
    for id: Int,
    using repository: any ComprehensionRepository,
    pollInterval: Duration = .seconds(3),
    sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
) async -> ComprehensionRecord? {
    guard let record = await awaitRecordFinishing(
        for: id, using: repository, pollInterval: pollInterval, sleep: sleep
    ) else { return nil }

    if record.hasExplanation {
        _ = try? await repository.setRead(id: id, isRead: true)
    }
    return record
}
