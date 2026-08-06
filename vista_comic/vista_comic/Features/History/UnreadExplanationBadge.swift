//
//  UnreadExplanationBadge.swift
//  vista_comic
//
//  The number on the 歷史紀錄 tab, and the only thing in this app that keeps
//  state two screens share (`comprehension-response-ux` ticket 22).
//
//  **This reverses a decision in the spec**, which said each screen fetches for
//  itself and the badge refreshes when the tab appears. Shipped, that gave the
//  badge a refresh policy that could only learn something had arrived at the
//  moments the reader no longer needed telling: translate, dismiss the sheet,
//  keep reading, and nothing fetched the list until the reader opened the very
//  tab the badge was supposed to send them to.
//
//  The per-screen-fetch rule was right for the *list*, which only matters while
//  it is on screen, and wrong for the *badge*, whose whole job is to speak while
//  the reader is somewhere else. So the badge is owned by the tab shell and kept
//  current two ways:
//
//  - `refresh()` on launch and on return to the foreground, catching whatever
//    finished while the app was dead or backgrounded.
//  - `watch(_:)` on a record still in flight when the reader **dismisses** the
//    result sheet, polling until the backend reaches a terminal status.
//
//  The handoff is at dismissal, not at translate, and that boundary is the whole
//  design: while the sheet is open the reader's own screen owns the wait and an
//  arrival counts as read; the moment they leave, this takes over and an arrival
//  counts as missed. Exactly one of the two is ever waiting, so they cannot race
//  to a contradictory answer — an earlier version started both at translate and
//  would light the badge for the explanation the reader was in the middle of
//  reading.
//
//  Each covers the other's hole: watching alone loses anything enqueued before a
//  relaunch, and refreshing alone either misses the arrival by minutes or polls
//  all day to avoid it. **Nothing in flight means no polling at all** — on a day
//  the reader never translates, this makes one request at launch and stops.
//
//  Kept to the size of the job on purpose: a count, a recount from a list a
//  screen already holds, and a watch on one record. It is the codebase's first
//  `@Observable`, which is worth saying out loud rather than smuggling in.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class UnreadExplanationBadge {
    /// What the tab shows. `0` renders no badge, so an empty or failed load
    /// simply shows nothing rather than a misleading zero.
    private(set) var count = 0

    /// Records being polled right now, so translating the same selection twice
    /// — or returning to a screen that re-announces its record — cannot start a
    /// second loop for one id.
    private var watched: Set<Int> = []

    /// How often a watched record is checked. The same interval the result
    /// screen polls at, because it is the same wait seen from two places.
    private let pollInterval: Duration

    /// How long one watch may run before giving up.
    ///
    /// A bound is load-bearing here in a way it was not on the result screen,
    /// whose identical loop was bounded by the sheet closing. This object lives
    /// as long as the app, so a record that never reaches a terminal status —
    /// deleted while pending, orphaned by a worker that died, or carrying a
    /// status this build does not recognise — would otherwise be polled until
    /// the process ends.
    ///
    /// Ten minutes is comfortably past any real job: the spec's worst case is a
    /// 120s per-attempt timeout with the SDK's own retries, roughly six minutes.
    /// Giving up still recounts, so a record that *did* finish unnoticed is
    /// picked up rather than lost.
    private let watchTimeout: Duration

    /// Injected so tests drive the loop in real time rather than real minutes —
    /// the seam `awaitExplanation` already established.
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        pollInterval: Duration = .seconds(3),
        watchTimeout: Duration = .seconds(600),
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.pollInterval = pollInterval
        self.watchTimeout = watchTimeout
        self.sleep = sleep
    }

    /// Recounts from a list the caller already has.
    ///
    /// 歷史紀錄 calls this with the list it just fetched, so the tab that is on
    /// screen costs no extra request — and so the badge and the list it points
    /// at can never disagree about what is unread.
    func recount(from records: [ComprehensionRecord]) {
        count = unreadExplanationCount(in: records)
    }

    /// Fetches the list purely to recount it.
    ///
    /// Failure leaves the previous count standing rather than zeroing it: the
    /// badge going quiet must mean "nothing is waiting", never "the request
    /// failed" — the same rule that stops the list degrading a read failure
    /// into an empty state.
    func refresh(using repository: any ComprehensionRepository) async {
        guard let records = try? await repository.list() else { return }
        recount(from: records)
    }

    /// Follows one record until the backend is finished with it, then recounts.
    ///
    /// Deliberately does **not** mark anything read — that is what makes this
    /// different from `awaitExplanation`, which runs while the reader is
    /// watching and can therefore say they have seen it. An explanation this
    /// watch sees land is one the reader missed, which is exactly what the
    /// badge is for.
    ///
    /// Owned by this object rather than by the view that hands the record over,
    /// so dismissing the result sheet does not cancel the wait that dismissal
    /// started.
    func watch(_ record: ComprehensionRecord, using repository: any ComprehensionRepository) {
        guard record.status.isInProgress, !watched.contains(record.id) else { return }
        watched.insert(record.id)

        Task { [weak self] in
            guard let self else { return }
            // The timeout races the poll rather than being checked inside it, so
            // a loop that is wedged on an id the backend will never finish is
            // abandoned rather than merely asked to stop.
            _ = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
                group.addTask { @MainActor in
                    _ = await awaitRecordFinishing(
                        for: record.id,
                        using: repository,
                        pollInterval: self.pollInterval,
                        sleep: self.sleep
                    )
                    return true
                }
                group.addTask { @MainActor in
                    try? await self.sleep(self.watchTimeout)
                    return false
                }
                let finished = await group.next() ?? false
                group.cancelAll()
                return finished
            }
            // Recount before clearing the flag, so anything waiting on the watch
            // to end sees the number it produced — and so a second `watch` for
            // this id cannot slip in mid-refresh.
            await refresh(using: repository)
            watched.remove(record.id)
        }
    }

    /// Whether a record is currently being polled. Test-facing: the guarantee
    /// worth asserting is that the loop *stops*, and that nothing in flight
    /// means no polling.
    var isWatching: Bool { !watched.isEmpty }
}

// MARK: - Environment injection

private struct UnreadExplanationBadgeKey: EnvironmentKey {
    /// A standing badge that no one refreshes, so a `#Preview` or a screen
    /// outside the tab shell renders with no badge instead of reaching the
    /// network. Only `RootTabView` installs a real one.
    @MainActor static let defaultValue = UnreadExplanationBadge()
}

extension EnvironmentValues {
    /// The unread count the 歷史紀錄 tab displays.
    var unreadExplanationBadge: UnreadExplanationBadge {
        get { self[UnreadExplanationBadgeKey.self] }
        set { self[UnreadExplanationBadgeKey.self] = newValue }
    }
}
