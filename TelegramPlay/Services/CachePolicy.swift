import Foundation

enum CachePolicy {
    static let maxFileCacheBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let immunityDelaySeconds = 600
    static let manualClearImmunityDelaySeconds = 0
    static let minCleanupInterval: TimeInterval = 5 * 60
    static let optimizeTTL = Int32.max
    static let optimizeCount = Int32.max
}
