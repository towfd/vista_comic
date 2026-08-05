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

/// Recognition result for a confirmed text selection (Ticket 05 of
/// `ocr-recognition`; extended additively by `ocr-translation` ticket 04):
/// recognizes the crop on appear, then shows the text pre-filled in an
/// editable field so the user can correct misreads. Once recognition has
/// succeeded, a "Translate" action becomes available to translate the
/// current (possibly user-corrected) text into a picked target language.
/// Once a translation is showing, a "Save" action persists the
/// original/translated pair and its source reference to the backend
/// (`ocr-translation` ticket 05). Dismissing — with or without edits,
/// translated or saved or not — only discards in-memory state; a
/// successfully saved pair already exists in the backend by that point, which
/// is the whole point of saving.
struct CroppedSelectionPreview: View {
    let image: UIImage
    /// The full decoded page `image` was cropped from, needed by
    /// `Comprehender` as scene/panel context (`llm-comprehension` ticket 14)
    /// alongside `image` and `editedText` — see `CroppedSelection.pageImage`
    /// for why it's captured at crop time rather than re-read later.
    let pageImage: UIImage
    /// The comic/chapter/page this crop was selected from, threaded down
    /// from `ReaderPage` — needed so "Save" can attach the correct source
    /// reference, mirroring `ComicRepository.saveProgress`'s use of the same
    /// three values elsewhere in this file.
    let comicID: String
    let chapterID: String
    let pageNumber: Int
    /// Passed in explicitly by `ReaderPage` rather than read from the
    /// environment here, so this view stays a plain consumer of the
    /// recognizer it's given (CLAUDE.md: pass data/actions into reusable
    /// views instead of hard-coding production behavior inside them).
    let recognizer: any OCRRecognizer
    /// Same reasoning as `recognizer` above, for the "Translate" action's
    /// primary cloud call (`llm-comprehension` ticket 14) — tried first,
    /// with `translator` below as its automatic fallback.
    let comprehender: any Comprehender
    /// Same reasoning as `recognizer` above, for the "Translate" action's
    /// fallback: run automatically when `comprehender` is declined or fails.
    let translator: any Translator
    /// Same reasoning as `recognizer`/`translator` above, for the "Save"
    /// action.
    let translationRepository: any TranslationRepository
    @Environment(\.dismiss) private var dismiss
    @State private var recognitionState: LoadState<String> = .loading
    /// User-editable text, seeded from a successful recognition. Purely for
    /// on-screen display/correction — never written anywhere.
    @State private var editedText = ""
    /// Translation state, deliberately separate from `recognitionState`:
    /// recognition runs automatically on appear, translation runs on demand
    /// (tapping "Translate") and can be re-run against a different language
    /// or a further-edited text without disturbing the recognition result.
    /// `nil` until the user taps "Translate" for the first time. Holds a
    /// `SelectionTranslateOutcome` (ticket 14), not a bare translated
    /// `String`, since a successful result may be a full cloud comprehension
    /// or a translation-only fallback.
    @State private var translationState: LoadState<SelectionTranslateOutcome>?
    /// Save state, deliberately separate from `translationState` for the same
    /// reason translation is separate from recognition: saving is a further
    /// on-demand step (tapping "Save"), not something that runs
    /// automatically once a translation appears. `nil` until the user taps
    /// "Save" for the first time; reset back to `nil` whenever a fresh
    /// translation replaces the one it was saved from, so a stale "Saved"
    /// indicator never sticks to a different translation.
    @State private var saveState: LoadState<SavedTranslation>?
    /// The target language, defaulting to the last-used one (or Traditional
    /// Chinese on first use — see `LastUsedTargetLanguage`). Persisted back
    /// to `UserDefaults` whenever the user changes the picker.
    @State private var selectedLanguageID = LastUsedTargetLanguage.id
    /// Whether the manual "request a stronger explanation" action
    /// (`llm-comprehension` ticket 17) is in flight. Deliberately not folded
    /// into `translationState`'s `LoadState`: the whole point of this action
    /// is that the currently-showing (Haiku-tier) result stays visible and
    /// interactive while the upgraded request runs, and stays visible if it
    /// fails — a `.loading`/`.failed` `translationState` would hide it.
    @State private var isUpgrading = false
    /// Set on a failed upgrade attempt to drive a one-shot alert, mirroring
    /// `VocabularyView`'s `deleteError` precedent: the failure is surfaced
    /// without disturbing `translationState`, so the reader never ends up
    /// with less than they had before tapping upgrade (the AC's explicit
    /// requirement).
    @State private var upgradeError: String?

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
        .alert(
            "Couldn't get a stronger explanation. Check your connection and try again.",
            isPresented: Binding(get: { upgradeError != nil }, set: { if !$0 { upgradeError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
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
        if case .loading = translationState { return true }
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
        // `translationState` is `nil` until "Translate" is tapped once;
        // unwrap explicitly rather than relying on optional/enum pattern
        // sugar, so each case below is unambiguous.
        if let translationState {
            switch translationState {
            case .loading:
                HStack {
                    Spacer()
                    ProgressView("Translating…")
                    Spacer()
                }
                .frame(minHeight: 80)
            case .loaded(let outcome):
                VStack(alignment: .leading, spacing: 12) {
                    // Always the first thing shown once a result exists (the
                    // AC's explicit ordering requirement) — answers "is this
                    // the full cloud explanation or a degraded result"
                    // before the reader looks at any content below it.
                    comprehensionBanner(for: outcome)

                    // Original and translated text side by side, so the user
                    // can compare them directly without scrolling between two
                    // screens.
                    HStack(alignment: .top, spacing: 12) {
                        translationColumn(titleKey: "Original", text: editedText)
                        Divider()
                        translationColumn(titleKey: "Translation", text: outcome.translation)
                    }

                    // Grammar/context/tone — and the manual upgrade action
                    // below them — only render for a full cloud success; the
                    // declined/error fallback cases only ever carry a
                    // translation, with no explanation to upgrade
                    // (`llm-comprehension` ticket 17's AC).
                    if case .comprehended(let result) = outcome {
                        translationColumn(titleKey: "Grammar notes", text: result.grammarNotes)
                        translationColumn(titleKey: "Context notes", text: result.contextNotes)
                        translationColumn(titleKey: "Tone & register", text: result.toneRegister)
                        upgradeButton
                    }

                    // "Save" is available as soon as a translation is
                    // showing (`ocr-translation` ticket 05's AC).
                    saveControl(outcome: outcome)
                }
            case .failed(let error):
                translationFailureContent(for: error)
            }
        }
    }

    /// The persistent status banner (`llm-comprehension` ticket 08's Variant
    /// C decision): always the first thing shown, so the reader knows at a
    /// glance whether they're looking at a full cloud explanation or one of
    /// the two distinct fallback states, before reading any content below.
    @ViewBuilder
    private func comprehensionBanner(for outcome: SelectionTranslateOutcome) -> some View {
        switch outcome {
        case .comprehended:
            banner(icon: "cloud.fill", text: "雲端深度解釋", tint: .blue)
        case .translatedOnly(_, .declined):
            // Orange, not gray — deliberately distinct from the generic
            // offline/error banner below, so a content-policy decline is
            // never mistaken for a connectivity problem (ticket 07/08's
            // whole point).
            banner(icon: "exclamationmark.triangle.fill", text: "內容政策・僅提供翻譯", tint: .orange)
        case .translatedOnly(_, .error):
            banner(icon: "iphone", text: "離線模式・僅逐字翻譯", tint: .gray)
        }
    }

    private func banner(icon: String, text: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(AppFont.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint))
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
        translationState = .loading
        // A fresh translation invalidates any prior save (it was saved from
        // the previous translated text), so start "Save" clean again.
        saveState = nil
        translationState = await comprehendOrTranslateSelection(
            editedText,
            crop: image,
            page: pageImage,
            to: selectedLanguage,
            targetLanguageCode: selectedLanguageID,
            using: comprehender,
            fallbackTranslator: translator
        )
    }

    // MARK: - Upgrade (`llm-comprehension` ticket 17)

    /// Re-requests a stronger-tier comprehension for the same text/images/
    /// target language, replacing the displayed (Haiku-tier) result on
    /// success. Only reachable while a `.comprehended` result is already
    /// showing (see `upgradeButton`'s placement) — there's no explanation to
    /// upgrade from a fallback state.
    private func upgrade() async {
        isUpgrading = true
        let result = await upgradeComprehension(
            editedText,
            crop: image,
            page: pageImage,
            targetLanguageCode: selectedLanguageID,
            using: comprehender
        )
        isUpgrading = false
        switch result {
        case .loaded(let comprehensionResult):
            translationState = .loaded(.comprehended(comprehensionResult))
            // A fresh result invalidates any prior save, same reasoning as
            // `translate()` above.
            saveState = nil
        case .failed:
            // The AC's explicit requirement: a failed upgrade leaves the
            // original result exactly as it was — `translationState` is
            // untouched — with the failure surfaced as a one-shot alert
            // instead.
            upgradeError = "Couldn't get a stronger explanation. Check your connection and try again."
        case .loading:
            break
        }
    }

    private var upgradeButton: some View {
        Button {
            Task { await upgrade() }
        } label: {
            if isUpgrading {
                HStack {
                    Spacer()
                    ProgressView()
                    Text("Requesting deeper explanation…")
                    Spacer()
                }
            } else {
                HStack {
                    Spacer()
                    Label("Request deeper explanation", systemImage: "sparkles")
                    Spacer()
                }
            }
        }
        .buttonStyle(.bordered)
        .tint(.primaryRed)
        .disabled(isUpgrading)
    }

    // MARK: - Save

    /// Persists `outcome`'s translation alongside the current edited
    /// original text, target language, and source reference. When `outcome`
    /// is a full cloud comprehension (`llm-comprehension` ticket 15), its
    /// three explanation fields are saved too; a fallback (translation-only)
    /// `outcome` saves with all three left `nil`/`NULL`.
    private func save(outcome: SelectionTranslateOutcome) async {
        saveState = .loading
        var grammarNotes: String?
        var contextNotes: String?
        var toneRegister: String?
        if case .comprehended(let result) = outcome {
            grammarNotes = result.grammarNotes
            contextNotes = result.contextNotes
            toneRegister = result.toneRegister
        }
        saveState = await saveSelection(
            originalText: editedText,
            translatedText: outcome.translation,
            grammarNotes: grammarNotes,
            contextNotes: contextNotes,
            toneRegister: toneRegister,
            targetLanguage: selectedLanguageID,
            comicID: comicID,
            chapterID: chapterID,
            pageNumber: pageNumber,
            using: translationRepository
        )
    }

    @ViewBuilder
    private func saveControl(outcome: SelectionTranslateOutcome) -> some View {
        if let saveState {
            switch saveState {
            case .loading:
                HStack {
                    Spacer()
                    ProgressView("Saving…")
                    Spacer()
                }
            case .loaded:
                HStack {
                    Spacer()
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(AppFont.caption)
                        .foregroundStyle(.primaryRed)
                    Spacer()
                }
            case .failed:
                saveFailureContent(outcome: outcome)
            }
        } else {
            // Available as soon as a translation is showing (the AC's whole
            // requirement) — no extra gating beyond that. Once tapped,
            // `saveState` becomes non-nil and this branch (along with the
            // button) is replaced by the loading/loaded/failed state above,
            // so there's no double-tap window to guard against separately.
            Button("Save") { Task { await save(outcome: outcome) } }
                .buttonStyle(.borderedProminent)
                .tint(.primaryRed)
                .frame(maxWidth: .infinity)
        }
    }

    /// A clear, non-silent failure message (the AC's explicit requirement),
    /// mirroring `failureContent(for:)`/`translationFailureContent(for:)`'s
    /// retry pattern above. Not broken out per distinguishable error case
    /// like OCR/translation failures are — `TranslationRepository.save`
    /// throws generic networking errors (`APIError`), not a save-specific
    /// enum, so one clear message covers it.
    private func saveFailureContent(outcome: SelectionTranslateOutcome) -> some View {
        VStack(spacing: 12) {
            Text("Couldn't save this translation. Check your connection and try again.")
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)
                .multilineTextAlignment(.center)

            Button("Retry") { Task { await save(outcome: outcome) } }
                .buttonStyle(.borderedProminent)
                .tint(.primaryRed)
        }
        .frame(maxWidth: .infinity)
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
