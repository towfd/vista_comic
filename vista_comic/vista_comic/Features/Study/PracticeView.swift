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
                RoundView(items: round) { self.round = nil }
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
            VStack(spacing: 16) {
                Text("Ready when you are.")
                    .font(AppFont.caption)
                    .foregroundStyle(.grayFont)
                Button("Start practice") { begin() }
                    .buttonStyle(.borderedProminent)
                    .tint(.primaryRed)
                    .accessibilityIdentifier("startPractice")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func begin() {
        guard case .loaded(let deck) = state else { return }
        switch makeRound(from: deck) {
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
            let cached = repository.knownCards()
            state = cached.isEmpty ? .failed(error) : .loaded(cached)
        }
        // Checked once here so the start screen can say which of the two
        // problems the reader actually has, before they tap anything.
        if case .loaded(let deck) = state, case .failure(let reason) = makeRound(from: deck) {
            unavailable = reason
        } else {
            unavailable = nil
        }
    }
}

/// One round, from the first question to the summary.
private struct RoundView: View {
    let items: [PracticeItem]
    let onFinish: () -> Void

    @State private var index = 0
    @State private var typed = ""
    /// `nil` while the question is open; set once answered, and what the screen
    /// shows instead of accepting another answer.
    @State private var verdict: TypedVerdict?
    @State private var outcome = RoundOutcome()

    var body: some View {
        if index >= items.count {
            summary
        } else {
            question(items[index])
        }
    }

    private func question(_ item: PracticeItem) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("\(index + 1) / \(items.count)")
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)

            Text(item.question.prompt)
                .font(AppFont.rowTitle)
                .fixedSize(horizontal: false, vertical: true)

            if let verdict {
                answered(item, verdict: verdict)
            } else {
                switch item.mode {
                case .choosing: choices(item)
                case .typing: typing(item)
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choices(_ item: PracticeItem) -> some View {
        VStack(spacing: 8) {
            ForEach(item.question.choices) { choice in
                Button {
                    answer(choice.id == item.question.answer.id ? .correct : .wrong)
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
                answer(judgeClozeAnswer(typed, for: item.question))
            }
            .buttonStyle(.borderedProminent)
            .tint(.primaryRed)
            .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    ? "The answer was \(item.question.removed)"
                    : "Correct",
                systemImage: verdict == .wrong ? "xmark.circle.fill" : "checkmark.circle.fill"
            )
            .font(AppFont.caption)
            .foregroundStyle(.grayFont)

            // Named rather than waved through. The answer counted — the reader
            // knew the word — but a lesson that said nothing here would be
            // teaching that Vietnamese tones are decoration.
            if verdict == .correctApartFromTones {
                Text("Watch the tones: \(item.question.removed)")
                    .font(AppFont.caption)
                    .foregroundStyle(.grayFont)
                    .accessibilityIdentifier("toneHint")
            }

            Text(item.question.card.translation)
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)

            Button(index + 1 == items.count ? "Finish" : "Next") { advance() }
                .buttonStyle(.borderedProminent)
                .tint(.primaryRed)
                .accessibilityIdentifier("nextQuestion")
        }
    }

    private var summary: some View {
        VStack(spacing: 16) {
            Text(outcome.allCorrect ? "All correct" : "\(outcome.correct) / \(outcome.total)")
                .font(AppFont.title)
            Button("Done") { onFinish() }
                .buttonStyle(.borderedProminent)
                .tint(.primaryRed)
                .accessibilityIdentifier("finishRound")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func answer(_ result: TypedVerdict) {
        verdict = result
        outcome.record(correct: result.isCorrect)
    }

    private func advance() {
        index += 1
        typed = ""
        verdict = nil
    }
}

#Preview {
    PracticeView()
}
