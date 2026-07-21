//
//  ComicView.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/12.
//
import SwiftUI
import UIKit

struct ComicView: View{
    let comic: Comic
    @State private var currentChapter: Chapter
    @State private var showControls = true
    @State private var showChapterList = false
    @Environment(\.dismiss) private var dismiss

    init(comic: Comic, chapter: Chapter) {
        self.comic = comic
        _currentChapter = State(initialValue: chapter)
    }

    var body: some View{
        ZStack{
            ScrollView{
                VStack(spacing: 0){
                    // Renders the current chapter's pages as a continuous vertical read.
                    ForEach(Array(currentChapter.pageImageNames.enumerated()), id: \.offset){ _, imageName in
                        pageView(for: imageName)
                    }
                }
            }
            // Rebuild the scroll view when the chapter changes so a newly opened
            // chapter always starts at its first page instead of inheriting the
            // previous chapter's scroll offset.
            .id(currentChapter.id)
            .onTapGesture {
                withAnimation { showControls.toggle() }
            }

            if showControls {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        // Use custom, immersive controls instead of the system navigation bar,
        // so there is no duplicate back button.
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showChapterList) {
            chapterListSheet
        }
    }

    // MARK: - Pages

    /// A single reading page. Local assets load synchronously, so only a failure
    /// placeholder is needed here; a loading state belongs with real asynchronous
    /// image loading in a later milestone.
    @ViewBuilder
    private func pageView(for imageName: String) -> some View {
        if UIImage(named: imageName) != nil {
            Image(imageName)
                .resizable()
                .frame(maxWidth: .infinity)
                .aspectRatio(contentMode: .fit)
        } else {
            failurePlaceholder
        }
    }

    private var failurePlaceholder: some View {
        VStack(spacing: 8){
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
            Text("Couldn't load this page")
                .font(AppFont.caption)
        }
        .foregroundStyle(.grayFont)
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding()
    }

    // MARK: - Controls

    private var controlsOverlay: some View {
        VStack(spacing: 0){
            HStack(spacing: 17){
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
                Spacer()
                Button { showChapterList = true } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Chapter list")
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)

            Spacer()

            HStack{
                Button { goTo(previousChapter) } label: {
                    Image(systemName: "chevron.backward")
                }
                .disabled(previousChapter == nil)
                .accessibilityLabel("Previous chapter")

                Spacer()

                Text(currentChapter.title)
                    .font(AppFont.rowTitle)

                Spacer()

                Button { goTo(nextChapter) } label: {
                    Image(systemName: "chevron.forward")
                }
                .disabled(nextChapter == nil)
                .accessibilityLabel("Next chapter")
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
        }
    }

    private var chapterListSheet: some View {
        NavigationStack {
            List(comic.chapters) { chapter in
                Button {
                    currentChapter = chapter
                    showChapterList = false
                } label: {
                    HStack{
                        Text(chapter.title)
                        Spacer()
                        if chapter.id == currentChapter.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.primaryRed)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle(comic.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Chapter navigation

    private var currentIndex: Int {
        comic.chapters.firstIndex { $0.id == currentChapter.id } ?? 0
    }

    private var previousChapter: Chapter? {
        currentIndex > 0 ? comic.chapters[currentIndex - 1] : nil
    }

    private var nextChapter: Chapter? {
        currentIndex < comic.chapters.count - 1 ? comic.chapters[currentIndex + 1] : nil
    }

    private func goTo(_ chapter: Chapter?) {
        guard let chapter else { return }
        currentChapter = chapter
    }
}

#Preview("Reader") {
    NavigationStack {
        ComicView(comic: SampleData.comics[0], chapter: SampleData.comics[0].chapters[1])
    }
}

#Preview("Missing page") {
    let comic = Comic(
        title: "Broken",
        coverImageName: "Landscape_4",
        chapters: [Chapter(number: 1, title: "Chapter 1", pageImageNames: ["no_such_asset"])]
    )
    return NavigationStack {
        ComicView(comic: comic, chapter: comic.chapters[0])
    }
}
