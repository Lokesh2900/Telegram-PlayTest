import Foundation
import Network

final class VirtualStreamServer {
    private let queue = DispatchQueue(label: "VirtualStreamServer")
    private var listener: NWListener?
    private var port: UInt16 = 0
    private var sessions: [UUID: VirtualStreamSession] = [:]
    private var byteSource: TDLibVirtualByteSource?

    func attach(byteSource: TDLibVirtualByteSource) {
        self.byteSource = byteSource
    }

    func register(session: VirtualStreamSession) async throws -> URL {
        if listener == nil {
            try startListener()
        }
        for _ in 0..<200 where port == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard port != 0 else { throw VirtualStreamError.readFailed }
        sessions[session.id] = session
        return URL(string: "http://127.0.0.1:\(port)/stream/\(session.id.uuidString)")!
    }

    func unregister(sessionId: UUID) {
        sessions.removeValue(forKey: sessionId)
        if sessions.isEmpty {
            stopListener()
        }
    }

    private func startListener() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint(host: .ipv4(.loopback), port: .any)
        guard let nwPort = NWEndpoint.Port(rawValue: port == 0 ? 0 : port) else {
            throw VirtualStreamError.readFailed
        }
        let listener = try NWListener(using: params, on: nwPort)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.port = listener.port?.rawValue ?? 0
            }
        }
        listener.start(queue: queue)
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                connection.cancel()
                print("VirtualStream receive error: \(error)")
                return
            }
            var buf = buffer
            if let data { buf.append(data) }
            if let headerEnd = buf.range(of: Data([13, 10, 13, 10])) {
                let headerData = buf.subdata(in: 0..<headerEnd.lowerBound)
                self.handleHTTP(headers: headerData, connection: connection)
                return
            }
            if isComplete {
                connection.cancel()
                return
            }
            self.receiveRequest(on: connection, buffer: buf)
        }
    }

    private func handleHTTP(headers: Data, connection: NWConnection) {
        guard let requestLine = String(data: headers, encoding: .utf8)?
            .components(separatedBy: "\r\n").first else {
            connection.cancel()
            return
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }
        let method = String(parts[0])
        let path = String(parts[1])
        guard method == "GET" || method == "HEAD" else {
            sendStatus(connection: connection, code: 405, body: "Method Not Allowed")
            return
        }

        guard path.hasPrefix("/stream/") else {
            sendStatus(connection: connection, code: 404, body: "Not Found")
            return
        }
        let uuidString = String(path.dropFirst("/stream/".count))
        guard let sessionId = UUID(uuidString: uuidString), let session = sessions[sessionId] else {
            sendStatus(connection: connection, code: 404, body: "Session Not Found")
            return
        }

        let headerText = String(data: headers, encoding: .utf8) ?? ""
        let rangeHeader = headerText
            .components(separatedBy: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("range:") })
            .map { String($0.dropFirst(6).trimmingCharacters(in: .whitespaces)) }

        let fileSize = session.streamLength
        let (start, end, isPartial) = HTTPRange.parse(rangeHeader, fileSize: fileSize)
        let length = end - start + 1

        var responseHeaders = """
        HTTP/1.1 \(isPartial ? "206 Partial Content" : "200 OK")\r
        Content-Type: \(session.mimeType)\r
        Accept-Ranges: bytes\r
        Content-Length: \(length)\r
        Connection: close\r
        """
        if isPartial {
            responseHeaders += "Content-Range: bytes \(start)-\(end)/\(fileSize)\r"
        }
        responseHeaders += "\r"

        let headerBytes = Data(responseHeaders.utf8)
        if method == "HEAD" {
            connection.send(content: headerBytes, completion: .contentProcessed { _ in connection.cancel() })
            return
        }

        connection.send(content: headerBytes, completion: .contentProcessed { [weak self] error in
            if error != nil {
                connection.cancel()
                return
            }
            self?.streamBody(session: session, innerStart: start, innerEnd: end, connection: connection)
        })
    }

    private func streamBody(session: VirtualStreamSession, innerStart: Int64, innerEnd: Int64, connection: NWConnection) {
        guard let byteSource else {
            connection.cancel()
            return
        }
        guard let zipRange = session.zipByteRange(innerStart: innerStart, innerEnd: innerEnd) else {
            connection.cancel()
            return
        }
        let (globalStart, globalEnd) = zipRange
        let manifest = session.manifest

        Task {
            do {
                guard let byteSource else {
                    connection.cancel()
                    return
                }
                let stream = await byteSource.streamVirtualBytes(
                    manifest: manifest,
                    globalStart: globalStart,
                    globalEnd: globalEnd
                )
                for try await chunk in stream {
                    let finished = await sendChunk(chunk, on: connection)
                    if !finished { break }
                }
                connection.cancel()
            } catch {
                connection.cancel()
            }
        }
    }

    private func sendChunk(_ chunk: Data, on connection: NWConnection) async -> Bool {
        await withCheckedContinuation { continuation in
            connection.send(content: chunk, completion: .contentProcessed { error in
                continuation.resume(returning: error == nil)
            })
        }
    }

    private func sendStatus(connection: NWConnection, code: Int, body: String) {
        let text = "HTTP/1.1 \(code) \(body)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}

private enum HTTPRange {
    static func parse(_ header: String?, fileSize: Int64) -> (start: Int64, end: Int64, isPartial: Bool) {
        guard fileSize > 0 else { return (0, 0, false) }
        guard let header, header.lowercased().hasPrefix("bytes=") else {
            return (0, fileSize - 1, false)
        }
        let value = header.dropFirst(6)
        let pieces = value.split(separator: "-", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else { return (0, fileSize - 1, false) }

        let startStr = pieces[0]
        let endStr = pieces[1]
        var start: Int64 = 0
        var end: Int64 = fileSize - 1

        if startStr.isEmpty {
            let suffixLength = Int64(endStr) ?? fileSize
            start = max(0, fileSize - suffixLength)
            end = fileSize - 1
        } else if endStr.isEmpty {
            start = Int64(startStr) ?? 0
            end = fileSize - 1
        } else {
            start = Int64(startStr) ?? 0
            end = Int64(endStr) ?? fileSize - 1
        }

        start = max(0, start)
        end = min(fileSize - 1, end)
        if end < start { end = start }
        let isPartial = header.lowercased().hasPrefix("bytes=")
        return (start, end, isPartial)
    }
}
