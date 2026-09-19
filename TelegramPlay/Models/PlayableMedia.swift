import Foundation

struct PlayableMedia: Identifiable, Hashable, Sendable {
    let id: Int64
    let fileId: Int
    let fileName: String
    let remoteSize: Int64
    let title: String
    let durationSeconds: Int?
}

enum PlayableItem: Identifiable, Hashable {
    case single(PlayableMedia)
    case virtualRaw(parts: [PlayableMedia], displayTitle: String, totalSize: Int64)
    case virtualZip(parts: [PlayableMedia], displayTitle: String, zipSize: Int64)

    var id: String {
        switch self {
        case .single(let media):
            return "s-\(media.id)"
        case .virtualRaw(let parts, _, _):
            return "vr-\(parts.map(\.id).sorted().map(String.init).joined(separator: "-"))"
        case .virtualZip(let parts, _, _):
            return "vz-\(parts.map(\.id).sorted().map(String.init).joined(separator: "-"))"
        }
    }

    var listTitle: String {
        switch self {
        case .single(let media):
            return media.title
        case .virtualRaw(_, let title, _), .virtualZip(_, let title, _):
            return title
        }
    }
}

struct ChatSummary: Identifiable, Hashable {
    let id: Int64
    let title: String
}

enum PlayableMediaGrouper {
    static func group(_ raw: [PlayableMedia]) -> [PlayableItem] {
        var splitBuckets: [String: [(part: Int, media: PlayableMedia, isZip: Bool)]] = [:]
        var singles: [PlayableMedia] = []

        for media in raw {
            guard let (key, part) = SplitFilenameParser.parseSplitInfo(fileName: media.fileName) else {
                singles.append(media)
                continue
            }
            let isZip = SplitFilenameParser.splitArchiveExtension(fileName: media.fileName) != nil
            splitBuckets[key, default: []].append((part, media, isZip))
        }

        var virtuals: [PlayableItem] = []
        for (_, entries) in splitBuckets {
            guard let grouped = makeVirtualItem(from: entries) else { continue }
            virtuals.append(grouped)
        }

        virtuals.sort { $0.listTitle.localizedCaseInsensitiveCompare($1.listTitle) == .orderedAscending }
        let singleItems = singles.map { PlayableItem.single($0) }
        return virtuals + singleItems
    }

    private static func makeVirtualItem(from entries: [(part: Int, media: PlayableMedia, isZip: Bool)]) -> PlayableItem? {
        let sorted = entries.sorted { $0.part < $1.part }
        guard !sorted.isEmpty else { return nil }

        let isZipGroup = sorted.contains(where: { $0.isZip })
        let parts = sorted.map(\.media)
        let numbers = sorted.map(\.part)
        guard isContiguousPartNumbers(numbers) else { return nil }

        let baseName = SplitFilenameParser.stripPartSuffix(fileName: parts[0].fileName)
        let displayTitle = parts[0].title == parts[0].fileName
            ? baseName
            : parts[0].title
        let totalSize = parts.reduce(Int64(0)) { $0 + $1.remoteSize }
        guard totalSize > 0 else { return nil }

        if isZipGroup {
            return .virtualZip(parts: parts, displayTitle: displayTitle, zipSize: totalSize)
        }
        return .virtualRaw(parts: parts, displayTitle: displayTitle, totalSize: totalSize)
    }

    /// Accepts 1…N or 0…(N-1) part numbering.
    private static func isContiguousPartNumbers(_ numbers: [Int]) -> Bool {
        guard !numbers.isEmpty else { return false }
        let sorted = numbers.sorted()
        if sorted[0] == 1 {
            return sorted == Array(1...sorted.count)
        }
        if sorted[0] == 0 {
            return sorted == Array(0..<sorted.count)
        }
        return false
    }
}
