//
//  ChapterPageView.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/7.
//
import SwiftUI

struct ChapterPageView: View{
    var body: some View{
        VStack{
            Image("Landscape_4")
                .resizable()
                .frame(width: 187, height: 187)
            Text("Furiren")
                .font(.system(size: 36, weight: .bold))
            
            ScrollView{
                ForEach(1..<10){ _ in
                    ChapterListView()
                }
            }
        }
    }
}
