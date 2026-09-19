import Foundation
import UniformTypeIdentifiers

struct ZipInnerEntry: Sendable {
    let name: String
    let dataOffset: Int64
    let size: Int64
    let method: Int
    let mimeType: String

    var isStored: Bool { method == 0 }
}

enum ZipEntryResolver {
    private static let stored = 0

    static func resolveZipEntry(
        read: (Int64, Int) async throws -> Data,
        zipSize: Int64
    ) async throws -> ZipInnerEntry? {
        guard zipSize > 0 else { return nil }

        let headLen = Int(min(65536, zipSize))
        let head = try await read(0, headLen)
        if let lh = parseLocalHeader(head), lh.method == stored, lh.size > 0, !lh.hasDescriptor,
           lh.dataOffset + lh.size <= zipSize {
            return entry(from: lh)
        }

        let tailLen = Int(min(262144, zipSize))
        let tailStart = zipSize - Int64(tailLen)
        let tail = try await read(tailStart, tailLen)
        let cd = parseCentralDirectory(tail: tail, tailBase: tailStart, zipSize: zipSize)
        if let cd, cd.method == stored, cd.size > 0 {
            let lhBuf = try await read(cd.localOffset, min(4096, Int(zipSize - cd.localOffset)))
            if let lh2 = parseLocalHeader(lhBuf) {
                let dataOffset = cd.localOffset + Int64(lh2.dataOffset)
                if dataOffset + cd.size <= zipSize {
                    return ZipInnerEntry(
                        name: cd.name,
                        dataOffset: dataOffset,
                        size: cd.size,
                        method: stored,
                        mimeType: mimeType(for: cd.name)
                    )
                }
            }
        }

        if let lh = parseLocalHeader(head), lh.method == stored, !lh.hasDescriptor {
            return entry(from: lh)
        }
        return nil
    }

    private static func entry(from lh: LocalHeader) -> ZipInnerEntry {
        ZipInnerEntry(
            name: lh.name,
            dataOffset: Int64(lh.dataOffset),
            size: lh.size,
            method: lh.method,
            mimeType: mimeType(for: lh.name)
        )
    }

    private static func mimeType(for name: String) -> String {
        let ext = (name as NSString).pathExtension
        if let type = UTType(filenameExtension: ext) {
            return type.preferredMIMEType ?? "application/octet-stream"
        }
        return "video/x-matroska"
    }

    private struct LocalHeader {
        let method: Int
        let name: String
        let dataOffset: Int
        let size: Int64
        let compSize: Int64
        let hasDescriptor: Bool
    }

    private struct CentralDirectoryEntry {
        let method: Int
        let name: String
        let size: Int64
        let compSize: Int64
        let localOffset: Int64
    }

    private static func parseLocalHeader(_ buf: Data) -> LocalHeader? {
        guard buf.count >= 30 else { return nil }
        guard buf[0] == 0x50, buf[1] == 0x4b, buf[2] == 0x03, buf[3] == 0x04 else { return nil }

        let flag = u16(buf, 6)
        let method = u16(buf, 8)
        var comp = Int64(u32(buf, 18))
        var uncomp = Int64(u32(buf, 22))
        let nameLen = Int(u16(buf, 26))
        let extraLen = Int(u16(buf, 28))
        guard buf.count >= 30 + nameLen + extraLen else { return nil }

        let nameData = buf.subdata(in: 30..<(30 + nameLen))
        let name = String(data: nameData, encoding: .utf8) ?? ""
        let extra = buf.subdata(in: (30 + nameLen)..<(30 + nameLen + extraLen))
        if uncomp == 0xFFFF_FFFF || comp == 0xFFFF_FFFF {
            let sizes = zip64Sizes(extra: extra, uncomp: uncomp, comp: comp, needOffset: false, offset: 0)
            uncomp = sizes.uncomp
            comp = sizes.comp
        }

        return LocalHeader(
            method: method,
            name: name,
            dataOffset: 30 + nameLen + extraLen,
            size: uncomp,
            compSize: comp,
            hasDescriptor: (flag & 0x08) != 0
        )
    }

