import Foundation

struct VirtualPart: Hashable, Sendable {
    let messageId: Int64
    let fileId: Int
    let size: Int64
    let cumStart: Int64
}

struct VirtualFileManifest: Hashable, Sendable {
    let parts: [VirtualPart]
    let totalSize: Int64

    static func from(playableParts: [PlayableMedia]) -> VirtualFileManifest? {
        guard !playableParts.isEmpty else { return nil }
        var cum: Int64 = 0
        var built: [VirtualPart] = []
        for media in playableParts {
            let size = media.remoteSize
            guard size > 0 else { return nil }
            built.append(VirtualPart(messageId: media.id, fileId: media.fileId, size: size, cumStart: cum))
            cum += size
        }
        return VirtualFileManifest(parts: built, totalSize: cum)
    }

    struct OverlapSlice: Sendable {
        let part: VirtualPart
        let localStart: Int64
        let localEnd: Int64
    }

    func slices(globalStart: Int64, globalEnd: Int64) -> [OverlapSlice] {
        guard totalSize > 0, globalStart >= 0 else { return [] }
        let end = min(globalEnd, totalSize - 1)
        let start = min(globalStart, end)
        guard start <= end else { return [] }
        var result: [OverlapSlice] = []
        for part in parts {
            let partEnd = part.cumStart + part.size - 1
            if partEnd < start { continue }
            if part.cumStart > end { break }
            let localStart = max(start, part.cumStart) - part.cumStart
            let localEnd = min(end, partEnd) - part.cumStart
            result.append(OverlapSlice(part: part, localStart: localStart, localEnd: localEnd))
        }
        return result
    }

    var allFileIds: [Int] {
        parts.map(\.fileId)
    }
}
