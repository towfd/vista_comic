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
            HStack {
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
                Spacer()
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
                        translationColumn(titleKey: "Translation", text: outcome.translation)
                    }

                    // M9's verdict banner is gone: there is no verdict to state
                    // yet, because the explanation is produced in the
                    // background and this ticket does not display it. What the
                    // reader must not be left guessing about is the one case
                    // where nothing was recorded at all.
                    if case .notRecorded(_, let reason) = outcome {
                        notRecordedNotice(reason: reason)
                    }
                }
            case .failed(let error):
                translationFailureContent(for: error)
            }
        }
    }

    /// Shown when the translation succeeded but no record exists, so the
    /// reader is never silently left without the explanation they expect.
    ///
    /// Split by whether retrying could help, the same rule applied everywhere
    /// else in this flow: the daily budget is spent until tomorrow, whereas a
    /// connection problem is worth another go.
    @ViewBuilder
    private func notRecordedNotice(
        reason: SelectionEnqueueOutcome.NotRecordedReason
    ) -> some View {
        switch reason {
        case .quotaExhausted:
            Text("Today's cloud explanation limit is used up. This one won't be saved to your history.")
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)
        case .transient:
            HStack(spacing: 12) {
                Text("Couldn't save this to your history.")
                    .font(AppFont.caption)
                    .foregroundStyle(.grayFont)
                Button("Retry") { Task { await translate() } }
                    .font(AppFont.caption)
                    .foregroundStyle(.primaryRed)
            }
        }
    }

    private func translationColumn(titleKey: LocalizedStringKey, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleKey)
                .font(AppFont.rowTitle)
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
        enqueueState = await translateAndEnqueueSelection(
            editedText,
            to: selectedLanguage,
            targetLanguageCode: selectedLanguageID,
            comicID: comicID,
            chapterID: chapterID,
            pageNumber: pageNumber,
            // No tier picker yet — that arrives with the result screen's
            // states, which is also the first ticket that can show the
            // difference. Until then every request uses the default tier.
            useStrongerModel: false,
            using: translator,
            repository: comprehensionRepository
        )
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
