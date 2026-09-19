import Foundation
import TDLibKit
import UIKit

enum AuthPhase: Equatable {
    case starting
    case phone
    case code
    case password(hint: String)
    case ready
    case closed
}

@MainActor
final class TelegramClientService: ObservableObject {
    let cacheManager = CacheManager()

    @Published var authPhase: AuthPhase = .starting
    @Published var chats: [ChatSummary] = []
    @Published var mediaItems: [PlayableMedia] = []
    @Published var statusMessage: String?
    @Published var isLoadingChats = false
    @Published var isLoadingMessages = false
    @Published var isPreparingPlayback = false

    private let manager = TDLibClientManager()
    private var client: TDLibClient!
    private var tdlibPaths: (database: String, files: String) = ("", "")
    private var pendingFileContinuations: [Int: CheckedContinuation<URL, Error>] = [:]
    private var selectedChatId: Int64?

    init() {
        client = manager.createClient { [weak self] data, client in
            Task { @MainActor in
                self?.handleUpdate(data: data, client: client)
            }
        }
        prepareDirectories()
        cacheManager.attach(client: client)
        Task { await bootstrapTdlib() }
    }

    func handleAppForeground() {
        cacheManager.scheduleMaintenanceAfterForeground()
    }

    func beginActivePlayback(chatId: Int64) {
        cacheManager.isPlaybackActive = true
        cacheManager.playbackExcludeChatId = chatId
    }

    func endActivePlayback() {
        cacheManager.isPlaybackActive = false
        cacheManager.playbackExcludeChatId = nil
        cacheManager.scheduleMaintenanceAfterDownload()
    }

