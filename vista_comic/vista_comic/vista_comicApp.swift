//
//  vista_comicApp.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/3.
//

import SwiftUI

@main
struct vista_comicApp: App {
    var body: some Scene {
        WindowGroup {
            // Inject the live backend repository. Previews and the canvas fall
            // back to `PreviewComicRepository` via the environment default.
            HomeView()
                .environment(\.comicRepository, APIComicRepository())
        }
    }
}
