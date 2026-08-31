//
//  PracticeView.swift
//  vista_comic
//
//  練習: the two ways in, and the session behind them.
//
//  **A session is no longer ten questions.** It runs until its queue is empty
//  and then says so, which is the only ending that means anything — a fixed
//  count cannot tell the reader they are finished, because it never knew what
//  finished was. Stopping early costs nothing: a card halfway through the
//  learning steps stays halfway through them.
//

import SwiftUI

/// Which of the two entrances the reader took.
enum SessionMode: Hashable {
    /// 複習卡片 — what is due, plus the day's new cards. Moves the schedule.
    case scheduled
    /// 永無止盡的訓練 — anything already met, at random, forever. Moves nothing.
    case training
}

struct PracticeView: View {
    @Environment(\.studyRepository) private var repository
    @Environment(\.scenePhase) private var scenePhase
    @State private var state: LoadState<[LearningCard]> = .loading
    /// The reader's own steps, or the defaults until the first fetch answers.
    /// Assuming rather than blocking: a session built on the wrong step lengths
    /// is a small error, and a practice screen that will not open is a large
    /// one.
    @State private var settings: StudySettings = .fallback
    @State private var session: SessionMode?
    /// Whether `.task` has already run once. `.onAppear` fires alongside it on
    /// the first appearance and again on every return to this tab, and only the
    /// second of those is worth a fetch.
    @State private var hasAppeared = false
    @State private var isEditingSettings = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Practice")
                .toolbar {
                    // Only on the start screen: a session in progress has its
                    // own trailing control, and changing the step lengths
                    // halfway through one would reschedule the card on screen.
                    if session == nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isEditingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityIdentifier("openSettings")
                        }
                    }
                }
                .sheet(isPresented: $isEditingSettings) {
                    StudySettingsView()
                }
                .onChange(of: isEditingSettings) { _, editing in
                    // Reload once the sheet closes: the steps decide how the
                    // queue is built, so the start screen's figures are stale
                    // the moment they change.
                    if !editing { Task { await load() } }
                }
        }
        .task { await load() }
        // A session changes due times and slots, so the deck held here goes
        // stale the moment one is played. Coming back to the tab — or to the
        // app — is where that showed: the next session was built from the
        // figures the last one started with, and picked the same cards again.
        .onAppear {
            if hasAppeared { Task { await load() } }
            hasAppeared = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ErrorStateView { Task { await load() } }
        case .loaded(let deck):
            if let session {
                SessionView(
                    startingDeck: deck,
                    settings: settings,
                    mode: session,
                    repository: repository
                ) {
                    self.session = nil
                    Task { await load() }
                }
            } else {
                StartView(
                    deck: deck,
                    settings: settings,
                    today: Self.today(),
                    start: { session = $0 }
                )
            }
        }
    }

    /// The reader's local day, as the backend groups practice by.
    ///
    /// Deliberately not UTC: on UTC+8 a UTC boundary would move the line at
    /// which the day's new-card quota resets to eight in the morning.
    static func today() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Reads the deck, falling back to what is on the device — the same
    /// arrangement 單字庫 uses, and for the same reason: a reader on a train
    /// should still be able to practise.
    private func load() async {
        do {
            state = .loaded(try await repository.cards())
        } catch {
            // Same rule as 單字庫 and the catalog: degrade when nothing was
            // reached, report when the server answered badly.
            let cached = APIConfig.isOriginUnreachable(error) ? repository.knownCards() : []
            state = cached.isEmpty ? .failed(error) : .loaded(cached)
        }
        // Best-effort and separate: the settings failing is not worth refusing
        // to practise over, and the defaults are what the backend seeded anyway.
        if let fetched = try? await repository.settings() { settings = fetched }
    }
}

/// The screen before a session: what is waiting, and the two ways in.
///
/// **Every figure on it is real.** Nothing here is a streak, a score or a daily
/// goal — those are stage 7 — and this app has already shipped two features
/// that were looked at rather than used.
private struct StartView: View {
    let deck: [LearningCard]
    let settings: StudySettings
    let today: String
    let start: (SessionMode) -> Void

    private var dueNow: Int {
        deck.filter { $0.state != .new && $0.dueAt <= Date() }.count
    }

    private var newLeft: Int {
        max(settings.newCardsPerDay - introducedCount(in: deck, on: today), 0)
    }

    private var trainable: Int { trainableCards(in: deck).count }

