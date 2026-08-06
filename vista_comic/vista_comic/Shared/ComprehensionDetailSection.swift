//
//  ComprehensionDetailSection.swift
//  vista_comic
//
//  The 深度解釋 section: the one place the deeper explanation renders, and the
//  one place its absence is explained. Lives in `Shared/` (alongside
//  `ErrorStateView`) rather than under `Features/ComicPage/`, because the
//  reader's result sheet and the 歷史紀錄 detail screen must render *identical*
//  states — the two screens should teach each other rather than each inventing
//  a vocabulary for "still coming" versus "never coming".
//
//  It replaces M9's verdict banner, which conflated two questions. "Is more
//  coming?" is answered here, standing exactly where the answer will appear.
//  "Which translation am I reading?" is answered by `ProvenanceChip` below, on
//  the translation itself.
//

import SwiftUI

/// Everything the 深度解釋 section can be showing, as one closed set.
///
/// Deliberately its own vocabulary rather than `ComprehensionStatus` directly:
/// the section also has to render the case where **no record exists at all**
/// (the enqueue itself was refused), which is not a status any record can hold.
/// Folding both into one type is what lets the screen keep a single slot.
enum ComprehensionSectionState: Equatable {
    /// `pending` or `running` — deliberately **not** distinguished. A queue
    /// position is not something the reader can act on, so telling them apart
    /// would add a word and no decision.
    case inProgress
    /// `ok`: the explanation landed. At least one field is non-`nil`.
    case explained(grammarNotes: String?, contextNotes: String?, toneRegister: String?)
    /// No explanation, and none is coming without action.
    case unavailable(Reason)

    /// Why there is no explanation. Split by whether retrying can possibly
    /// help — the same rule applied everywhere else in this flow, and the
    /// thing that decides whether a retry is offered at all.
    enum Reason: Equatable {
        /// The record exists and `failed`: network/server/API trouble.
        case failed
        /// The record exists and the model `declined` to explain this
        /// selection. Retrying would spend another request to receive the same
        /// verdict, so no retry.
        case declined
        /// No record: today's request budget was already spent at enqueue.
        /// Permanent until tomorrow.
        case quotaExhausted
        /// No record: the enqueue itself failed for a transient reason.
        case enqueueFailed

        var allowsRetry: Bool {
            switch self {
            case .failed, .enqueueFailed: return true
            case .declined, .quotaExhausted: return false
            }
        }
    }

    /// Maps a record onto what to show for it.
    ///
    /// `ok` without any note field is treated as `.failed` rather than as an
    /// empty explanation: the reader would otherwise get a heading with nothing
    /// under it, and a retry is the honest offer.
    init(record: ComprehensionRecord) {
        switch record.status {
        case .pending, .running, .unknown:
            self = .inProgress
        case .ok where record.hasExplanation:
            self = .explained(
                grammarNotes: record.grammarNotes,
                contextNotes: record.contextNotes,
                toneRegister: record.toneRegister
            )
        case .ok, .failed:
            self = .unavailable(.failed)
        case .declined:
            self = .unavailable(.declined)
        }
    }
}

/// Renders one `ComprehensionSectionState` under a `深度解釋` heading.
///
/// `retry` is supplied by the host because the two retryable reasons retry
/// *different things* — a `failed` record is re-enqueued on the backend,
/// whereas a failed enqueue means running the whole translate action again.
/// The button appears only when the reason allows it and a host action exists.
struct ComprehensionDetailSection: View {
    let state: ComprehensionSectionState
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deeper explanation")
                .font(AppFont.rowTitle)

            switch state {
            case .inProgress:
                // The reader is explicitly told they may leave: the backend
                // finishes this whether or not the screen stays open, and not
                // saying so is what makes people sit and wait.
                Label {
                    Text("Being written. You can close this — it'll be waiting in 歷史紀錄.")
                } icon: {
                    ProgressView()
                }
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)

            case .explained(let grammarNotes, let contextNotes, let toneRegister):
                VStack(alignment: .leading, spacing: 12) {
                    if let grammarNotes {
                        explanationField(titleKey: "Grammar notes", text: grammarNotes)
                    }
                    if let contextNotes {
                        explanationField(titleKey: "Context notes", text: contextNotes)
                    }
                    if let toneRegister {
                        explanationField(titleKey: "Tone & register", text: toneRegister)
                    }
                }

            case .unavailable(let reason):
                VStack(alignment: .leading, spacing: 8) {
                    message(for: reason)
                        .font(AppFont.caption)
                        .foregroundStyle(.grayFont)
                    if reason.allowsRetry, let retry {
                        Button("Retry", action: retry)
                            .font(AppFont.caption)
                            .foregroundStyle(.primaryRed)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Distinct, localization-ready copy per reason — never collapsed into one
    /// generic "no explanation" message, matching how this flow already treats
    /// `OCRRecognitionError` and `TranslationError`. A content decline and a
    /// spent budget are different facts about the reader's day.
    @ViewBuilder
    private func message(for reason: ComprehensionSectionState.Reason) -> some View {
        switch reason {
        case .failed:
            Text("The explanation couldn't be written. Your translation above is unaffected.")
        case .declined:
            Text("No explanation was written for this selection. Trying again would return the same answer.")
        case .quotaExhausted:
            Text("Today's explanation limit is used up, so this selection wasn't saved to 歷史紀錄. The limit resets tomorrow.")
        case .enqueueFailed:
            Text("This selection couldn't be sent for an explanation, so it isn't in 歷史紀錄.")
        }
    }

    /// Same shape as `SavedTranslationRow.explanationField`, so an explanation
    /// reads identically wherever it appears.
    private func explanationField(titleKey: LocalizedStringKey, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titleKey)
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)
            Text(text)
                .font(AppFont.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Says which translation is on screen, so the text changing under the reader
/// once the cloud version lands is legible rather than startling.
///
/// A chip on the translation column rather than a banner: it labels the thing
/// it describes, and it is the half of M9's verdict banner that was actually
/// about the translation.
struct TranslationProvenanceChip: View {
    /// `true` once the record carries a cloud translation.
    let isCloud: Bool

    var body: some View {
        Label {
            Text(isCloud ? "Cloud" : "On device")
        } icon: {
            Image(systemName: isCloud ? "cloud" : "iphone")
        }
        .font(.system(size: 10))
        .foregroundStyle(.grayFont)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.gray.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityIdentifier(isCloud ? "provenance.cloud" : "provenance.onDevice")
    }
}

#Preview("In progress") {
    ComprehensionDetailSection(state: .inProgress).padding()
}

#Preview("Explained") {
    ComprehensionDetailSection(
        state: .explained(
            grammarNotes: "Subject-verb-object order; \"cảm ơn\" is a set greeting phrase.",
            contextNotes: "The previous panel shows the speaker bowing, so \"anh\" refers to the older man.",
            toneRegister: "Polite and slightly formal — appropriate to a stranger."
        )
    )
    .padding()
}

#Preview("Failed") {
    ComprehensionDetailSection(state: .unavailable(.failed), retry: {}).padding()
}

#Preview("Declined") {
    ComprehensionDetailSection(state: .unavailable(.declined), retry: {}).padding()
}

#Preview("Quota exhausted") {
    ComprehensionDetailSection(state: .unavailable(.quotaExhausted), retry: {}).padding()
}
