//
//  CardDetailView.swift
//  vista_comic
//
//  One card, and the two things the workshop exists to do to it: correct it or
//  throw it away.
//
//  **The source text is not editable, and that is the API of this screen.** It
//  is half the card's identity, so changing it could collide with another card
//  and would detach this one from the page reference still pointing at where
//  the line was read. A wrong source text means the card was wrong from the
//  start; deleting and re-collecting is cleaner and costs one more selection.
//
//  What *is* editable is the half that can be wrong. The reader corrected the
//  OCR before anything else happened, so the source is theirs; the translation
//  is the part they never fully trusted, and the kind is a choice between two
//  adjacent buttons that will sometimes be mis-tapped.
//

import SwiftUI

struct CardDetailView: View {
    let card: LearningCard
    /// Called with the corrected card so the list can swap it in place, rather
    /// than reloading and scrolling out from under the reader.
    let onChanged: (LearningCard) -> Void
    /// Called after a successful delete, for the same reason.
    let onDeleted: (LearningCard) -> Void

    @Environment(\.studyRepository) private var repository
    @Environment(\.dismiss) private var dismiss

    @State private var translation: String
    /// `nil` means unclassified — a real choice, not a missing one. Cards
    /// collected before the two save buttons have no answer, and a mis-tap
    /// needs to be undoable, so this picker can return to nothing.
    @State private var kind: CardKind?
    @State private var isSaving = false
    @State private var isConfirmingDelete = false
    @State private var isConfirmingReset = false
    @State private var failure: Failure?

    init(
        card: LearningCard,
        onChanged: @escaping (LearningCard) -> Void,
        onDeleted: @escaping (LearningCard) -> Void
    ) {
        self.card = card
        self.onChanged = onChanged
        self.onDeleted = onDeleted
        _translation = State(initialValue: card.translation)
        _kind = State(initialValue: card.kind)
    }

    /// What went wrong, and therefore what to say about it.
    private enum Failure: Identifiable {
        case couldNotSave
        case couldNotDelete
        case couldNotReset

        var id: Int {
            switch self {
            case .couldNotSave: 0
            case .couldNotDelete: 1
            case .couldNotReset: 2
            }
        }

        var message: LocalizedStringKey {
            // All three name the connection, because it is overwhelmingly the
            // reason and because these actions deliberately do not queue: the
            // reader needs to know it did not happen, not be reassured it will.
            switch self {
            case .couldNotSave: "Couldn't save. This needs a connection."
            case .couldNotDelete: "Couldn't delete. This needs a connection."
            case .couldNotReset: "Couldn't reset. This needs a connection."
            }
        }
    }

    var body: some View {
        Form {
            Section("Word") {
                Text(card.sourceText)
                    .font(AppFont.rowTitle)
                    .textSelection(.enabled)
            }

            Section("Meaning") {
                TextField("Meaning", text: $translation, axis: .vertical)
                    .lineLimit(1...4)
                    .accessibilityIdentifier("translationField")
            }

            Section("Type") {
                Picker("Type", selection: $kind) {
                    Text("Word").tag(CardKind?.some(.word))
                    Text("Sentence").tag(CardKind?.some(.sentence))
                    Text("Unclassified").tag(CardKind?.none)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("kindPicker")
            }

            Section("Where it came from") {
                if let source = card.sourceLabel {
                    // Only a link while the comic is still in the library: the
                    // stored ids would resolve to a route that then fails.
                    NavigationLink(value: card.source.peekRoute) {
                        Text("\(source) · p.\(card.pageNumber)")
                    }
                } else {
                    Text("This comic is no longer in your library.")
                        .font(AppFont.caption)
                        .foregroundStyle(.grayFont)
                }

                if card.lookupCount > 0 {
                    LabeledContent(
                        "Looked up again",
                        value: "\(card.lookupCount)×"
                    )
                }
            }

            // What the scheduler knows, said plainly. The adjectives that used
            // to be here — New, Learning, Familiar — were an alias for the slot
            // number, and a screen full of "Familiarity New" is what provoked
            // the stage 6 rewrite: the word read as a verdict on the reader
            // while describing a column that had not moved.
            Section("Where it stands") {
                LabeledContent(
                    "State",
                    value: scheduleState(of: card, steps: StudySettings.fallback.learningSteps)
                )
                LabeledContent("Interval", value: "\(card.ladderStage) / \(ladderTopRung)")
                LabeledContent("Next up", value: scheduleDue(of: card))
            }

            Section {
                // Not `.destructive`, unlike Delete below it. Both cost
                // something and neither can be undone, but the card survives
                // this one — two red buttons in a row would flatten a real
                // difference in what the reader is about to lose.
                Button("Reset progress") { isConfirmingReset = true }
                    .accessibilityIdentifier("resetCard")

                Button("Delete", role: .destructive) { isConfirmingDelete = true }
                    .accessibilityIdentifier("deleteCard")
            }
        }
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveCard")
            }
        }
        .disabled(isSaving)
        // An alert with two named choices, rather than an action sheet whose
        // only button is the destructive one. Deleting is irreversible and has
        // no undo — the lookup count and ladder position go with the row — so
        // the reader should be answering a question, not being handed a second
        // button that finishes what the first one started.
        .alert("Delete this card?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await remove() } }
        } message: {
            Text("How often you've looked it up goes too. You can collect it again later.")
        }
        // Says what actually happens rather than "are you sure": the reader is
        // choosing between two outcomes that both sound like starting over, and
        // the one that matters — the card queues behind the day's new words
        // instead of coming straight back — is not guessable from the button.
        .alert("Reset this card's progress?", isPresented: $isConfirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { Task { await resetProgress() } }
        } message: {
            Text("It goes back to new and waits for the day's new-word allowance. Your answers and lookups are kept.")
        }
        // A failed save keeps what was typed: the reader's correction is the
        // only copy of it, and discarding it to show an error would cost them
        // the work rather than just the save.
        .alert(item: $failure) { failure in
            Alert(title: Text(failure.message))
        }
    }

    private var canSave: Bool {
        let trimmed = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed != card.translation || kind != card.kind
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await repository.update(
                id: card.id,
                translation: translation.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: kind
            )
            onChanged(updated)
            dismiss()
        } catch {
            failure = .couldNotSave
        }
    }

    private func resetProgress() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let reset = try await repository.reset(id: card.id)
            // Reported and dismissed rather than shown here, exactly as `save`
            // does: `card` is a `let`, so this screen cannot redraw itself
            // around the new standing, and the list behind it can.
            onChanged(reset)
            dismiss()
        } catch {
            failure = .couldNotReset
        }
    }

    private func remove() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.delete(id: card.id)
            onDeleted(card)
            dismiss()
        } catch {
            failure = .couldNotDelete
        }
    }
}

#Preview {
    NavigationStack {
        CardDetailView(card: .preview(), onChanged: { _ in }, onDeleted: { _ in })
    }
}
