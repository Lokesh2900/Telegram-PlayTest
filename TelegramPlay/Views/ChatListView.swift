import SwiftUI

struct ChatListView: View {
    @EnvironmentObject private var telegram: TelegramClientService

    var body: some View {
        List(telegram.chats) { chat in
            NavigationLink(chat.title) {
                ChatMediaView(chat: chat)
            }
        }
        .overlay {
            if telegram.isLoadingChats && telegram.chats.isEmpty {
                ProgressView("Loading chats…")
            }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    CacheSettingsView(cache: telegram.cacheManager)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await telegram.reloadChats() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .refreshable {
            await telegram.reloadChats()
        }
    }
}

private struct PlayerRoute: Hashable {
    let url: URL
    let title: String
    let virtualSessionId: UUID?
    let virtualFileIds: [Int]
}

struct ChatMediaView: View {
    @EnvironmentObject private var telegram: TelegramClientService
    let chat: ChatSummary
    @State private var playerRoute: PlayerRoute?
    @State private var playbackError: String?

    var body: some View {
        List(telegram.mediaItems) { item in
            Button {
                Task { await play(item) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.listTitle)
                        .lineLimit(2)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if telegram.isLoadingMessages && telegram.mediaItems.isEmpty {
                ProgressView("Loading videos…")
            }
        }
        .navigationTitle(chat.title)
        .navigationDestination(item: $playerRoute) { route in
            VideoPlayerScreen(
                title: route.title,
                fileURL: route.url,
                chatId: chat.id,
                virtualSessionId: route.virtualSessionId,
                virtualFileIds: route.virtualFileIds
            )
        }
        .alert("Playback", isPresented: Binding(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackError ?? "")
        }
        .task {
            await telegram.loadPlayableMedia(chatId: chat.id)
        }
    }

    private func play(_ item: PlayableItem) async {
        playbackError = nil
        do {
            switch item {
            case .single(let media):
                let url = try await telegram.localFileURL(for: media)
                playerRoute = PlayerRoute(
                    url: url,
                    title: media.title,
                    virtualSessionId: nil,
                    virtualFileIds: []
                )
            case .virtualRaw(let parts, _, _), .virtualZip(let parts, _, _):
                let virtual = try await telegram.virtualPlayback(for: item)
                playerRoute = PlayerRoute(
                    url: virtual.url,
                    title: virtual.title,
                    virtualSessionId: virtual.sessionId,
                    virtualFileIds: parts.map(\.fileId)
                )
            }
        } catch {
            playbackError = error.localizedDescription
        }
    }
}

private extension PlayableItem {
    var subtitle: String? {
        switch self {
        case .single(let media):
            guard let seconds = media.durationSeconds else { return nil }
            let m = seconds / 60
            let s = seconds % 60
            return String(format: "%d:%02d", m, s)
        case .virtualRaw(let parts, _, _), .virtualZip(let parts, _, _):
            return "Split · \(parts.count) parts"
        }
    }
}
