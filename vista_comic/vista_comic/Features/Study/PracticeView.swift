//
//  PracticeView.swift
//  vista_comic
//
//  練習 tab content (`vocabulary-review` stage 3, ticket 03).
//
//  **The first time this app asks the reader anything.** Three stages in, it
//  collects words and lets them be repaired, and the question the whole PRD
//  exists to answer — will they come back? — has had nothing to come back to.
//
//  It has a tab of its own rather than sitting behind 單字庫, because practice
//  is the point of the system and 單字庫 is a workshop the reader should rarely
//  need. Putting the daily thing behind the rare thing would mean walking
//  through the empty room to reach it.
//
//  **Nothing is recorded.** A round is a toy: it proves the questions are
//  answerable and worth answering, and stage 4 is where results start to mean
//  something. Leaving mid-round therefore starts a new one on return — there is
//  nothing to resume from, and pretending otherwise would need exactly the
//  storage this stage is deliberately doing without.
//

import SwiftUI

struct PracticeView: View {
    @Environment(\.studyRepository) private var repository
    @State private var state: LoadState<[LearningCard]> = .loading
    @State private var round: [PracticeItem]?
    @State private var unavailable: RoundUnavailable?

    var body: some View {
        NavigationStack {
            content.navigationTitle("Practice")
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ErrorStateView { Task { await load() } }
        case .loaded:
            if let round {
                RoundView(items: round, repository: repository) { self.round = nil }
            } else {
                start
            }
        }
    }

    @ViewBuilder
    private var start: some View {
        switch unavailable {
        case .tooFewCards(let needed):
            ContentUnavailableView(
                "Not enough words yet",
                systemImage: "text.book.closed",
                description: Text("Collect \(needed) more while reading, then come back.")
            )
        case .noSentencesWithKnownWords:
            // Worded apart from "not enough words" on purpose: this reader has
            // cards, and telling them to collect more would send them to the
            // wrong action. What is missing is a *sentence* holding a word they
            // already have.
            ContentUnavailableView(
                "Nothing to practise yet",
                systemImage: "text.quote",
                description: Text(
                    "Add a sentence that contains one of your words, and it becomes a question."
                )
            )
        case nil:
            if case .loaded(let deck) = state {
                RoundCard(summary: DeckSummary(deck: deck), play: begin)
            }
        }
    }

    /// The reader's local day, as the backend groups practice by.
    ///
    /// Deliberately not UTC: on UTC+8 a UTC boundary would reset the day at
    /// eight in the morning, so a card passed before breakfast could be passed
    /// again after it.
    static func today() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func begin() {
        guard case .loaded(let deck) = state else { return }
        switch makeRound(from: deck, today: Self.today()) {
        case .success(let items): round = items
        case .failure(let reason): unavailable = reason
        }
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
        // Checked once here so the start screen can say which of the two
        // problems the reader actually has, before they tap anything.
        if case .loaded(let deck) = state,
           case .failure(let reason) = makeRound(from: deck, today: Self.today()) {
            unavailable = reason
        } else {
            unavailable = nil
        }
    }
}

/// The card the reader sees before playing, and the thing they tap.
///
/// **Every figure on it is real.** Nothing here is a streak, a score or a daily
/// goal: this stage records nothing, so anything of that sort would be
/// decoration dressed as progress — and this app has already shipped two
/// features that were looked at rather than used.
///
/// It is a card rather than a bare button because the round has properties
/// worth seeing before committing to it, and because the things stage 4 and
/// stage 8 will add — how familiar these words are, how many days in a row —
/// belong in the same frame rather than scattered around it.
private struct RoundCard: View {
    let summary: DeckSummary
    let play: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(alignment: .leading, spacing: 20) {
                Text("TODAY'S ROUND")
                    .font(AppFont.caption)
                    .foregroundStyle(.grayFont)
                    .kerning(1.5)

                // Five dots for five questions: the round's size, shown rather
                // than stated. In stage 4 these become the reader's progress
                // through it.
                HStack(spacing: 10) {
                    ForEach(0..<practiceRoundLength, id: \.self) { _ in
                        Circle()
                            .fill(Color.primaryRed)
                            .frame(width: 12, height: 12)
                    }
                }

                Text("\(practiceRoundLength) questions")
                    .font(AppFont.prompt)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    figure("\(summary.usableSentences)", "sentences ready")
                    figure("\(summary.words)", "words collected")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal)

            Spacer()