    private func prepareDirectories() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TelegramPlay", isDirectory: true)
        let database = base.appendingPathComponent("database", isDirectory: true)
        let files = base.appendingPathComponent("files", isDirectory: true)
        try? FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        tdlibPaths = (database.path, files.path)
    }

    private func bootstrapTdlib() async {
        do {
            _ = try await client.setLogVerbosityLevel(newVerbosityLevel: 1)
            let state = try await client.getAuthorizationState()
            await applyAuthorizationState(state)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func handleUpdate(data: Data, client: TDLibClient) {
        do {
            let update = try client.decoder.decode(Update.self, from: data)
            switch update {
            case .updateAuthorizationState(let payload):
                Task { await applyAuthorizationState(payload.authorizationState) }
            case .updateFile(let payload):
                handleFileUpdate(payload.file)
            default:
                break
            }
        } catch {
            statusMessage = "Update decode error: \(error.localizedDescription)"
        }
    }

    private func applyAuthorizationState(_ state: AuthorizationState) async {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            await configureTdlibParameters()
        case .authorizationStateWaitEncryptionKey:
            do {
                _ = try await client.checkDatabaseEncryptionKey(encryptionKey: Data())
            } catch {
                statusMessage = error.localizedDescription
            }
        case .authorizationStateWaitPhoneNumber:
            authPhase = .phone
        case .authorizationStateWaitCode:
            authPhase = .code
        case .authorizationStateWaitPassword(let info):
            authPhase = .password(hint: info.passwordHint)
        case .authorizationStateReady:
            authPhase = .ready
            await cacheManager.enableStorageOptimizer()
            await cacheManager.refreshStatistics()
            await cacheManager.enforceLimitIfNeeded()
            await reloadChats()
        case .authorizationStateClosing, .authorizationStateClosed:
            authPhase = .closed
        default:
            break
        }
    }

    private func configureTdlibParameters() async {
        do {
            _ = try await client.setTdlibParameters(
                apiHash: TelegramConfig.apiHash,
                apiId: TelegramConfig.apiId,
                applicationVersion: "1.0",
                databaseDirectory: tdlibPaths.database,
                databaseEncryptionKey: nil,
                deviceModel: "iOS",
                filesDirectory: tdlibPaths.files,
                systemLanguageCode: Locale.current.language.languageCode?.identifier ?? "en",
                systemVersion: UIDevice.current.systemVersion,
                useChatInfoDatabase: true,
                useFileDatabase: true,
                useMessageDatabase: true,
                useSecretChats: false,
                useTestDc: false
            )
            await cacheManager.enableStorageOptimizer()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func submitPhoneNumber(_ phone: String) async {
        statusMessage = nil
        let settings = PhoneNumberAuthenticationSettings(
            allowFlashCall: false,
            allowMissedCall: false,
            allowSmsRetrieverApi: false,
            authenticationTokens: [],
            firebaseAuthenticationSettings: nil,
            hasUnknownPhoneNumber: false,
            isCurrentPhoneNumber: false
        )
        do {
            _ = try await client.setAuthenticationPhoneNumber(phoneNumber: phone, settings: settings)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func submitCode(_ code: String) async {
        statusMessage = nil
        do {
            _ = try await client.checkAuthenticationCode(code: code)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func submitPassword(_ password: String) async {
        statusMessage = nil
        do {
            _ = try await client.checkAuthenticationPassword(password: password)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func reloadChats() async {
        isLoadingChats = true
        defer { isLoadingChats = false }
        do {
            _ = try await client.loadChats(chatList: .chatListMain, limit: 100)
            let list = try await client.getChats(chatList: .chatListMain, limit: 100)
            var summaries: [ChatSummary] = []
            for chatId in list.chatIds {
                let chat = try await client.getChat(chatId: chatId)
                summaries.append(ChatSummary(id: chat.id, title: chat.title))
            }
            chats = summaries
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func loadPlayableMedia(chatId: Int64) async {
        selectedChatId = chatId
        isLoadingMessages = true
        mediaItems = []
        defer { isLoadingMessages = false }
        do {
            let history = try await client.getChatHistory(
                chatId: chatId,
                fromMessageId: 0,
                limit: 80,
                offset: 0,
                onlyLocal: false
            )
            mediaItems = history.messages.compactMap(Self.playableMedia(from:))
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func localFileURL(for media: PlayableMedia) async throws -> URL {
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }

        let url = try await withCheckedThrowingContinuation { continuation in
            pendingFileContinuations[media.fileId] = continuation
            Task {
                do {
                    _ = try await client.downloadFile(
                        fileId: media.fileId,
                        limit: 0,
                        offset: 0,
                        priority: 32,
                        synchronous: false
                    )
                } catch {
                    pendingFileContinuations.removeValue(forKey: media.fileId)?.resume(throwing: error)
                }
            }
        }
        cacheManager.scheduleMaintenanceAfterDownload()
        return url
    }

    private func handleFileUpdate(_ file: File) {
        guard let continuation = pendingFileContinuations[file.id] else { return }
        let path = file.local.path
        guard !path.isEmpty else { return }

        if file.local.isDownloadingCompleted {
            pendingFileContinuations.removeValue(forKey: file.id)
            continuation.resume(returning: URL(fileURLWithPath: path))
            return
        }

        // Start playback once a chunk is available (Telegram progressive download).
        if file.local.downloadedSize > 512 * 1024, FileManager.default.fileExists(atPath: path) {
            pendingFileContinuations.removeValue(forKey: file.id)
            continuation.resume(returning: URL(fileURLWithPath: path))
        }
    }

    private static func playableMedia(from message: Message) -> PlayableMedia? {
        switch message.content {
        case .messageVideo(let video):
            let file = video.video.video
            let name = video.video.fileName.isEmpty ? "Video" : video.video.fileName
            let caption = video.caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = caption.isEmpty ? name : caption
            return PlayableMedia(
                id: message.id,
                fileId: file.id,
                title: title,
                durationSeconds: video.video.duration
            )
        case .messageAnimation(let animation):
            return PlayableMedia(
                id: message.id,
                fileId: animation.animation.id,
                title: animation.caption.text.isEmpty ? "GIF / animation" : animation.caption.text,
                durationSeconds: animation.animation.duration
            )
        case .messageDocument(let document):
            let mime = document.document.mimeType.lowercased()
            guard mime.hasPrefix("video/") else { return nil }
            let name = document.document.fileName.isEmpty ? "Video file" : document.document.fileName
            return PlayableMedia(
                id: message.id,
                fileId: document.document.id,
                title: name,
                durationSeconds: nil
            )
        default:
            return nil
        }
    }
}
