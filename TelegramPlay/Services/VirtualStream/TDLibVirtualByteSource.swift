import Foundation
import TDLibKit

enum VirtualStreamError: LocalizedError {
    case manifestInvalid
    case zipUnreadable
    case zipCompressed
    case zipDescriptor
    case readFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .manifestInvalid:
            return "Invalid split file group."
        case .zipUnreadable:
            return "Could not read this split archive."
        case .zipCompressed:
            return "This archive is compressed. Only stored (uncompressed) ZIP releases can be streamed."
        case .zipDescriptor:
            return "This archive uses data descriptors and cannot be seek-streamed."
        case .readFailed:
            return "Failed to read file data from Telegram."
        case .cancelled:
            return "Playback was cancelled."
        }
    }
}

actor TDLibVirtualByteSource {
    static let chunkSize = 1024 * 1024

    private let client: TDLibClient
    private var fileUpdateContinuations: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var sessionToken: UUID?

    init(client: TDLibClient) {
        self.client = client
    }

    func setActiveSession(_ token: UUID?) {
        sessionToken = token
    }

    func notifyFileUpdate(fileId: Int) {
        let waiters = fileUpdateContinuations.removeValue(forKey: fileId) ?? []
        for w in waiters { w.resume() }
    }

    func readVirtual(manifest: VirtualFileManifest, offset: Int64, length: Int) async throws -> Data {
        guard length > 0, offset >= 0, offset < manifest.totalSize else { return Data() }
        let end = min(offset + Int64(length) - 1, manifest.totalSize - 1)
        var buffer = Data()
        buffer.reserveCapacity(length)
        for try await chunk in streamVirtualBytes(manifest: manifest, globalStart: offset, globalEnd: end) {
            buffer.append(chunk)
        }
        return buffer
    }

    func streamVirtualBytes(
        manifest: VirtualFileManifest,
        globalStart: Int64,
        globalEnd: Int64
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let slices = manifest.slices(globalStart: globalStart, globalEnd: globalEnd)
                    for slice in slices {
                        try Task.checkCancellation()
                        let byteCount = slice.localEnd - slice.localStart + 1
                        var remaining = byteCount
                        var pos = slice.localStart
                        while remaining > 0 {
                            try Task.checkCancellation()
                            let step = min(Int64(Self.chunkSize), remaining)
                            let data = try await readPart(
                                fileId: slice.part.fileId,
                                offset: pos,
                                count: step
                            )
                            if data.isEmpty { throw VirtualStreamError.readFailed }
                            continuation.yield(data)
                            remaining -= Int64(data.count)
                            pos += Int64(data.count)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func readPart(fileId: Int, offset: Int64, count: Int64) async throws -> Data {
        try await ensureDownloaded(fileId: fileId, offset: offset, count: count)
        if let disk = try await readFromDisk(fileId: fileId, offset: offset, count: count) {
            return disk
        }
        let part = try await client.readFilePart(count: count, fileId: fileId, offset: offset)
        return part.data
    }

    private func ensureDownloaded(fileId: Int, offset: Int64, count: Int64) async throws {
        let needed = offset + count
        var attempts = 0
        while attempts < 600 {
            attempts += 1
            try Task.checkCancellation()
            let prefix = try await client.getFileDownloadedPrefixSize(fileId: fileId, offset: offset)
            if prefix >= count { return }

            _ = try await client.downloadFile(
                fileId: fileId,
                limit: count,
                offset: offset,
                priority: 32,
                synchronous: false
            )

            try await waitForFileUpdate(fileId: fileId)

            let file = try await client.getFile(fileId: fileId)
            if file.local.isDownloadingCompleted {
                return
            }
            if file.local.downloadedSize >= needed { return }
            let nextPrefix = try await client.getFileDownloadedPrefixSize(fileId: fileId, offset: offset)
            if nextPrefix >= count { return }
            if nextPrefix == prefix {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        throw VirtualStreamError.readFailed
    }

    private func waitForFileUpdate(fileId: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            fileUpdateContinuations[fileId, default: []].append(continuation)
        }
    }

    private func readFromDisk(fileId: Int, offset: Int64, count: Int64) async throws -> Data? {
        let file = try await client.getFile(fileId: fileId)
        let path = file.local.path
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        guard let data = try handle.read(upToCount: Int(count)) else { return nil }
        return data
    }
}