    private static func parseCentralDirectory(tail: Data, tailBase: Int64, zipSize: Int64) -> CentralDirectoryEntry? {
        guard let eocdRange = tail.range(of: Data([0x50, 0x4b, 0x05, 0x06]), options: .backwards) else {
            return nil
        }
        let eocd = eocdRange.lowerBound
        guard tail.count >= eocd + 22 else { return nil }

        var cdOffset = Int64(u32(tail, eocd + 16))

        if let z64loc = tail.range(of: Data([0x50, 0x4b, 0x06, 0x07]), options: .backwards),
           cdOffset == 0xFFFF_FFFF {
            let loc = z64loc.lowerBound
            if tail.count >= loc + 16 {
                let z64EocdOff = u64(tail, loc + 8)
                let rel = Int(z64EocdOff - tailBase)
                if rel >= 0, rel + 56 <= tail.count,
                   tail[rel] == 0x50, tail[rel + 1] == 0x4b, tail[rel + 2] == 0x06, tail[rel + 3] == 0x06 {
                    cdOffset = u64(tail, rel + 48)
                }
            }
        }

        let relCd = Int(cdOffset - tailBase)
        guard relCd >= 0, relCd + 46 <= tail.count else { return nil }
        guard tail[relCd] == 0x50, tail[relCd + 1] == 0x4b, tail[relCd + 2] == 0x01, tail[relCd + 3] == 0x02 else {
            return nil
        }

        let method = u16(tail, relCd + 10)
        var comp = Int64(u32(tail, relCd + 20))
        var uncomp = Int64(u32(tail, relCd + 24))
        let nameLen = Int(u16(tail, relCd + 28))
        let extraLen = Int(u16(tail, relCd + 30))
        let commentLen = Int(u16(tail, relCd + 32))
        var localOffset = Int64(u32(tail, relCd + 42))
        let nameStart = relCd + 46
        guard tail.count >= nameStart + nameLen + extraLen else { return nil }

        let name = String(data: tail.subdata(in: nameStart..<(nameStart + nameLen)), encoding: .utf8) ?? ""
        let extra = tail.subdata(in: (nameStart + nameLen)..<(nameStart + nameLen + extraLen))
        if uncomp == 0xFFFF_FFFF || comp == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF {
            let sizes = zip64Sizes(extra: extra, uncomp: uncomp, comp: comp, needOffset: true, offset: localOffset)
            uncomp = sizes.uncomp
            comp = sizes.comp
            localOffset = sizes.offset
        }

        return CentralDirectoryEntry(method: method, name: name, size: uncomp, compSize: comp, localOffset: localOffset)
    }

    private struct Zip64Sizes {
        var uncomp: Int64
        var comp: Int64
        var offset: Int64
    }

    private static func zip64Sizes(
        extra: Data,
        uncomp: Int64,
        comp: Int64,
        needOffset: Bool,
        offset: Int64
    ) -> Zip64Sizes {
        var u = uncomp
        var c = comp
        var o = offset
        var i = 0
        while i + 4 <= extra.count {
            let hid = u16(extra, i)
            let hsz = Int(u16(extra, i + 2))
            let bodyStart = i + 4
            let bodyEnd = bodyStart + hsz
            guard bodyEnd <= extra.count else { break }
            if hid == 0x0001 {
                let body = extra.subdata(in: bodyStart..<bodyEnd)
                var vals: [Int64] = []
                var j = 0
                while j + 8 <= body.count {
                    vals.append(u64(body, j))
                    j += 8
                }
                var k = 0
                if u == 0xFFFF_FFFF, k < vals.count { u = vals[k]; k += 1 }
                if c == 0xFFFF_FFFF, k < vals.count { c = vals[k]; k += 1 }
                if needOffset, o == 0xFFFF_FFFF, k < vals.count { o = vals[k]; k += 1 }
                break
            }
            i += 4 + hsz
        }
        return Zip64Sizes(uncomp: u, comp: c, offset: o)
    }

    private static func u16(_ data: Data, _ offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func u64(_ data: Data, _ offset: Int) -> Int64 {
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(data[offset + i]) << (UInt8(i * 8))
        }
        return Int64(bitPattern: value)
    }
}
