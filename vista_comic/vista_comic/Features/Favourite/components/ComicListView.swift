//
//  comic_list.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/7.
//

import SwiftUI

struct ComicListView: View {
    let comic: Comic

    var body: some View{
        VStack{
            HStack(spacing: 17){
                Image(comic.coverImageName)
                    .resizable()
                    .frame(width: 76, height: 64, alignment: .center)
                VStack(alignment: .leading){
                    HStack{
                        Text(comic.title)
                            .font(AppFont.rowTitle)
                        Spacer()
                        Text("#\(comic.chapters.count)")
                            .font(AppFont.rowTitle)
                            .foregroundStyle(.grayFont)
                    }.padding(.bottom)

                    Text(lastReadText)
                        .font(AppFont.caption)
                        .foregroundStyle(.grayFont)
                }
            }

            HStack(spacing: 30){
                // Continue Reading behaviour is owned by the Library milestone (M2).
                Button(action: {}){
                    Text("continue")
                        .font(.system(size: 12, weight: .bold))
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.white)
                .foregroundStyle(.primaryRed)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.primaryRed, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

                NavigationLink(value: comic){
                    Text("chapter(\(comic.chapters.count))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.primaryRed)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: 147, alignment: .center)
    }

    private var lastReadText: String {
        guard let lastReadAt = comic.lastReadAt else {
            return "not started yet"
        }
        let when = lastReadAt.formatted(date: .abbreviated, time: .shortened)
        return "\(when) · last read"
    }
}

#Preview {
    NavigationStack {
        ComicListView(comic: SampleData.comics[0])
            .padding()
    }
}
