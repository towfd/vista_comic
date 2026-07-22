//
//  ErrorStateView.swift
//  vista_comic
//
//  A reusable full-screen failure state with a retry action, shown whenever a
//  repository fetch fails (library, chapter list, or reader pages). Text is
//  localization-ready via the String Catalog.
//

import SwiftUI

struct ErrorStateView: View {
    /// Re-runs the failed fetch.
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't connect", systemImage: "wifi.exclamationmark")
        } description: {
            Text("Check that the server is running and try again.")
        } actions: {
            Button(action: retry) {
                Text("Retry")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.primaryRed)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ErrorStateView(retry: {})
}
