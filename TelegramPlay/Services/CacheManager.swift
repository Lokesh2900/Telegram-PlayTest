import Foundation
import TDLibKit

@MainActor
final class CacheManager: ObservableObject {
    @Published private(set) var usedBytes: Int64 = 0
    @Published private(set) var limitBytes: Int64 = CachePolicy.maxFileCacheBytes
    @Published private(set) var lastCleanupDate: Date?
    @Published private(set) var isCleaning = false
    @Published private(set) var lastError: String?

    var isPlaybackActive = false
    var playbackExcludeChatId: Int64?
    var playbackExcludeFileIds: Set<Int> = []

    private weak var client: TDLibClient?
    private var lastCleanupAttempt: Date?
    private var cleanupTask: Task<Void, Never>?

    func attach(client: TDLibClient) {
        self.client = client
    }

    func enableStorageOptimizer() async {
        guard let client else { return }
        do {
            _ = try await client.setOption(
                name: "use_storage_optimizer",
                value: .optionValueBoolean(OptionValueBoolean(value: true))
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshStatistics() async {
        guard let client else { return }
        do {
            let stats = try await client.getStorageStatisticsFast()
            usedBytes = stats.filesSize
            limitBytes = CachePolicy.maxFileCacheBytes
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func enforceLimitIfNeeded() async {
        if isPlaybackActive { return }
        guard usedBytes > CachePolicy.maxFileCacheBytes else { return }
        guard canRunAutomaticCleanup() else { return }
        await runOptimize(targetSize: CachePolicy.maxFileCacheBytes, immunityDelay: CachePolicy.immunityDelaySeconds)
    }

    func clearCacheNow() async {
        await runOptimize(targetSize: 0, immunityDelay: CachePolicy.manualClearImmunityDelaySeconds, ignoreInterval: true)
    }

    func scheduleMaintenanceAfterForeground() {
        enqueueMaintenance()
    }

    func scheduleMaintenanceAfterDownload() {
        enqueueMaintenance()
    }

    private func enqueueMaintenance() {
        cleanupTask?.cancel()
        cleanupTask = Task { @MainActor in
            await refreshStatistics()
            await enforceLimitIfNeeded()
        }
    }

    private func canRunAutomaticCleanup() -> Bool {
        guard let last = lastCleanupAttempt else { return true }
        return Date().timeIntervalSince(last) >= CachePolicy.minCleanupInterval
    }

    private func runOptimize(targetSize: Int64, immunityDelay: Int, ignoreInterval: Bool = false) async {
        guard let client else { return }
        if isCleaning { return }
        if !ignoreInterval && targetSize > 0 && !canRunAutomaticCleanup() { return }

        isCleaning = true
        lastCleanupAttempt = Date()
        defer { isCleaning = false }

        var exclude: [Int64] = []
        if let chatId = playbackExcludeChatId {
            exclude = [chatId]
        }

        do {
            _ = try await client.optimizeStorage(
                chatIds: nil,
                chatLimit: 0,
                count: Int(CachePolicy.optimizeCount),
                excludeChatIds: exclude.isEmpty ? nil : exclude,
                fileTypes: nil,
                immunityDelay: immunityDelay,
                returnDeletedFileStatistics: false,
                size: targetSize,
                ttl: Int(CachePolicy.optimizeTTL)
            )
            lastCleanupDate = Date()
            lastError = nil
            await refreshStatistics()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
