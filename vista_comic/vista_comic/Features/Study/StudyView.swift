//
//  StudyView.swift
//  vista_comic
//
//  單字庫 tab content (`vocabulary-review` stage 2, ticket 03), taking the slot
//  歷史紀錄 held. Follows `HomeView`'s `LoadState`-driven wiring and carries its
//  own `NavigationStack` — each tab is its own navigation context.
//
//  **This is a workshop, not a display case**, and the difference decides what
//  belongs here. Its job is letting the reader find a card and fix it; seeing
//  familiarity and lookup counts is a small pleasure on top, not the reason to
//  open it. Two features that existed to be browsed — 單字本 and then 歷史紀錄 —
//  both went unused and were deleted, and building a third would be the same
//  wrong bet. **Rarely opening a workshop is success**: it means nothing is
//  broken.
//
//  So the two things that matter are search and grouping, because they answer
//  the only two ways a reader arrives: "I just mis-tapped" (it is at the top)
//  and "I remember one of these being wrong" (search for it).
//
//  This screen finds; `CardDetailView` acts. Tapping a row opens the card
//  rather than jumping straight to the page it came from — in a workshop the
//  reason to tap something is to work on it, and the jump is still one tap
//  further in.
//

import SwiftUI

struct StudyView: View {
    @Environment(\.studyRepository) private var repository
    @Environment(\.scenePhase) private var scenePhase
    @State private var state: LoadState<[LearningCard]> = .loading
    @State private var query = ""
    /// True when the list on screen came from the local snapshot rather than
    /// the backend. Shown, because a workshop that quietly serves stale data is
    /// worse than one that says so.
    @State private var isOffline = false

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: LearningCard.self) { card in
                    CardDetailView(
                        card: card,
                        onChanged: { replace($0) },
                        onDeleted: { remove($0) }
                    )
                }
                // The detail screen's jump-back pushes onto *this* tab's stack,
                // exactly as 歷史紀錄's did: each tab is its own navigation
                // context, so peeking at an old page never touches 書庫's.
                .navigationDestination(for: ReaderRoute.self) { route in
                    ComicView(
                        comicID: route.comicID,
                        chapterID: route.chapterID,
                        targetPage: route.targetPage,
                        isPeek: route.isPeek
                    )
                }
        }
        .task { await load() }
        // Words are collected in the reader, on another tab, so coming back
        // here is exactly when this list is most likely to be behind.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let cards):
            if cards.isEmpty {
                emptyDeck
            } else {
                list(cards)
            }
        case .failed:
            // Distinct from the empty state on purpose: "we couldn't load this"
            // must never read as "your vocabulary is gone".
            ErrorStateView { Task { await load() } }
        }
    }

    private func list(_ cards: [LearningCard]) -> some View {
        let matches = cardsMatching(query, in: cards)
        let groups = groupedByKind(matches)

        return Group {
            if matches.isEmpty {
                // Deliberately not the empty-deck copy: "nothing matched" and
                // "you have collected nothing" are different facts, and telling
                // the reader the wrong one sends them to fix the wrong problem.
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    if isOffline {
                        Text("Showing what was saved on this device.")
                            .font(AppFont.caption)
                            .foregroundStyle(.grayFont)
                    }
                    // Headings always, even for a single section — unlike
                    // familiarity, one kind is a fact about this deck rather
                    // than about the feature being unfinished, so "Words"
                    // above a list of only words is worth saying.
                    ForEach(groups) { group in
                        Section(group.title) { rows(group.cards) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Vocabulary")
        .searchable(text: $query, prompt: "Search words and meanings")
        .refreshable { await load() }
    }

    private func rows(_ cards: [LearningCard]) -> some View {
        ForEach(cards) { card in
            NavigationLink(value: card) {
                CardRow(card: card)
            }
        }
    }

    /// Swaps one card in place after the detail screen corrected it, so the
    /// list neither reloads nor scrolls out from under the reader on their way
    /// back.
    private func replace(_ updated: LearningCard) {
        guard case .loaded(var cards) = state,
              let index = cards.firstIndex(where: { $0.id == updated.id })
        else { return }
        cards[index] = updated
        state = .loaded(cards)
    }

    /// Drops a deleted card from the displayed list in place. A failed delete
    /// never reaches here, because the card is still on the backend.
    private func remove(_ deleted: LearningCard) {
        guard case .loaded(var cards) = state else { return }
        cards.removeAll { $0.id == deleted.id }
        state = .loaded(cards)
    }

    private var emptyDeck: some View {
        ContentUnavailableView(
            "No words yet",
            systemImage: "text.book.closed",
            description: Text("Translate a line while reading, then add it as a word or a sentence.")
        )
    }

    /// Fetches the deck, falling back to what is on the device.
    ///
    /// The fallback is what makes this usable on a train — the same situation
    /// the already-learned marker was built for. It is only a `failed` state
    /// when there is nothing cached either, since showing the reader their own
    /// vocabulary is better than showing them an error about it.
    private func load() async {
        do {
            state = .loaded(try await repository.cards())
            isOffline = false
        } catch {
            let cached = repository.knownCards()
            if cached.isEmpty {
                state = .failed(error)
                isOffline = false
            } else {
                state = .loaded(cached)
                isOffline = true
            }
        }
    }
}

#Preview {
    StudyView()
}

extension LearningCard {
    /// Preview/sample-only factory. `LearningCard` exposes no memberwise
    /// initializer beyond `Decodable`, so this decodes a canned payload — the
    /// previews and the tests then share one fixture and cannot drift. Not
    /// `private` because `CardRow`'s `#Preview` uses it too.
    static func preview(
        id: Int = 1,
        sourceText: String = "大丈夫ですか",
        translation: String = "你還好嗎",
        comicTitle: String? = "marrymyhusband",
        chapterTitle: String? = "bai1",
        kind: String? = "word",
        ladderStage: Int = 0,
        lookupCount: Int = 0,
        createdAt: String = "2026-08-19T10:30:00Z"
    ) -> LearningCard {
        func quoted(_ value: String?) -> String {
            value.map { "\"\($0)\"" } ?? "null"
        }
        let json = """
        {
            "id": \(id),
            "sourceText": "\(sourceText)",
            "translation": "\(translation)",
            "targetLanguage": "zh-Hant",
            "comicId": "comic-1",
            "chapterId": "chapter-1",
            "pageNumber": 3,
            "comicTitle": \(quoted(comicTitle)),
            "chapterTitle": \(quoted(chapterTitle)),
            "kind": \(quoted(kind)),
            "ladderStage": \(ladderStage),
            "dueOn": "2026-08-19",
            "lookupCount": \(lookupCount),
            "lastLookedUpAt": null,
            "createdAt": "\(createdAt)"
        }
        """
        return try! APIConfig.iso8601Decoder.decode(LearningCard.self, from: Data(json.utf8))
    }
}