    var body: some View {
        if deck.isEmpty {
            ContentUnavailableView(
                "No words yet",
                systemImage: "text.book.closed",
                description: Text("Collect a few while reading, then come back.")
            )
        } else {
            VStack(spacing: 24) {
                Spacer()

                VStack(alignment: .leading, spacing: 20) {
                    Text("WAITING FOR YOU")
                        .font(AppFont.caption)
                        .foregroundStyle(.grayFont)
                        .kerning(1.5)

                    VStack(alignment: .leading, spacing: 6) {
                        figure("\(dueNow)", "cards due")
                        figure("\(newLeft)", "new today")
                    }

                    Divider()

                    // No question count, because there is no longer one to
                    // give: a card comes back until it is learned, so how many
                    // questions this takes depends on how it goes.
                    Text("Runs until nothing is left.")
                        .font(AppFont.caption)
                        .foregroundStyle(.grayFont)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        start(.scheduled)
                    } label: {
                        Label("Review cards", systemImage: "play.fill")
                            .font(AppFont.prompt)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primaryRed)
                    .accessibilityIdentifier("startPractice")

                    Button {
                        start(.training)
                    } label: {
                        Label("Endless training", systemImage: "infinity")
                            .font(AppFont.prompt)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .disabled(trainable == 0)
                    .accessibilityIdentifier("startTraining")

                    // Said rather than left to the disabled button, which
                    // explains nothing: training draws on words already met, so
                    // a reader who has met none is not being refused, they are
                    // early.
                    if trainable == 0 {
                        Text("Training opens once you have met a word.")
                            .font(AppFont.caption)
                            .foregroundStyle(.grayFont)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }

    private func figure(_ value: String, _ label: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value).font(AppFont.statistic)
            Text(label).font(AppFont.caption).foregroundStyle(.grayFont)
        }
    }
}

/// One session, from the first question to the end of the queue.
private struct SessionView: View {
    let startingDeck: [LearningCard]
    let settings: StudySettings
    let mode: SessionMode
    let repository: any StudyRepository
    let onFinish: () -> Void

    /// The deck as this session has changed it.
    ///
    /// Updated from each answer's response rather than refetched, which is what
    /// lets the queue keep building with no network — and is also why the
    /// backend returns the card's whole scheduling block instead of just
    /// acknowledging.
    @State private var deck: [LearningCard] = []
    @State private var current: PracticeItem?
    @State private var lastCardID: Int?
    /// Set once the queue runs dry, and what the closing screen reads.
    @State private var ended: QueueEmpty?
    @State private var typed = ""
    /// The rearrangement in progress: what has been placed, and what is left.
    @State private var assembled: [String] = []
    @State private var available: [String] = []
    /// `nil` while the question is open; set once answered, and what the screen
    /// shows instead of accepting another answer.
    @State private var verdict: TypedVerdict?
    @State private var outcome = RoundOutcome()

    var body: some View {
        Group {
            if let current {
                question(current)
            } else {
                closing
            }
        }
        .toolbar {
            // Visible throughout, because a session has no length the reader
            // can see and so no point at which stopping is obviously allowed.
            // Leaving costs nothing: every card keeps the step it is on.
            ToolbarItem(placement: .topBarTrailing) {
                Button("Stop") { onFinish() }
                    .accessibilityIdentifier("stopSession")
            }
        }
        .task {
            if deck.isEmpty {
                deck = startingDeck
                advance()
            }
        }
    }

    private func question(_ item: PracticeItem) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("\(outcome.total) answered")

                Spacer()

                // Where this card stands and when it is next up. Without it a
                // reader meeting the same word for the fourth time has no way
                // to tell whether anything is moving — which is exactly the
                // complaint that started this rewrite.
                Label {
                    Text(scheduleSummary(of: item.card, steps: settings.learningSteps))
                } icon: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
                .accessibilityIdentifier("cardSchedule")
            }
            .font(AppFont.caption)
            .foregroundStyle(.grayFont)

            // The two whole-sentence modes show the meaning and ask for the
            // Vietnamese; the cloze modes show the sentence with a gap in it.
            Text(item.prompt)
                .font(AppFont.prompt)
                .fixedSize(horizontal: false, vertical: true)

            if let verdict {
                answered(item, verdict: verdict)
            } else {
                switch item.mode {
                case .choosing: choices(item)
                case .typing, .translating: typing(item)
                case .rearranging: rearranging(item)
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choices(_ item: PracticeItem) -> some View {
        VStack(spacing: 8) {
            ForEach(item.question?.choices ?? []) { choice in
                Button {
                    answer(choice.id == item.question?.answer.id ? .correct : .wrong)
                } label: {
                    Text(choice.sourceText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func typing(_ item: PracticeItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("The missing word", text: $typed)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("clozeAnswerField")
            Button("Check") {
                // A cloze asks for the missing word; a translation asks for
                // the card itself. Same normalisation either way.
                answer(
                    item.question.map { judgeClozeAnswer(typed, for: $0) }
                        ?? judgeSentenceAnswer(typed, for: item.card)
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(.primaryRed)
            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func rearranging(_ item: PracticeItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // The answer so far, on its own line so it reads as a sentence
            // rather than as a row of buttons.
            Text(assembled.joined(separator: " "))
                .font(AppFont.prompt)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Wrapping, because a sentence splits into twelve to fifteen pieces
            // and one scrolling row would hide most of them.
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(Array(available.enumerated()), id: \.offset) { index, piece in
                        Button(piece) { assembled.append(available.remove(at: index)) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxHeight: 180)

            HStack {
                Button("Check") { answer(judgeArrangement(assembled, for: item.card)) }
                    .buttonStyle(.borderedProminent)
                    .tint(.primaryRed)
                    .disabled(assembled.isEmpty)

                // Undoing one piece rather than starting over: a misplacement
                // near the end of fifteen should not cost the other fourteen.
                Button("Take back") { available.append(assembled.removeLast()) }
                    .buttonStyle(.bordered)
                    .disabled(assembled.isEmpty)
            }
        }
    }

    /// What the reader sees once they have answered.
    ///
    /// A wrong answer names the right one and the session carries on. It does
    /// not requeue the card here: the scheduler already sent it back to the
    /// first learning step, so it returns on its own a few minutes later —
    /// which is the whole reason the mistakes area was cancelled.
    private func answered(_ item: PracticeItem, verdict: TypedVerdict) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                verdict == .wrong
                    ? "The answer was \(item.question?.removed ?? item.card.sourceText)"
                    : "Correct",
                systemImage: verdict == .wrong ? "xmark.circle.fill" : "checkmark.circle.fill"
            )
            .font(AppFont.caption)
            .foregroundStyle(.grayFont)

            // Named rather than waved through. The answer counted — the reader
            // knew the word — but a lesson that said nothing here would be
            // teaching that Vietnamese tones are decoration.
            if verdict == .correctApartFromTones {
                Text("Watch the tones: \(item.question?.removed ?? item.card.sourceText)")
                    .font(AppFont.caption)
                    .foregroundStyle(.grayFont)
                    .accessibilityIdentifier("toneHint")
            }

            Text(item.card.translation)
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)

            Button("Next") { advance() }
                .buttonStyle(.borderedProminent)
                .tint(.primaryRed)
                .accessibilityIdentifier("nextQuestion")
        }
    }

    /// The end of the queue — the thing a fixed round could never say.
    @ViewBuilder
    private var closing: some View {
        VStack(spacing: 16) {
            // What graduated, not what was tapped. A session can be answered
            // perfectly and graduate nothing, if every card was met once — and
            // a reader told "10 / 10" would reasonably think they had finished
            // something.
            Text("\(outcome.graduated.count)")
                .font(AppFont.title)
            Text(
                outcome.graduated.count == 1
                    ? "word learned"
                    : "words learned"
            )
            .font(AppFont.caption)
            .foregroundStyle(.grayFont)

            if ended == .dayIsDone {
                Text("Nothing left for today.")
                    .font(AppFont.caption)
                    .foregroundStyle(.grayFont)
                    .accessibilityIdentifier("dayIsDone")
            }

            Button("Done") { onFinish() }
                .buttonStyle(.borderedProminent)
                .tint(.primaryRed)
                .accessibilityIdentifier("finishRound")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func answer(_ result: TypedVerdict) {
        verdict = result
        guard let item = current else { return }
        Task { await submit(item, correct: result.isCorrect) }
    }

    /// Records the answer, and lets the backend say what it changed.
    ///
    /// The new state is **read from the response** rather than recomputed here:
    /// both sides could derive it from the same rules, and a second
    /// implementation is exactly how the two come to disagree about where a
    /// card stands. (Ticket 07 does add a second one, on purpose and pinned by
    /// tests, because offline practice cannot ask.)
    ///
    /// A failure costs the record, not the session. The reader is mid-question
    /// and there is nothing they could do about it; the answer they gave stands
    /// on screen either way.
    private func submit(_ item: PracticeItem, correct: Bool) async {
        let result = try? await repository.recordReview(
            cardID: item.card.id,
            questionType: item.questionType,
            isCorrect: correct,
            clientToken: item.token,
            localDate: Date(),
            answeredAt: Date(),
            context: mode == .training ? .training : .review,
            elapsedMs: nil
        )
        if let result, let index = deck.firstIndex(where: { $0.id == item.card.id }) {
            // Training changes nothing on the server, and writing the response
            // back is how that stays true here too rather than only there.
            deck[index].apply(result)
        }
        outcome.record(
            correct: correct,
            cardID: item.card.id,
            state: result?.state ?? item.card.state
        )
    }

    private func advance() {
        lastCardID = current?.card.id
        typed = ""
        verdict = nil

        switch mode {
        case .scheduled:
            switch nextItem(
                from: deck,
                settings: settings,
                now: Date(),
                today: PracticeView.today(),
                avoiding: lastCardID
            ) {
            case .success(let item):
                current = item
            case .failure(let why):
                current = nil
                ended = why
            }
        case .training:
            current = nextTrainingItem(from: deck, avoiding: lastCardID)
            if current == nil { ended = .deckIsEmpty }
        }
        seedPieces()
    }

    /// Fills the piece rows for a rearrangement, and empties them otherwise so
    /// a stale arrangement cannot be checked against the next question.
    private func seedPieces() {
        guard let item = current, item.mode == .rearranging else {
            assembled = []
            available = []
            return
        }
        assembled = []
        available = shuffledPieces(of: item.card)
    }
}

#Preview {
    PracticeView()
}
