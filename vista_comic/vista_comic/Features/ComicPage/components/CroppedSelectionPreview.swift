//
//  CroppedSelectionPreview.swift
//  vista_comic
//
//  The OCR/translate result sheet presented over the reader for a confirmed
//  selection crop, plus the two per-device picker helpers only it uses.
//
//  Extracted verbatim from `ComicView.swift` (`comprehension-response-ux`
//  ticket 13); placed under `components/` to match the convention set by
//  `Features/Vocabulary/components/SavedTranslationRow.swift` and
//  `Features/ChapterPage/components/ChapterListView.swift`. Behaviour is
//  unchanged; the one unavoidable difference is that `CroppedSelectionPreview`
//  is no longer `private`, because a top-level `private` in Swift is
//  file-private and `ReaderPage` presents this sheet from `ComicView.swift`.
//
import SwiftUI
import UIKit

/// Recognition result for a confirmed text selection: recognizes the crop on
/// appear, then shows the text pre-filled in an editable field so the user can
/// correct misreads. Once recognition has succeeded, a "Translate" action
/// translates the current (possibly user-corrected) text into a picked target
/// language.
///
/// Translation runs **on device and first**, so it appears with no perceptible
/// wait, and the deeper explanation is enqueued on the backend to be produced
/// afterwards. There is no "Save": every translate is recorded automatically.
///
/// Dismissing therefore loses nothing. The record already exists on the backend
/// and the explanation arrives whether or not this screen is still open — which
/// is the whole point of enqueueing rather than waiting.
struct CroppedSelectionPreview: View {
    let image: UIImage
    /// The comic/chapter/page this crop was selected from, threaded down from
    /// `ReaderPage`. The enqueued record carries these so the backend can
    /// re-read the page from the library minutes later — which is exactly why
    /// no image is ever uploaded or stored.
    let comicID: String
    let chapterID: String
    let pageNumber: Int
    /// Passed in explicitly by `ReaderPage` rather than read from the
    /// environment here, so this view stays a plain consumer of the
    /// recognizer it's given (CLAUDE.md: pass data/actions into reusable
    /// views instead of hard-coding production behavior inside them).
    let recognizer: any OCRRecognizer
    /// Same reasoning as `recognizer` above, for the "Translate" action —
    /// now the *first* thing that runs, not a fallback, so a literal
    /// translation appears with no perceptible wait.
    let translator: any Translator
    /// Same reasoning as `recognizer`/`translator` above, for enqueueing the
    /// record whose explanation the backend produces afterwards.
    let comprehensionRepository: any ComprehensionRepository

