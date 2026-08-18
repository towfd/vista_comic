//
//  ChapterDownloadButton.swift
//  vista_comic
//
//  The download affordance on a chapter row (`offline-download` ticket 01):
//  one control that both *shows* which of the four states a chapter is in and
//  *acts* on it — start, cancel, retry.
//
//  Its own view rather than a branch inside `ChapterListView` for two reasons:
//  the row's job is to describe a chapter and push the reader, and this is a
//  second, unrelated action with its own hit target; and ticket 06's batch
//  selection needs the same states drawn in a second place.
//
//  Takes its state and its actions as parameters, so nothing about downloading
//  is hard-coded inside it — a preview renders every state with no store, no
//  network and no manager.
//

import SwiftUI

struct ChapterDownloadButton: View {
    let state: ChapterDownloadState
    let start: () -> Void
    let cancel: () -> Void

    var body: some View {
        Button(action: act) {
            symbol
                // A fixed box so a row's height never changes with its download
                // state, and so the tap target stays comfortable while the ring
                // inside it is small.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // Plain, because the row is a `NavigationLink`: a bordered button
        // inside one styles itself as part of the link and taps land on the
        // wrong target.
        .buttonStyle(.plain)
        .disabled(state == .downloaded)
        .accessibilityLabel(accessibilityLabel)
    }

    private func act() {
        switch state {
        case .notDownloaded, .failed: start()
        case .downloading: cancel()
        case .downloaded: break
        }
    }

    @ViewBuilder
    private var symbol: some View {
        switch state {
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(Color(.grayFont))
        case .downloading:
            progressRing
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(.grayFont))
        case .failed:
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(Color(.primaryRed))
        }
    }

    /// A ring that fills as pages arrive, with a stop mark in the middle so the
    /// same control that reports progress is the one that cancels it.
    ///
    /// Drawn rather than a `ProgressView`: the determinate circular style is not
    /// available on iOS, and a linear bar in a 44pt row would be either
    /// unreadable or the widest thing on the row.
    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color(.grayFont).opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: state.fraction)
                .stroke(
                    Color(.primaryRed),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                // Starts at the top rather than at three o'clock, which is where
                // a fill that is meant to read as a clock has to start.
                .rotationEffect(.degrees(-90))
            Image(systemName: "square.fill")
                .font(.system(size: 7))
                .foregroundStyle(Color(.primaryRed))
        }
        .frame(width: 20, height: 20)
    }

    private var accessibilityLabel: String {
        switch state {
        case .notDownloaded: return String(localized: "Download chapter")
        case .downloading: return String(localized: "Cancel download")
        case .downloaded: return String(localized: "Downloaded")
        case .failed: return String(localized: "Retry download")
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        ChapterDownloadButton(state: .notDownloaded, start: {}, cancel: {})
        ChapterDownloadButton(state: .downloading(completed: 0, total: 0), start: {}, cancel: {})
        ChapterDownloadButton(state: .downloading(completed: 7, total: 12), start: {}, cancel: {})
        ChapterDownloadButton(state: .downloaded, start: {}, cancel: {})
        ChapterDownloadButton(state: .failed, start: {}, cancel: {})
    }
}
