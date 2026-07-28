//
//  CoverImage.swift
//  vista_comic
//
//  Shared cover renderer for the library card and the chapter screen (M5 Slice 3).
//  Loads a cover URL with `AuthorizedAsyncImage` (see that file — a stand-in
//  for `AsyncImage` that attaches Cloudflare Access headers), showing a
//  neutral placeholder while loading and on failure so covers degrade
//  gracefully when the backend is down.
//

import SwiftUI

struct CoverImage: View {
    let url: URL?

    var body: some View {
        AuthorizedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                // Let the caller's `.frame(...)` impose the size: `Color.clear`
                // adopts that frame and the aspect-filled image is clipped to it,
                // so the cover can never overflow onto adjacent controls.
                Color.clear
                    .overlay {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
            case .empty:
                placeholder { ProgressView() }
            case .failure:
                placeholder {
                    Image(systemName: "photo")
                        .foregroundStyle(.grayFont)
                }
            @unknown default:
                placeholder { EmptyView() }
            }
        }
    }

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Rectangle()
                .fill(Color(.secondarySystemBackground))
            content()
        }
    }
}

#Preview {
    CoverImage(url: nil)
        .frame(width: 187, height: 187)
}