            Button {
                play()
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(AppFont.prompt)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primaryRed)
            .padding(.horizontal)
            .padding(.bottom)
            .accessibilityIdentifier("startPractice")
        }
    }

    private func figure(_ value: String, _ label: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value).font(AppFont.statistic)
            Text(label).font(AppFont.caption).foregroundStyle(.grayFont)
        }
    }
}

/// One round, from the first question to the summary.
private struct RoundView: View {
    let items: [PracticeItem]
    let repository: any StudyRepository
    let onFinish: () -> Void

    /// The order still to be asked. A wrong answer goes back on the end rather
    /// than being dropped, so the round ends only when everything has been
    /// answered correctly once — the reader never leaves having simply failed
    /// at something, which is also why the ladder can afford to be strict about
    /// that first wrong answer.
    @State private var queue: [PracticeItem] = []
    @State private var asked = 0
    @State private var typed = ""
    /// The rearrangement in progress: what has been placed, and what is left.
    @State private var assembled: [String] = []
    @State private var available: [String] = []
    /// `nil` while the question is open; set once answered, and what the screen
    /// shows instead of accepting another answer.
    @State private var verdict: TypedVerdict?
    @State private var outcome = RoundOutcome()

    var body: some View {
        if let current = queue.first {
            question(current)
        } else {
            summary
        }
        // Seeded here rather than in an initialiser so the queue survives the
        // view being rebuilt, which SwiftUI does freely.
        Color.clear.frame(height: 0).task {
            if queue.isEmpty && asked == 0 {
                queue = items
                seedPieces()
            }
        }
    }

    private func question(_ item: PracticeItem) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Counts what is left rather than where the reader is, because a
            // requeued item makes the second number move — and a progress
            // readout that goes backwards reads as a bug.
            Text("\(items.count - queue.count + 1) of \(items.count)")
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
            .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// Pieces to put in order, and the sentence being built from them.
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
    /// A wrong answer names the right one and the round carries on. Repeating
    /// until correct belongs with the three-step day, in stage 4 — here it would
    /// be a rule with nothing behind it.
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

            Button(queue.count == 1 ? "Finish" : "Next") { advance() }
                .buttonStyle(.borderedProminent)
                .tint(.primaryRed)
                .accessibilityIdentifier("nextQuestion")
        }
    }

    private var summary: some View {
        VStack(spacing: 16) {
            // What passed, not what was tapped. A round can be answered
            // perfectly and pass nothing, if every card was seen once — and a
            // reader told "10 / 10" would reasonably think they had finished
            // something.
            Text("\(outcome.passed.count)")
                .font(AppFont.title)
            Text(
                outcome.passed.count == 1
                    ? "word done for today"
                    : "words done for today"
            )
            .font(AppFont.caption)
            .foregroundStyle(.grayFont)
            Button("Done") { onFinish() }
                .buttonStyle(.borderedProminent)
                .tint(.primaryRed)
                .accessibilityIdentifier("finishRound")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func answer(_ result: TypedVerdict) {
        verdict = result
        asked += 1
        guard let item = queue.first else { return }
        Task { await submit(item, correct: result.isCorrect) }
    }

    /// Records the answer, and lets the backend say what it changed.
    ///
    /// The step and the rung are **read from the response** rather than
    /// recomputed here: both sides could derive them from the same rules, and a
    /// second implementation is exactly how the two come to disagree about
    /// whether the reader passed something.
    ///
    /// A failure costs the record, not the round. The reader is mid-question
    /// and there is nothing they could do about it; the answer they already
    /// gave stands on screen either way.
    private func submit(_ item: PracticeItem, correct: Bool) async {
        let result = try? await repository.recordReview(
            cardID: item.card.id,
            questionType: item.questionType,
            isCorrect: correct,
            clientToken: item.token,
            localDate: Date(),
            elapsedMs: nil
        )
        outcome.record(
            correct: correct,
            cardID: item.card.id,
            step: result?.step ?? .unknown
        )
    }

    private func advance() {
        guard let finished = queue.first else { return }
        queue.removeFirst()
        // Wrong answers come back. A fresh item, so its token differs and the
        // second attempt is recorded as its own answer rather than swallowed as
        // a replay of the first.
        if verdict == .wrong {
            queue.append(
                PracticeItem(
                    card: finished.card,
                    question: finished.question,
                    mode: finished.mode,
                    isDue: finished.isDue
                )
            )
        }
        typed = ""
        verdict = nil
        seedPieces()
    }

    /// Fills the piece rows for a rearrangement, and empties them otherwise so
    /// a stale arrangement cannot be checked against the next question.
    private func seedPieces() {
        guard let item = queue.first, item.mode == .rearranging else {
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
