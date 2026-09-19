import SwiftUI

struct VideoPlayerScreen: View {
    @EnvironmentObject private var telegram: TelegramClientService

    let title: String
    let fileURL: URL
    let chatId: Int64
    var virtualSessionId: UUID?
    var virtualFileIds: [Int] = []

    @ObservedObject private var coordinator = MPVMetalPlayerView.Coordinator()
    @State private var buffering = false

    var body: some View {
        MPVMetalPlayerView(coordinator: coordinator)
            .play(fileURL)
            .onPropertyChange { _, propertyName, propertyData in
                if propertyName == MPVProperty.pausedForCache {
                    buffering = (propertyData as? Bool) ?? false
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if buffering {
                    ProgressView()
                }
            }
            .onAppear {
                telegram.beginActivePlayback(
                    chatId: chatId,
                    virtualFileIds: virtualFileIds,
                    virtualSessionId: virtualSessionId
                )
            }
            .onDisappear {
                telegram.endActivePlayback()
            }
    }
}
