//
//  comic_list.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/7.
//

import SwiftUI

struct ChapterListView: View {
    var body: some View{
        VStack{
            Button(action: {}){
                HStack(spacing: 17){
                    Image("Landscape_4")
                        .resizable()
                        .frame(width: 60, height: 60, alignment: .center)
                    
                    VStack(alignment: .leading, spacing: 10){
                        Text("bai1")
                            .font(.system(size: 14, weight: .bold))
                        Text("unread")
                            .font(.system(size: 12))
                    }
                    
                    Spacer()
                    
                    VStack(){
                        Text("#1")
                            .font(.system(size: 14))
                    }.padding(.trailing, 10)
                }
            }
            .foregroundStyle(.grayFont)
        }.frame(maxWidth: .infinity, maxHeight: 73, alignment: .center)
    }
}
