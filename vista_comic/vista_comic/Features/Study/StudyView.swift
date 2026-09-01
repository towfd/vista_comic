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
    /// Whether `.task` has already run. See `PracticeView` — `.onAppear` fires
    /// alongside it the first time and again on every return to this tab.
    @State private var hasAppeared = false
    /// Which headings the reader has opened, by `CardGroup.id`.
    ///
    /// **Everything starts closed, and nothing is remembered.** Opening the tab
    /// shows the two or three headings and their counts — the whole deck in one
    /// screen, nothing to scroll — and leaving it forgets what was open. That
    /// is deliberately the cheapest arrangement: no stored state, nothing to
    /// migrate, nothing to go stale, on a screen whose premise is that it is
    /// rarely opened. Rarely opening a workshop is success.
    @State private var openSections: Set<String> = []

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
        // here is exactly when this list is most likely to be behind — and as
        // of stage 4 they are also *practised* on another tab, which moves the
        // rung this list now shows. Switching tabs never fired `scenePhase`,
        // so a reader who practised and came straight here read the figures
        // from before the round and concluded nothing had moved.
        .onAppear {
            if hasAppeared { Task { await load() } }
            hasAppeared = true
            // A tab keeps its state while the reader is on another one, so
            // "the fold is not remembered" has to be done rather than assumed:
            // without this, returning to 單字庫 would show whatever was left
            // open last time.
            openSections.removeAll()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await load() }
                openSections.removeAll()
            }
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
                        Section {
                            if isExpanded(group) { rows(group.cards) }
                        } header: {
                            CardSectionHeader(
                                title: group.title,
                                // `groups` is built from the matches, so this
                                // is the total when nothing is being searched
                                // and the number found when something is. The
                                // heading never describes rows that are not
                                // under it.
                                count: group.cards.count,
                                isExpanded: isExpanded(group),
                                accent: group.accent
                            ) {
                                toggle(group)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .textCase(nil)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Vocabulary")
        .searchable(text: $query, prompt: "Search words and meanings")
        .refreshable { await load() }
    }

    /// A section is open if the reader opened it — **or if a search is
    /// running**, which overrides the fold entirely.
    ///
    /// The override is the one place "start closed" and "search is why people
    /// come here" would fight. Typing a word and being shown a closed heading
    /// answers the question with a number instead of the card, and this screen
    /// exists for the two ways a reader arrives: "I just mis-tapped" and "I
    /// remember one of these being wrong". Clearing the field returns to
    /// whatever was open before, because the query never touched `openSections`.
    private func isExpanded(_ group: CardGroup) -> Bool {
        isSearching || openSections.contains(group.id)
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func toggle(_ group: CardGroup) {
        if openSections.contains(group.id) {
            openSections.remove(group.id)
        } else {
            openSections.insert(group.id)
        }
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
            // Only degrade when nothing was reached. A 500 or a rejected token
            // means the server is there and something is wrong — serving the
            // snapshot for those would look perfectly normal while being
            // silently out of date, and nothing would ever say so.
            let cached = APIConfig.isOriginUnreachable(error) ? repository.knownCards() : []
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
        state: String = "new",
        learningStep: Int? = nil,
        ladderStage: Int = 0,
        previousStage: Int? = nil,
        introducedOn: String? = nil,
        dueAt: String = "2026-08-19T00:00:00Z",
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
            "state": "\(state)",
            "learningStep": \(learningStep.map(String.init) ?? "null"),
            "ladderStage": \(ladderStage),
            "previousStage": \(previousStage.map(String.init) ?? "null"),
            "introducedOn": \(quoted(introducedOn)),
            "dueAt": "\(dueAt)",
            "lookupCount": \(lookupCount),
            "lastLookedUpAt": null,
            "createdAt": "\(createdAt)"
        }
        """
        return try! APIConfig.iso8601Decoder.decode(LearningCard.self, from: Data(json.utf8))
    }
}
