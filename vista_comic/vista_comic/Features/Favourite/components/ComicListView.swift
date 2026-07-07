//
//  comic_list.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/7.
//

import SwiftUI

struct ComicListView: View {
    var body: some View{
        VStack{
            HStack(spacing: 17){
                Image("Landscape_4")
                    .resizable()
                    .frame(width: 76, height: 64, alignment: .center)
                VStack(alignment: .leading){
                    HStack{
                        Text("furiren")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                        Text("#200")
                            .font(.system(size: 14))
                            .foregroundStyle(.grayFont)
                    }.padding(.bottom)
                    
                    Text("30 Jan, 12:30 . last read")
                        .font(.system(size: 12))
                        .foregroundStyle(.grayFont)
                }
            }
            
            HStack(spacing: 30){
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
                
                Button(action: {}){
                    Text("chapter(500)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.primaryRed)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }.frame(maxWidth: .infinity, maxHeight: 147, alignment: .center)
    }
}