    @Environment(\.dismiss) private var dismiss
    /// The tab shell's unread count, handed this screen's record on the way out
    /// (ticket 22) so the badge still lights up when the reader dismisses before
    /// the explanation lands. The handoff is at dismissal rather than at
    /// translate on purpose: while this screen is open it owns the wait and an
    /// arrival counts as read, so a badge watching in parallel would light up
    /// for the explanation the reader is in the middle of reading.
    @Environment(\.unreadExplanationBadge) private var badge
    @State private var recognitionState: LoadState<String> = .loading
    /// User-editable text, seeded from a successful recognition. Purely for
    /// on-screen display/correction — never written anywhere.
    @State private var editedText = ""
    /// Translation + enqueue state, deliberately separate from
    /// `recognitionState`: recognition runs automatically on appear, this runs
    /// on demand (tapping "Translate") and can be re-run against a different
    /// language or a further-edited text without disturbing the recognition
    /// result. `nil` until the user taps "Translate" for the first time.
    ///
    /// Holds a `SelectionEnqueueOutcome`, so a successful translation that the
    /// backend refused to record is still a success — the reader has their
    /// translation either way.
    @State private var enqueueState: LoadState<SelectionEnqueueOutcome>?
    @State private var selectedLanguageID = LastUsedTargetLanguage.id
    @State private var useStrongerModel = LastUsedModelTier.useStrongerModel
    /// The latest known state of the record this screen created — replaced
    /// wholesale each time polling returns a newer one, so the translation
    /// column and the `深度解釋` section always read from a single source.
    ///
    /// Separate from `enqueueState`, which records how the *translate action*
    /// went and never changes afterwards. This changes for minutes after it.
    @State private var record: ComprehensionRecord?
    /// Bumped whenever a record becomes watchable again *without* its id
    /// changing — which is exactly what a retry does. Without it, `.task(id:)`
    /// would see the same id and not re-run, and the retried record would sit
    /// unwatched.
    @State private var pollGeneration = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 180)

                    resultContent

                    if canTranslate {
                        Divider()
                        translateSection
                    }
                }
                .padding()
            }
            .navigationTitle("Selected text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await recognize() }
        // Tied to the view's lifetime rather than started inside `translate()`,
        // so dismissing the sheet cancels the poll instead of leaving it
        // running against a screen nobody is looking at — the one piece of work
        // here that would otherwise outlive the screen by minutes.
        //
        // Keyed on the record plus a generation, so it starts when a record
        // first exists, re-starts on a translate or a retry, and does *not*
        // restart merely because polling replaced the record with a newer one.
        .task(id: pollKey) { await pollForExplanation() }
        // …and hand the wait to the badge on the way out, so an explanation
        // that lands after the reader has gone still reaches them.
        .onDisappear { handOffToBadge() }
    }

    @ViewBuilder
    private var resultContent: some View {
        switch recognitionState {
        case .loading:
            HStack {
                Spacer()
                ProgressView("Recognizing text…")
                Spacer()
            }
            .frame(minHeight: 120)
        case .loaded:
            // Editable, not read-only: the whole point of showing recognized
            // text is letting the user fix a misread in place.
            TextEditor(text: $editedText)
                .font(AppFont.caption)
                .frame(minHeight: 120)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3))
                }
        case .failed(let error):
            failureContent(for: error)
        }
    }

    private func failureContent(for error: Error) -> some View {
        VStack(spacing: 12) {
            failureMessage(for: error)
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Retry") { Task { await recognize() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.primaryRed)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    /// Distinct, localization-ready messages per `OCRRecognitionError` case
    /// (Ticket 04's whole point in making them distinguishable — never
    /// collapsed into one generic "recognition failed" message), plus a
    /// fallback for a conformer that throws something else.
    @ViewBuilder
    private func failureMessage(for error: Error) -> some View {
        if let ocrError = error as? OCRRecognitionError {
            switch ocrError {
            case .noTextFound:
                Text("No text was found in the selected region. Try selecting a tighter area around the text.")
            case .lowConfidence:
                Text("The recognized text wasn't clear enough to show reliably. Try a larger or clearer selection.")
            case .underlying:
                Text("Text recognition failed unexpectedly.")
            }
        } else {
            Text("Recognition failed. You can try again.")
        }
    }

    private func recognize() async {
        recognitionState = .loading
        let result = await recognizeSelection(image, using: recognizer)
        recognitionState = result
        if case .loaded(let text) = result {
            editedText = text
        }
    }

    // MARK: - Translation

    /// The "Translate" action (and the language picker alongside it) only
    /// makes sense once there is recognized — possibly user-corrected — text
    /// to translate; recognition failing or still running leaves nothing to
    /// act on.
    private var canTranslate: Bool {
        guard case .loaded = recognitionState else { return false }
        return !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isTranslating: Bool {
        if case .loading = enqueueState { return true }
        return false
    }

    private var selectedLanguage: Locale.Language {
        Locale.Language(identifier: selectedLanguageID)
    }

    private var translateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Side by side where the width allows, stacked where it doesn't:
            // a label plus two menus overflows a compact phone (a language name
            // like "Traditional Chinese" is wide on its own), and a truncated
            // picker is worse than a second row.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    languagePicker
                    Spacer(minLength: 8)
                    depthPicker
                }
                VStack(alignment: .leading, spacing: 8) {
                    languagePicker
                    depthPicker
                }
            }

            Button("Translate") {
                Task { await translate() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.primaryRed)
            .disabled(isTranslating)
            .frame(maxWidth: .infinity)

            translationResultContent
        }
    }

    private var languagePicker: some View {
        HStack(spacing: 4) {
            Text("Translate to")
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)
            Picker("Translate to", selection: $selectedLanguageID) {
                ForEach(TargetLanguageOption.options) { option in
                    Text(option.nameKey).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .onChange(of: selectedLanguageID) { _, newValue in
                LastUsedTargetLanguage.id = newValue
            }
        }
        .fixedSize()
    }

    /// Inline beside the language picker rather than behind a settings screen:
    /// this app has no settings screen and does not gain one here, and depth is
    /// a judgement the reader makes with the text in front of them.
    ///
    /// It replaces M9's "request a stronger explanation" action, which under a
    /// queue would mean a second multi-minute wait on the very screen this work
    /// exists to unblock — so the choice moves *before* the request, not after.
    private var depthPicker: some View {
        HStack(spacing: 4) {
            Text("Depth")
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)
            Picker("Depth", selection: $useStrongerModel) {
                Text("Standard").tag(false)
                Text("Deeper").tag(true)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .onChange(of: useStrongerModel) { _, newValue in
                LastUsedModelTier.useStrongerModel = newValue
            }
            .accessibilityIdentifier("depthPicker")
        }
        .fixedSize()
    }

    @ViewBuilder
    private var translationResultContent: some View {
        // `enqueueState` is `nil` until "Translate" is tapped once;
        // unwrap explicitly rather than relying on optional/enum pattern
        // sugar, so each case below is unambiguous.
        if let enqueueState {
            switch enqueueState {
            case .loading:
                HStack {
                    Spacer()
                    ProgressView("Translating…")
                    Spacer()
                }
                .frame(minHeight: 80)
            case .loaded(let outcome):
                VStack(alignment: .leading, spacing: 12) {
                    // Original and translated text side by side, so the reader
                    // can compare them directly without scrolling between two
                    // screens.
                    HStack(alignment: .top, spacing: 12) {
                        translationColumn(titleKey: "Original", text: editedText)
                        Divider()
                        translationColumn(
                            titleKey: "Translation",
                            // Where a cloud translation exists it wins; until
                            // then the on-device one stands. Reading it off the
                            // record means pending, failed and declined records
                            // need no special case here — they simply have no
                            // cloud wording yet, or ever.
                            text: record?.displayedTranslation ?? outcome.translation,
                            isCloud: record?.cloudTranslation != nil
                        )
                    }

                    Divider()

                    // M9's verdict banner is gone, its two jobs split: the chip
                    // above says which translation this is, and this section
                    // says whether more is coming — standing exactly where the
                    // explanation itself will render.
                    ComprehensionDetailSection(
                        state: sectionState(for: outcome),
                        retry: retryAction(for: outcome)
                    )
                }
            case .failed(let error):
                translationFailureContent(for: error)
            }
        }
    }

    /// Folds the two independent things that can go wrong — the enqueue, and
    /// the explanation itself — into the section's single vocabulary, so both
    /// render in the same slot instead of the screen growing a second one.
    private func sectionState(for outcome: SelectionEnqueueOutcome) -> ComprehensionSectionState {
        switch outcome {
        case .recorded(_, let created):
            // The polled record when one has arrived, otherwise the record as
            // enqueued (always `pending`).
            return ComprehensionSectionState(record: record ?? created)
        case .notRecorded(_, let reason):
            switch reason {
            case .quotaExhausted: return .unavailable(.quotaExhausted)
            case .transient: return .unavailable(.enqueueFailed)
            }
        }
    }

    /// What "Retry" means depends on how far the flow got: a record that
    /// `failed` is re-enqueued on the backend, whereas an enqueue that never
    /// landed means running the whole translate action again. Returning `nil`
    /// where retrying cannot help keeps the button from appearing at all.
    private func retryAction(for outcome: SelectionEnqueueOutcome) -> (() -> Void)? {
        switch sectionState(for: outcome) {
        case .unavailable(.failed):
            guard let id = (record ?? outcome.record)?.id else { return nil }
            return { Task { await retryRecord(id: id) } }
        case .unavailable(.enqueueFailed):
            return { Task { await translate() } }
        case .inProgress, .explained, .unavailable:
            return nil
        }
    }

    private func translationColumn(
        titleKey: LocalizedStringKey,
        text: String,
        isCloud: Bool? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(titleKey)
                    .font(AppFont.rowTitle)
                if let isCloud {
                    TranslationProvenanceChip(isCloud: isCloud)
                }
            }
            Text(text)
                .font(AppFont.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func translationFailureContent(for error: Error) -> some View {
        VStack(spacing: 12) {
            translationFailureMessage(for: error)
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)
                .multilineTextAlignment(.center)

            Button("Retry") { Task { await translate() } }
                .buttonStyle(.borderedProminent)
                .tint(.primaryRed)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }

    /// Distinct, localization-ready messages per `TranslationError` case,
    /// mirroring `failureMessage(for:)` above for `OCRRecognitionError` —
    /// same reasoning: never collapse distinguishable failures into one
    /// generic message.
    @ViewBuilder
    private func translationFailureMessage(for error: Error) -> some View {
        if let translationError = error as? TranslationError {
            switch translationError {
            case .languagePackUnavailable:
                Text("This language isn't downloaded for on-device translation yet. Download it in Settings, then try again.")
            case .underlying:
                Text("Translation failed unexpectedly.")
            }
        } else {
            Text("Translation failed. You can try again.")
        }
    }

    private func translate() async {
        enqueueState = .loading
        // Dropped before the new request so a re-translate can't briefly show
        // the previous selection's explanation under the new translation.
        record = nil
        let outcome = await translateAndEnqueueSelection(
            editedText,
            to: selectedLanguage,
            targetLanguageCode: selectedLanguageID,
            comicID: comicID,
            chapterID: chapterID,
            pageNumber: pageNumber,
            useStrongerModel: useStrongerModel,
            using: translator,
            repository: comprehensionRepository
        )
        enqueueState = outcome
        // Setting this is what starts `.task(id:)` polling.
        if case .loaded(let value) = outcome { record = value.record }
    }

    /// Hands an unfinished record to the badge as this screen goes away.
    ///
    /// `.task(id:)`'s poll dies with the screen, so without this the explanation
    /// lands with nobody listening — which is the bug ticket 22 exists to fix. A
    /// record that already finished is not handed over: the reader saw it, and
    /// `awaitExplanation` already marked it read.
    private func handOffToBadge() {
        guard let current = record, current.status.isInProgress else { return }
        badge.watch(current, using: comprehensionRepository)
    }

    /// What `.task(id:)` watches. A record id alone is not enough: a retry puts
    /// the *same* record back to `pending`, and the poll must start again.
    private var pollKey: String {
        "\(record?.id.description ?? "none")#\(pollGeneration)"
    }

    /// Runs for as long as this screen is open and its record unfinished. Does
    /// nothing when there is no record, or when the backend already finished —
    /// including on the re-run `.task(id:)` performs after a second translate.
    private func pollForExplanation() async {
        guard let current = record, current.status.isInProgress else { return }
        if let finished = await awaitExplanation(
            for: current.id,
            using: comprehensionRepository
        ) {
            record = finished
        }
    }

    /// Re-enqueues a record the backend failed on, putting it back to `pending`.
    ///
    /// Deliberately does not poll here: bumping the generation hands the watch
    /// back to `.task(id:)`, so the poll stays owned by the view's lifetime
    /// instead of by an unstructured task that would outlive dismissal.
    private func retryRecord(id: Int) async {
        guard let requeued = try? await comprehensionRepository.retry(id: id) else { return }
        record = requeued
        pollGeneration += 1
    }
}

/// Persists the reader's explanation-depth choice locally (`UserDefaults`),
/// copying `LastUsedTargetLanguage` below exactly — same kind of preference
/// (a per-device UI choice, not learning material), so it gets the same
/// treatment rather than a new mechanism.
///
/// Defaults to the standard tier: `UserDefaults.bool(forKey:)` returns `false`
/// for a key never written, which is the cheaper model — so a reader who never
/// touches the picker never silently spends the higher rate.
private enum LastUsedModelTier {
    private static let defaultsKey = "comprehension.useStrongerModel"

    static var useStrongerModel: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}

/// Persists the OCR result screen's last-used translation target language
/// locally (`UserDefaults`) — a lightweight per-device UI preference, not
/// learning material, so it doesn't need backend storage (see the
/// `ocr-translation` spec's rationale). First-ever default is Traditional
/// Chinese, per Ticket 04.
private enum LastUsedTargetLanguage {
    private static let defaultsKey = "ocrTranslation.lastTargetLanguageID"
    static let defaultID = "zh-Hant"

    static var id: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? defaultID }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}

