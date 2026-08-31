//
//  StudySettingsView.swift
//  vista_comic
//
//  The two numbers the reader owns: how long the learning steps are, and how
//  many new words a day.
//
//  **Not editable with no connection**, and that is a rule rather than an
//  omission. The backend recomputes schedules when an offline session flushes,
//  so two copies of these values that disagreed would produce two different due
//  times for the same answer. `OfflineFallbackStudyRepository` already refuses
//  to queue an edit to a card on the same grounds: an offline edit has no
//  derivable merge rule, only an invented one.
//

import SwiftUI

struct StudySettingsView: View {
    @Environment(\.studyRepository) private var repository
    @Environment(\.dismiss) private var dismiss

    /// Held as text rather than as `[Int]` so a half-typed list is a state the
    /// screen can be in. Parsing on every keystroke and snapping the field back
    /// would fight the reader mid-edit.
    @State private var stepsText = ""
    @State private var newCardsPerDay = StudySettings.fallback.newCardsPerDay
    @State private var state: LoadState<StudySettings> = .loading
    @State private var saveFailed = false

    private var parsedSteps: [Int]? { parseLearningSteps(stepsText) }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Practice settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .disabled(parsedSteps == nil)
                            .accessibilityIdentifier("saveSettings")
                    }
                }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
        case .failed:
            // Deliberately not an empty form. Showing the defaults here and
            // accepting a save would write values the reader never chose over
            // the ones they did.
            ContentUnavailableView(
                "Settings need a connection",
                systemImage: "wifi.slash",
                description: Text(
                    "These decide how every card is scheduled, so they are kept in one place rather than on this device."
                )
            )
        case .loaded:
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("5, 7, 10", text: $stepsText)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("learningStepsField")
                if parsedSteps == nil {
                    Label("Minutes, separated by commas — at least one.", systemImage: "exclamationmark.triangle")
                        .font(AppFont.caption)
                        .foregroundStyle(.grayFont)
                }
            } header: {
                Text("Learning steps")
            } footer: {
                // Said out loud because it is the least obvious consequence of
                // this field: the number of steps is the number of times a card
                // has to come back before it is scheduled in days at all.
                Text(
                    "A new card comes back after each of these, then graduates onto the day intervals. How many you list is how many times it comes back."
                )
            }

            Section {
                Stepper(
                    "\(newCardsPerDay) a day",
                    value: $newCardsPerDay,
                    in: 0...100
                )
                .accessibilityIdentifier("newCardsStepper")
            } header: {
                Text("New words")
            } footer: {
                Text(
                    "Unused ones do not carry over to tomorrow. Zero is a choice: clear what is due without meeting anything new."
                )
            }

            if saveFailed {
                Section {
                    Label("Could not save. Check the connection and try again.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.primaryRed)
                }
            }
        }
    }

    private func load() async {
        do {
            let current = try await repository.settings()
            stepsText = formatLearningSteps(current.learningSteps)
            newCardsPerDay = current.newCardsPerDay
            state = .loaded(current)
        } catch {
            state = .failed(error)
        }
    }

    private func save() async {
        guard let steps = parsedSteps else { return }
        do {
            _ = try await repository.updateSettings(
                StudySettings(learningSteps: steps, newCardsPerDay: newCardsPerDay)
            )
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}

#Preview {
    StudySettingsView()
}
