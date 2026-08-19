//
//  CroppedSelectionPreview.swift
//  vista_comic
//
//  The OCR/translate result sheet presented over the reader for a confirmed
//  selection crop, plus the two per-device picker helpers only it uses.
//
//  Extracted verbatim from `ComicView.swift` (`comprehension-response-ux`
//  ticket 13); placed under `components/` to match the convention set by
//  the 歷史紀錄 row/detail pair and
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
/// The screen has **two separate actions**, not one. "Translate" runs entirely
/// on device: no network call, no Claude request spent, no 歷史紀錄 row. Most
/// selections are a glance at a speech bubble and need nothing more. Only when
/// the reader asks for a deeper explanation does anything reach the backend —
/// and that request is what creates the 歷史紀錄 entry, so the history is a list
/// of lines the reader actually chose to study rather than of everything they
/// ever glanced at.
///
/// Once an explanation has been requested, dismissing loses nothing: the record
/// exists on the backend and the explanation arrives whether or not this screen
/// is still open, which is the whole point of enqueueing rather than waiting.
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
    /// Same reasoning as `recognizer` above, for the "Translate" action — the
    /// whole of it, now that translating no longer calls the backend at all.
    let translator: any Translator
    /// Same reasoning as `recognizer`/`translator` above, for the opt-in
    /// explanation request whose record the backend produces afterwards.
    let comprehensionRepository: any ComprehensionRepository
    /// Same reasoning again, for the opt-in "加入單字庫" action.
    let studyRepository: any StudyRepository

    @Environment(\.dismiss) private var dismiss
    /// The tab shell's unread count, handed this screen's record on the way out
    /// (ticket 22) so the badge still lights up when the reader dismisses before
    /// the explanation lands. The handoff is at dismissal rather than at
    /// translate on purpose: while this screen is open it owns the wait and an
    /// arrival counts as read, so a badge watching in parallel would light up
    /// for the explanation the reader is in the middle of reading.
    @Environment(\.unreadExplanationBadge) private var badge
    @State private var recognitionState: LoadState<String> = .loading
    /// User-editable text, seeded from a successful recognition, and the only
    /// text in this flow the reader has actually confirmed.
    ///
    /// It used to be display-only. It is now what a collected card stores, so
    /// correcting the OCR is no longer just tidying the screen: it is the step
    /// that makes the source side of a card trustworthy, which is the premise
    /// the whole of 單字庫 rests on (see `.scratch/vocabulary-review/prd.md`).
    @State private var editedText = ""
    /// On-device translation state, deliberately separate from
    /// `recognitionState`: recognition runs automatically on appear, this runs
    /// on demand (tapping "Translate") and can be re-run against a different
    /// language or a further-edited text without disturbing the recognition
    /// result. `nil` until the user taps "Translate" for the first time.
    @State private var translationState: LoadState<String>?
    /// How the opt-in explanation request went, `nil` until the reader asks for
    /// one — which is what keeps a plain translate off the network entirely.
    ///
    /// Not a `LoadState`: this request has no failure case of its own. A
    /// refused enqueue is `.notRecorded`, still leaving the translation above
    /// untouched, so modelling it as failure would misdescribe the screen.
    @State private var explanationOutcome: ExplanationRequestOutcome?
    /// True only while the enqueue call itself is in flight. Rendered as the
    /// section's `.inProgress` state, the same as a record the backend has not
    /// finished — from the reader's side both are "it's being written".
    @State private var isRequestingExplanation = false
    @State private var selectedLanguageID = LastUsedTargetLanguage.id
    @State private var useStrongerModel = LastUsedModelTier.useStrongerModel
    /// The latest known state of the record this screen created — replaced
    /// wholesale each time polling returns a newer one, so the translation
    /// column and the `深度解釋` section always read from a single source.
    ///
    /// Separate from `explanationOutcome`, which records how the *request*
    /// went and never changes afterwards. This changes for minutes after it.
    @State private var record: ComprehensionRecord?
    /// Bumped whenever a record becomes watchable again *without* its id
    /// changing — which is exactly what a retry does. Without it, `.task(id:)`
    /// would see the same id and not re-run, and the retried record would sit
    /// unwatched.
    @State private var pollGeneration = 0
    /// Where the "加入單字庫" action has got to for the translation currently on
    /// screen. Reset by `translate()`, because a re-translate means either the
    /// text or the target language changed, and neither of those is the card
    /// that was collected a moment ago.
    @State private var collectionState: CollectionState = .idle
    /// Cards this sheet has already reported a re-lookup for.
    ///
    /// The reader can tap Translate more than once on one selection — a
    /// different target language, or the same one again after an edit — and
    /// each of those re-runs the check. Only the first sighting per card is an
    /// event: the rest are the same forgetting, counted repeatedly, which would
    /// weight the reviewing stages by how often the reader taps rather than by
    /// how often they forget.
    @State private var reportedLookups: Set<Int> = []

    /// The add button's three states, plus the one the reader can act on.
    ///
    /// `collected` offers no removal: stage 1 ships without a management
    /// screen, by decision, so this is deliberately a dead end rather than a
    /// half-built toggle.
    private enum CollectionState: Equatable {
        case idle
        case collecting
        /// Added by this reader, just now, as the kind they chose. Carried so
        /// the confirmation can name it: a mis-tap between two adjacent buttons
        /// should be visible now, not weeks later when stage 3 asks the wrong
        /// kind of question about it.
        case collected(CardKind?)
        /// Found in the deck when the translation arrived — they collected this
        /// before and are looking it up again, which is the one thing this app
        /// can know that Anki and Duolingo cannot.
        case alreadyKnown
        case failed
    }

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
                // This field holds OCR output the reader is correcting
                // character by character, in a language that is not the
                // keyboard's. Autocorrect has nothing useful to offer it and
                // actively rewrites deliberate fixes.
                //
                // It is also measurably expensive here: with autocorrect on,
                // the first tap spent 5.4s between `keyboardWillShow` and
                // `keyboardDidShow`, its candidate service timing out twice at
                // 3s and dropping an XPC connection; with it off, 2.0s. The
                // remaining 2.0s was the separate bug this shipped with — a
                // sheet owned by a recycled `LazyVStack` row (see `ReaderView`).
                .autocorrectionDisabled()
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
            languagePicker

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

    /// Sits with the "深入解釋" button rather than with the language picker,
    /// because depth is a property of *that* request and means nothing to a
    /// plain on-device translation — offering it up front implied the cloud
    /// call was part of translating, which is exactly what this split undoes.
    ///
    /// Still chosen *before* the request rather than after it: under a queue,
    /// upgrading afterwards would mean a second multi-minute wait.
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
            case .loaded(let translation):
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
                            text: record?.displayedTranslation ?? translation,
                            isCloud: record?.cloudTranslation != nil
                        )
                    }

                    Divider()

                    collectContent

                    Divider()

                    explanationContent
                }
            case .failed(let error):
                translationFailureContent(for: error)
            }
        }
    }

    // MARK: - Collecting into 單字庫

    /// The "加入單字庫" offer, and what it becomes once taken.
    ///
    /// Sits above the explanation section rather than beside it because the two
    /// cost different things and should not read as alternatives: collecting is
    /// free, instant and the reader's own judgement; the explanation spends one
    /// of today's requests and takes minutes.
    @ViewBuilder
    private var collectContent: some View {
        switch collectionState {
        case .idle:
            collectButtons
        case .collecting:
            HStack(spacing: 8) {
                ProgressView()
                Text("Adding…")
                    .font(AppFont.caption)
                    .foregroundStyle(.grayFont)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .collected(let kind):
            Label(collectedLabel(for: kind), systemImage: "checkmark.circle.fill")
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("collectedMarker")
        case .alreadyKnown:
            // Worded differently from `collected` on purpose. One says "kept";
            // this one says "you kept this before, and here you are again" —
            // which is the whole reward this feature is built around, and it is
            // only true in this case.
            //
            // The translation above stays in full. Being told you have seen a
            // word before is not a reason to withhold what it means; the reader
            // is looking it up precisely because they did not remember.
            Label("You've learned this before", systemImage: "checkmark.circle.fill")
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("alreadyLearnedMarker")
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn't add this to your vocabulary.")
                    .font(AppFont.caption)
                    .foregroundStyle(.grayFont)
                // Still the same buttons, not a separate "retry": nothing was
                // spent and nothing is half-done, so trying again is simply
                // doing it again — and the reader picks the kind again too,
                // rather than the screen acting on a choice that never took.
                collectButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The two offers, side by side where the width allows.
    ///
    /// Two buttons rather than one button plus a type picker, because the
    /// choice **is** the action: the reader knows which it is at the moment
    /// they decide to keep it, and asking them to set a type first would put a
    /// decision in front of the thing they came to do.
    ///
    /// `ViewThatFits` for the same reason `explanationPrompt` uses it — two
    /// buttons overflow a compact phone, and a truncated label is worse than a
    /// second row.
    private var collectButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                collectButton(.word)
                collectButton(.sentence)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                collectButton(.word)
                collectButton(.sentence)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func collectButton(_ kind: CardKind) -> some View {
        Button(kind == .word ? "Add as word" : "Add as sentence") {
            Task { await collect(as: kind) }
        }
        .buttonStyle(.bordered)
        .disabled(!canTranslate)
        .accessibilityIdentifier(kind == .word ? "addWord" : "addSentence")
    }

    /// Names what was kept, or stays vague when there is nothing to name — a
    /// card collected before the two buttons existed has no answer, and
    /// inventing one here would undo the point of asking.
    private func collectedLabel(for kind: CardKind?) -> LocalizedStringKey {
        switch kind {
        case .word: "Added as a word"
        case .sentence: "Added as a sentence"
        case nil: "In your vocabulary"
        }
    }

    /// Keeps the line the reader confirmed, with the translation they are
    /// looking at right now.
    ///
    /// `displayedTranslation` is read the same way the translation column reads
    /// it, so the card stores exactly the wording on screen: the on-device one
    /// if they added straight after translating, the cloud's if they asked for
    /// an explanation and waited for it.
    private func collect(as kind: CardKind) async {
        guard case .loaded(let translation) = translationState else { return }

        collectionState = .collecting
        let outcome = await collectSelection(
            sourceText: editedText,
            translation: record?.displayedTranslation ?? translation,
            targetLanguageCode: selectedLanguageID,
            comicID: comicID,
            chapterID: chapterID,
            pageNumber: pageNumber,
            kind: kind,
            repository: studyRepository
        )
        switch outcome {
        // Queued is not a lesser success. The reader's choice was recorded and
        // will be delivered; saying anything else would ask them to worry about
        // a connection on their behalf.
        case .collected, .queued:
            collectionState = .collected(kind)
        case .notCollected:
            collectionState = .failed
        }
    }

    /// Tells the backend the reader looked this collected word up again.
    ///
    /// The cleanest forgetting signal this system gets: they have just proved
    /// they did not retain it. Nothing in stage 1 displays the number — it is
    /// recorded now because it **cannot be recorded retroactively**, and stages
    /// 2 through 4 all read it.
    ///
    /// Deliberately unobserved and unable to fail the screen. The reader asked
    /// for a translation and they have it; a bookkeeping call is not worth a
    /// spinner, an error, or a moment of their attention.
    private func reportLookupIfNew(of card: LearningCard) async {
        guard reportedLookups.insert(card.id).inserted else { return }
        try? await studyRepository.recordLookup(id: card.id)
    }

    // MARK: - Deeper explanation

    /// The second, opt-in action — an offer until the reader takes it, and the
    /// shared `深度解釋` section from the moment they do.
    ///
    /// Both halves stand in the same slot on purpose: the button is replaced by
    /// the thing it produces, so the screen never shows an explanation section
    /// and a way to ask for one at the same time.
    @ViewBuilder
    private var explanationContent: some View {
        if let state = explanationSectionState {
            ComprehensionDetailSection(state: state, retry: explanationRetryAction(for: state))
        } else {
            explanationPrompt
        }
    }

    private var explanationPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Side by side where the width allows, stacked where it doesn't: a
            // label plus a menu plus a button overflows a compact phone, and a
            // truncated picker is worse than a second row.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    depthPicker
                    Spacer(minLength: 8)
                    explanationButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    depthPicker
                    explanationButton
                }
            }

            // Says plainly what taking this costs, since it is the only action
            // on this screen that spends anything or leaves anything behind.
            Text("Uses one of today's requests, and saves this line to 歷史紀錄.")
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var explanationButton: some View {
        Button("Explain in depth") {
            Task { await requestDeeperExplanation() }
        }
        .buttonStyle(.bordered)
        .tint(.primaryRed)
        .accessibilityIdentifier("explainInDepth")
    }

    /// What the `深度解釋` section is showing, or `nil` while the reader has not
    /// asked for one — which is what makes the button appear instead.
    ///
    /// Folds the two independent things that can go wrong — the enqueue, and
    /// the explanation itself — into the section's single vocabulary, so both
    /// render in the same slot instead of the screen growing a second one.
    private var explanationSectionState: ComprehensionSectionState? {
        guard let explanationOutcome else {
            return isRequestingExplanation ? .inProgress : nil
        }
        switch explanationOutcome {
        case .recorded(let created):
            // The polled record when one has arrived, otherwise the record as
            // enqueued (always `pending`).
            return ComprehensionSectionState(record: record ?? created)
        case .notRecorded(.quotaExhausted):
            return .unavailable(.quotaExhausted)
        case .notRecorded(.transient):
            return .unavailable(.enqueueFailed)
        }
    }

    /// What "Retry" means depends on how far the request got: a record that
    /// `failed` is re-enqueued on the backend, whereas an enqueue that never
    /// landed means asking again from scratch. Returning `nil` where retrying
    /// cannot help keeps the button from appearing at all.
    private func explanationRetryAction(for state: ComprehensionSectionState) -> (() -> Void)? {
        switch state {
        case .unavailable(.failed):
            guard let id = (record ?? explanationOutcome?.record)?.id else { return nil }
            return { Task { await retryRecord(id: id) } }
        case .unavailable(.enqueueFailed):
            return { Task { await requestDeeperExplanation() } }
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

    /// Translates on device and stops there — no network call, no request
    /// spent, nothing written to 歷史紀錄.
    private func translate() async {
        translationState = .loading
        // Dropped before the new translation so a re-translate can't leave the
        // previous text's explanation sitting under a different translation.
        // The record itself survives on the backend; only this screen forgets
        // it, and the badge still reports it if it was unfinished.
        explanationOutcome = nil
        record = nil
        // The card that was collected belonged to the previous text/language
        // pair, so the offer starts over rather than claiming this one is kept.
        collectionState = .idle
        translationState = await translateSelection(
            editedText, to: selectedLanguage, using: translator
        )
        // Checked here rather than on appear because this is the first moment
        // the text is settled: recognition runs automatically and the reader
        // corrects it afterwards, so anything earlier would be matching against
        // a line they had not finished fixing.
        //
        // A local read of the last good response — no network, so it answers
        // just as well on a train, which is where most of this reading happens.
        if case .loaded = translationState {
            if let known = alreadyCollected(
                editedText,
                targetLanguage: selectedLanguageID,
                in: studyRepository.knownCards()
            ) {
                collectionState = .alreadyKnown
                await reportLookupIfNew(of: known)
            } else if let queued = queuedEntry(
                for: editedText,
                targetLanguage: selectedLanguageID,
                in: studyRepository.queuedLines()
            ) {
                // Collected on this device but not yet delivered — so it is
                // kept, but the reader has not "learned it before" in any sense
                // worth claiming: they picked it minutes ago, offline.
                collectionState = .collected(queued.kind)
            }
        }
    }

    /// Asks the backend for the deeper explanation of the translation currently
    /// on screen. The only path here that spends a request or creates a
    /// 歷史紀錄 row.
    private func requestDeeperExplanation() async {
        // The button only exists under a loaded translation, so this is a
        // guard against a re-entrant tap rather than a real branch.
        guard case .loaded(let translation) = translationState else { return }

        isRequestingExplanation = true
        explanationOutcome = nil
        record = nil
        let outcome = await requestExplanation(
            sourceText: editedText,
            translation: translation,
            targetLanguageCode: selectedLanguageID,
            comicID: comicID,
            chapterID: chapterID,
            pageNumber: pageNumber,
            useStrongerModel: useStrongerModel,
            repository: comprehensionRepository
        )
        isRequestingExplanation = false
        explanationOutcome = outcome
        // Setting this is what starts `.task(id:)` polling.
        record = outcome.record
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

#Preview("Reader — peek from 歷史紀錄") {
    NavigationStack {
        ComicView(
            comicID: SampleData.comics[0].id,
            chapterID: SampleData.comics[0].chapters[1].id,
            targetPage: 3,
            isPeek: true
        )
    }
}
