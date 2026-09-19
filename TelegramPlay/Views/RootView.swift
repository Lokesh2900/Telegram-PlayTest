import SwiftUI

struct RootView: View {
    @EnvironmentObject private var telegram: TelegramClientService

    var body: some View {
        Group {
            switch telegram.authPhase {
            case .starting:
                ProgressView("Connecting to Telegram…")
            case .phone, .code, .password:
                AuthFlowView()
            case .ready:
                NavigationStack {
                    ChatListView()
                }
            case .closed:
                ContentUnavailableView("Session closed", systemImage: "xmark.circle")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
