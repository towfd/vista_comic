//
//  Favourite.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/3.
//

import SwiftUI

struct FavouriteView: View {
    var body: some View {
        ScrollView{
            VStack {
                Text("Favourite")
                    .font(.system(size: 36, weight: .bold))
                
                ForEach(0..<10){_ in
                    ComicListView()
                }
                
            }
            .padding()
        }
    }
}
