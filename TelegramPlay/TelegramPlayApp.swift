import SwiftUI

@main
struct TelegramPlayApp: App {
    @StateObject private var telegram = TelegramClientService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(telegram)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                telegram.handleAppForeground()
            }
        }
    }
}