/// A curated, non-exhaustive set of target languages offered by the
/// translate picker (Ticket 04) — not every language Apple's `Translation`
/// framework supports, since that would clutter a picker meant for a
/// specific reading-comprehension flow; a short, sensible list is enough.
/// Traditional Chinese is first, matching the default-language decision.
/// `id` doubles as the value persisted via `LastUsedTargetLanguage` and as a
/// `Locale.Language(identifier:)` string (e.g. `Locale.Language(identifier:
/// "zh-Hant")` resolves to the same language as `AppleTranslator`'s own
/// `Locale.Language(languageCode: "zh", script: "Hant")` construction).
private struct TargetLanguageOption: Identifiable {
    let id: String
    let nameKey: LocalizedStringKey

    static let options: [TargetLanguageOption] = [
        TargetLanguageOption(id: "zh-Hant", nameKey: "Traditional Chinese"),
        TargetLanguageOption(id: "en", nameKey: "English"),
        TargetLanguageOption(id: "ja", nameKey: "Japanese"),
        TargetLanguageOption(id: "ko", nameKey: "Korean"),
        TargetLanguageOption(id: "fr", nameKey: "French"),
        TargetLanguageOption(id: "es", nameKey: "Spanish"),
    ]
}

#Preview("Reader") {
    NavigationStack {
        ComicView(
            comicID: SampleData.comics[0].id,
            chapterID: SampleData.comics[0].chapters[1].id
        )
    }
}

#Preview("Reader — load failed") {
    NavigationStack {
        ComicView(
            comicID: SampleData.comics[0].id,
            chapterID: SampleData.comics[0].chapters[0].id
        )
        .environment(\.comicRepository, FailingPreviewRepository())
    }
}

#Preview("Reader — peek from 單字本") {
    NavigationStack {
        ComicView(
            comicID: SampleData.comics[0].id,
            chapterID: SampleData.comics[0].chapters[1].id,
            targetPage: 3,
            isPeek: true
        )
    }
}
