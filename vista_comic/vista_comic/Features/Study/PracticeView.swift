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
                    }
                    .buttonStyle(.commit)
                    .accessibilityIdentifier("startPractice")

                    Button {
                        start(.training)
                    } label: {
                        Label("Endless training", systemImage: "infinity")
                    }
                    .buttonStyle(.option)
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
    /// The rearrangement in progress. See `PieceTray`.
    @State private var tray = PieceTray()
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

    /// The cards this session still has to get through, including the one on
    /// screen — read off the same in-memory deck the queue is built from, which
    /// every answer updates from the response. So it moves with no refetch and
    /// stays right with no network, and it reaches zero at the same moment the
    /// closing screen appears.
    private var remaining: Int {
        remainingCards(
            from: deck, settings: settings, now: Date(), today: PracticeView.today()
        )
    }

    private func question(_ item: PracticeItem) -> some View {
        // Centred rather than ragged-left. Everything here is one thing at a
        // time — a sentence, then the ways to answer it — and a column pinned to
        // the left edge of a phone reads as a form to fill in rather than as a
        // question to answer.
        VStack(alignment: .center, spacing: 20) {
            HStack {
                Text("\(outcome.total) answered")

                // Only where there is an end to be near. 永無止盡的訓練 has no
                // remaining anything — that is the mode — and a count there
                // would be a pool size dressed up as a finish line.
                if mode == .scheduled {
                    Text("\(remaining) left")
                        .accessibilityIdentifier("cardsRemaining")
                }

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
                .multilineTextAlignment(.center)
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
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func choices(_ item: PracticeItem) -> some View {
        VStack(spacing: 14) {
            ForEach(item.question?.choices ?? []) { choice in
                Button {
                    answer(choice.id == item.question?.answer.id ? .correct : .wrong)
                } label: {
                    Text(choice.sourceText)
                }
                .buttonStyle(.option)
            }
        }
    }

    private func typing(_ item: PracticeItem) -> some View {
        VStack(spacing: 14) {
            TextField("The missing word", text: $typed)
                .font(AppFont.choice)
                .multilineTextAlignment(.center)
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
            .buttonStyle(.commit)
            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func rearranging(_ item: PracticeItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // The answer so far, as pieces rather than as a finished line.
            // Tapping one takes it back; holding one moves it, and the rest of
            // the row gets out of its way while the finger is down.
            PlacedPiecesRow(
                pieces: tray.placedPieces,
                takeBack: { tray.takeBack(at: $0) },
                move: { tray.move(from: $0, before: $1) }
            )
            .frame(minHeight: 44, alignment: .topLeading)
            .accessibilityIdentifier("assembledPieces")

            // Said, because both gestures are invisible otherwise — and the
            // second one was invisible enough that the reader asked for a
            // feature the screen already had.
            if !tray.isEmpty {
                Text("Tap a word to take it back. Hold one to move it.")
                    .font(AppFont.caption)
                    .foregroundStyle(.grayFont)
            }

            Divider()

            // Scrolls only when it has to. Each word is its own width now, so a
            // twelve-piece sentence fits where the grid's equal columns did not
            // — and the strip that had to be scrolled to read was the reader's
            // second complaint about this screen.
            ScrollView {
                PiecePool(
                    pieces: tray.availablePieces,
                    place: { tray.place(from: $0) }
                )
            }
            .frame(maxHeight: 300)

            Button("Check") { answer(judgeArrangement(tray.placed, for: item.card)) }
                .buttonStyle(.commit)
                .disabled(tray.isEmpty)
        }
    }

    /// What the reader sees once they have answered.
    ///
    /// A wrong answer names the right one and the session carries on. It does
    /// not requeue the card here: the scheduler already sent it back to the
    /// first learning step, so it returns on its own a few minutes later —
    /// which is the whole reason the mistakes area was cancelled.
    private func answered(_ item: PracticeItem, verdict: TypedVerdict) -> some View {
        VStack(spacing: 12) {
            // **The sentence, with nothing in front of it.** "The answer was"
            // was three words of preamble on the one line the reader is here to
            // read, and the colour has already said which way it went.
            if verdict == .wrong {
                Text(item.question?.removed ?? item.card.sourceText)
                    .font(AppFont.prompt)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.primaryRed)
            } else {
                Label("Correct", systemImage: "checkmark.circle.fill")
                    .font(AppFont.choice)
                    .foregroundStyle(Color.practiceTeal)
            }

            // Named rather than waved through. The answer counted — the reader
            // knew the word — but a lesson that said nothing here would be
            // teaching that Vietnamese tones are decoration.
            if verdict == .correctApartFromTones {
                Text("Watch the tones: \(item.question?.removed ?? item.card.sourceText)")
                    .font(AppFont.caption)
                    .foregroundStyle(.grayFont)
                    .accessibilityIdentifier("toneHint")
            }

            // The meaning, at a size it can be read at. It was a 12pt caption
            // under a 26pt sentence, which made the half that explains the
            // other half the smallest thing on the screen.
            Text(item.card.translation)
                .font(AppFont.explanation)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.grayFont)

            Button("Next") { advance() }
                .buttonStyle(.commit)
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
                .buttonStyle(.commit)
                .padding(.horizontal, 40)
                .accessibilityIdentifier("finishRound")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func answer(_ result: TypedVerdict) {
        verdict = result
        guard let item = current else { return }
        let moment = Date()

        // **The deck moves now, not when the response comes back.**
        //
        // The queue is built from this deck, and the submission below is a
        // round trip that "Next" does not wait for — so a slow one, or one that
        // never arrives, used to leave a card sitting here as due when the
        // server had already scheduled it days out. The session would then
        // offer it again and the second answer would be taken as a real one,
        // which is how a card graduated onto one day was promoted to three.
        //
        // Computed with the same table the server runs (`Scheduler.swift`),
        // which the offline path has always used. The server's outcome
        // overwrites this the moment it arrives; until then this is what the
        // queue reads, rather than something known to be out of date.
        if mode == .scheduled, let index = deck.firstIndex(where: { $0.id == item.card.id }) {
            deck[index].apply(
                nextSchedule(
                    deck[index].scheduling,
                    correct: result.isCorrect,
                    answeredAt: moment,
                    learningSteps: settings.learningSteps
                ),
                introducedOn: PracticeView.today()
            )
        }

        Task { await submit(item, correct: result.isCorrect, at: moment) }
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
    /// on screen either way — and `answer(_:)` has already moved the card, so a
    /// failure no longer leaves the queue believing it is still due.
    ///
    /// `moment` is passed in rather than read here, so that what the server is
    /// told and what the deck was moved with are the same instant.
    private func submit(_ item: PracticeItem, correct: Bool, at moment: Date) async {
        let result = try? await repository.recordReview(
            cardID: item.card.id,
            questionType: item.questionType,
            isCorrect: correct,
            clientToken: item.token,
            localDate: moment,
            answeredAt: moment,
            context: mode == .training ? .training : .review,
            elapsedMs: nil
        )
        if let result, let index = deck.firstIndex(where: { $0.id == item.card.id }) {
            // The server's answer wins over the one computed on tapping.
            // Training changes nothing on the server, and writing the response
            // back is how that stays true here too rather than only there.
            deck[index].apply(result)
        }
        outcome.record(
            correct: correct,
            cardID: item.card.id,
            // The card as it now stands: the server's word if it arrived, and
            // otherwise the local move, which is what the session is running on.
            state: deck.first(where: { $0.id == item.card.id })?.state ?? item.card.state
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
            tray = PieceTray()
            return
        }
        tray = PieceTray(available: shuffledPieces(of: item.card))
    }
}

#Preview {
    PracticeView()
}
