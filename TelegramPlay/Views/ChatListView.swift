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

struct ChatMediaView: View {
    @EnvironmentObject private var telegram: TelegramClientService
    let chat: ChatSummary
    @State private var playbackURL: URL?
    @State private var playbackTitle: String?
    @State private var playbackError: String?

    var body: some View {
        List(telegram.mediaItems) { item in
            Button {
                Task { await play(item) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .lineLimit(2)
                    if let seconds = item.durationSeconds {
                        Text(formatDuration(seconds))
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
        .navigationDestination(item: $playbackURL) { url in
            VideoPlayerScreen(
                title: playbackTitle ?? "Video",
                fileURL: url,
                chatId: chat.id
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

    private func play(_ item: PlayableMedia) async {
        playbackError = nil
        do {
            let url = try await telegram.localFileURL(for: item)
            playbackTitle = item.title
            playbackURL = url
        } catch {
            playbackError = error.localizedDescription
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
