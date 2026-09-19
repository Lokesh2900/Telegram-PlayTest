import Foundation

enum VirtualStreamContent: Sendable {
    case raw(manifest: VirtualFileManifest)
    case zip(manifest: VirtualFileManifest, inner: ZipInnerEntry)
}

struct VirtualStreamSession: Sendable {
    let id: UUID
    let content: VirtualStreamContent
    let fileName: String
    let mimeType: String

    var streamLength: Int64 {
        switch content {
        case .raw(let manifest):
            return manifest.totalSize
        case .zip(_, let inner):
            return inner.size
        }
    }

    var manifest: VirtualFileManifest {
        switch content {
        case .raw(let manifest), .zip(let manifest, _):
            return manifest
        }
    }

    func zipByteRange(innerStart: Int64, innerEnd: Int64) -> (Int64, Int64)? {
        switch content {
        case .raw:
            return (innerStart, innerEnd)
        case .zip(_, let inner):
            return (inner.dataOffset + innerStart, inner.dataOffset + innerEnd)
        }
    }
}
