//
//  ErrorStateView.swift
//  vista_comic
//
//  A reusable full-screen failure state with a retry action, shown whenever a
//  repository fetch fails (library, chapter list, or reader pages). Text is
//  localization-ready via the String Catalog.
//
//  `offline-download` ticket 02 gives it a second thing to say. "The network is
//  unreachable" and "you are offline and never downloaded this chapter" are
//  different facts about the reader's situation, and only one of them is
//  answered by trying again — telling them apart is the difference between a
//  reader who knows what to do and one who wonders whether the app is broken.
//

import SwiftUI

struct ErrorStateView: View {
    enum Kind {
        /// The default, and every call site that predates downloads: something
        /// could not be fetched, and trying again is the answer.
        case connection
        /// Offline, and this chapter is not on the device — or is only partly
        /// on it, which reads the same from here.
        case notAvailableOffline
    }

    var kind: Kind = .connection
    /// Re-runs the failed fetch.
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(explanation)
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

    private var title: String {
        switch kind {
        case .connection: return String(localized: "Couldn't connect")
        case .notAvailableOffline: return String(localized: "Not downloaded")
        }
    }

    private var symbol: String {
        switch kind {
        case .connection: return "wifi.exclamationmark"
        case .notAvailableOffline: return "arrow.down.circle"
        }
    }

    private var explanation: String {
        switch kind {
        case .connection:
            return String(localized: "Check that the server is running and try again.")
        case .notAvailableOffline:
            return String(localized: "This chapter isn't on your device. Reconnect to read it, or download it while you're online.")
        }
    }
}

#Preview("Couldn't connect") {
    ErrorStateView(retry: {})
}

#Preview("Not downloaded") {
    ErrorStateView(kind: .notAvailableOffline, retry: {})
}
