//
//  ComicView.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/12.
//
import SwiftUI

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
                    // Renders the current chapter's pages as a continuous vertical
                    // read. Loading / failure states and previous / next chapter
                    // navigation are still owned by the Reader milestone (M3).
                    ForEach(Array(currentChapter.pageImageNames.enumerated()), id: \.offset){ _, imageName in
                        Image(imageName)
                            .resizable()
                            .frame(maxWidth: .infinity)
                            .aspectRatio(contentMode: .fit)
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

    private var controlsOverlay: some View {
        VStack(spacing: 0){
            HStack(spacing: 17){
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("返回")
                Spacer()
                Button { showChapterList = true } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("章節列表")
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Spacer()

            HStack{
                Text(currentChapter.title)
                    .font(AppFont.rowTitle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
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
}

#Preview {
    NavigationStack {
        ComicView(comic: SampleData.comics[0], chapter: SampleData.comics[0].chapters[1])
    }
}
