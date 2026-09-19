import Foundation

enum SplitFilenameParser {
    private static let videoExtensions = "mkv|mp4|avi|ts|m4v|mov|wmv|webm|flv|m2ts|mpg|mpeg"
    private static let archiveExtensions = "zip"

    private static let trailingNumericPattern: NSRegularExpression = {
        let pattern = #"(?i)\.(#(videoExtensions)|#(archiveExtensions))\.(\d{2,3})(?=$|\D)"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let normalizePattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"[\.\-_ ]+"#)
    }()

    static func splitArchiveExtension(fileName: String) -> String? {
        guard let match = findSplitMatch(fileName.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let ext = match.extensionLowercased
        return ext == "zip" ? ext : nil
    }

    static func parseSplitInfo(fileName: String) -> (groupKey: String, partNumber: Int)? {
        let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let match = findSplitMatch(name) else { return nil }

        let ns = name as NSString
        let remainder: String
        if let ext = match.extensionLowercased {
            remainder = ns.substring(to: match.range.lowerBound) + "." + ext
        } else {
            remainder = ns.substring(to: match.range.lowerBound) + ns.substring(from: match.range.upperBound)
        }
        return (normalize(remainder), match.partNumber)
    }

    static func stripPartSuffix(fileName: String) -> String {
        let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = findSplitMatch(name) else { return fileName }
        let ns = name as NSString
        if let ext = match.extensionLowercased {
            return ns.substring(to: match.range.lowerBound) + "." + ext
        }
        return ns.substring(to: match.range.lowerBound) + ns.substring(from: match.range.upperBound)
    }

    private struct SplitMatch {
        let range: NSRange
        let partNumber: Int
        let extensionLowercased: String?
    }

    private static func findSplitMatch(_ name: String) -> SplitMatch? {
        let ns = name as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = trailingNumericPattern.firstMatch(in: name, range: range) else { return nil }
        let partRange = m.range(at: 3)
        let partStr = ns.substring(with: partRange)
        guard let partNumber = Int(partStr) else { return nil }
        let extRange = m.range(at: 1)
        let ext = extRange.location != NSNotFound ? ns.substring(with: extRange).lowercased() : nil
        return SplitMatch(range: m.range, partNumber: partNumber, extensionLowercased: ext)
    }

    private static func normalize(_ base: String) -> String {
        let ns = base as NSString
        let range = NSRange(location: 0, length: ns.length)
        var result = normalizePattern.stringByReplacingMatches(in: base, range: range, withTemplate: ".")
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return result.lowercased()
    }
}
