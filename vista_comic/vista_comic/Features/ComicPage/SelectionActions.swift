//
//  SelectionActions.swift
//  vista_comic
//
//  The selection domain shared by the reader and its result sheet: the
//  confirmed-crop model plus the free functions the sheet's actions run
//  through (recognize, translate, request an explanation, await it).
//
//  Translation and explanation are two separate actions, not one. Tapping
//  "Translate" runs on-device translation and nothing else — no network call,
//  no request spent, no 歷史紀錄 row. Only the explicit "深入解釋" action reaches
//  the backend, which is why `requestExplanation` takes an already-translated
//  string rather than producing one.
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

/// The result of asking the backend for a deeper explanation — the *second*,
/// opt-in half of the result sheet's flow.
///
/// Deliberately not collapsed into success/failure: a refused enqueue still
/// leaves the reader with the on-device translation they already have on
/// screen, so it is a variant of *success* for the screen as a whole. What it
/// costs them is the explanation and the 歷史紀錄 entry, which is what the
/// reasons below distinguish.
enum ExplanationRequestOutcome: Equatable {
    /// Recorded, and the backend is now producing the explanation. This is also
    /// the only way a row enters 歷史紀錄.
    case recorded(ComprehensionRecord)
    /// Nothing was recorded — so no explanation is coming and there is nothing
    /// in 歷史紀錄 for this selection.
    case notRecorded(NotRecordedReason)

    /// Why no record exists. Split by whether retrying can possibly help,
    /// which is the same rule the result screen applies to a declined versus a
    /// failed explanation — and it decides whether a retry is offered at all.
    enum NotRecordedReason: Equatable {
        /// Today's request budget is spent. Permanent until tomorrow, so no
        /// retry, and the reader should be told plainly.
        case quotaExhausted
        /// A connection or server problem. Worth retrying.
        case transient
    }

    /// The record to poll for an explanation, if one was created.
    var record: ComprehensionRecord? {
        switch self {
        case .recorded(let record): return record
        case .notRecorded: return nil
        }
    }
}

/// Runs the opt-in "深入解釋" action: record this selection on the backend and
/// let it produce the explanation.
///
/// Split out from translation on purpose. Translation is on-device, instant and
/// free, and most selections need nothing more than that; the explanation costs
/// a Claude request out of a daily budget and takes minutes. Binding the two
/// together spent a request on every glance at a speech bubble, and filled
/// 歷史紀錄 with rows the reader never wanted to keep. So **this function is the
/// only thing that calls the backend, and therefore the only thing that creates
/// a 歷史紀錄 row** — a plain translate now leaves no trace anywhere.
///
/// Takes the on-device `translation` rather than producing one, because by the
/// time this runs the reader is already looking at it: it is enqueued alongside
/// the source text so the record carries something readable from the moment it
/// exists, even if the cloud never answers.
///
/// A free function, mirroring `translateSelection`'s/`recognizeSelection`'s own
/// reasoning: unit-testable against a stub `ComprehensionRepository` conformer
/// independent of any SwiftUI rendering.
func requestExplanation(
    sourceText: String,
    translation: String,
    targetLanguageCode: String,
    comicID: String,
    chapterID: String,
    pageNumber: Int,
    useStrongerModel: Bool,
    repository: any ComprehensionRepository
) async -> ExplanationRequestOutcome {
    do {
        let record = try await repository.enqueue(
            sourceText: sourceText,
            translatedText: translation,
            targetLanguage: targetLanguageCode,
            comicID: comicID,
            chapterID: chapterID,
            pageNumber: pageNumber,
            useStrongerModel: useStrongerModel
        )
        return .recorded(record)
    } catch ComprehensionEnqueueError.dailyCapReached {
        return .notRecorded(.quotaExhausted)
    } catch {
        // Any other enqueue failure is transient — including a conformer
        // throwing something unexpected — so a retry is worth offering.
        return .notRecorded(.transient)
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

/// The result of collecting a selection into 單字庫 — the third, opt-in action
/// on the result sheet.
///
/// Deliberately not `LoadState`: there is nothing being *loaded*, and the
/// failure here costs the reader nothing they already had. The translation
/// stays on screen either way; what a failure costs is the card.
enum CollectionOutcome: Equatable {
    /// In the deck. Also the answer when the line was **already** there — the
    /// backend returns the existing card rather than an error, and from the
    /// reader's side "it is collected" is the same fact in both cases.
    case collected(LearningCard)
    /// It did not reach the backend. Ticket 02 offers another tap; ticket 04
    /// replaces this with a queue, at which point failing at all becomes rare.
    case notCollected
}

/// Runs the "加入單字庫" action: keep this line for review later.
///
/// Takes the `translation` currently on screen rather than producing one,
/// because **which** translation that is carries meaning. The reader may be
/// looking at the on-device wording, or at the cloud's if they asked for an
/// explanation and waited; the card stores whichever they were actually reading
/// when they pressed add, since that is the one they judged correct. Nothing
/// upgrades it afterwards.
///
/// A free function, mirroring `requestExplanation`'s reasoning: unit-testable
/// against a stub `StudyRepository` conformer independent of any SwiftUI
/// rendering.
func collectSelection(
    sourceText: String,
    translation: String,
    targetLanguageCode: String,
    comicID: String,
    chapterID: String,
    pageNumber: Int,
    repository: any StudyRepository
) async -> CollectionOutcome {
    do {
        let card = try await repository.collect(
            sourceText: sourceText,
            translation: translation,
            targetLanguage: targetLanguageCode,
            comicID: comicID,
            chapterID: chapterID,
            pageNumber: pageNumber
        )
        return .collected(card)
    } catch {
        // No case split, unlike `requestExplanation`'s quota versus transient:
        // collecting spends nothing, so there is no failure here a reader
        // could only fix by waiting until tomorrow.
        return .notCollected
    }
}

/// Finds the card the reader already has for `sourceText`, if any.
///
/// Pure, and takes the cards rather than a repository, so the rule can be
/// tested without a network seam anywhere near it. The caller supplies whatever
/// it knows locally — `StudyRepository.knownCards()` in the app, a literal
/// array in tests.
///
/// Matching is on the **normalised key plus the target language**, exactly the
/// identity the backend enforces (see `TextNormalization.swift`). Anything
/// looser would claim the reader knows a word they have not collected;
/// anything stricter would miss the line breaks OCR puts in.
///
/// **A miss means "not known", never "not sure".** The snapshot may be absent,
/// stale, or from before a word was added, and none of that is worth telling
/// the reader about — the marker is a courtesy on top of the translation they
/// already have.
func alreadyCollected(
    _ sourceText: String,
    targetLanguage: String,
    in cards: [LearningCard]
) -> LearningCard? {
    let key = normalizedKey(sourceText)
    guard !key.isEmpty else { return nil }
    return cards.first {
        $0.targetLanguage == targetLanguage && normalizedKey($0.sourceText) == key
    }
}
