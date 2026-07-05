import Foundation

/// Drives a live `egg mcp` server over its stdio JSON-RPC transport.
///
/// Requests are newline-delimited JSON on stdin; responses arrive as
/// newline-delimited JSON on stdout and are matched to requests by id. A
/// background thread drains stdout into a locked line buffer so calls can
/// poll with a deadline instead of blocking forever on a hung server.
/// `@unchecked Sendable`: the mutable line buffer is guarded by `lock`, and
/// requests are issued from a single test task at a time.
final class MCPRunner: @unchecked Sendable {
    enum Error: Swift.Error, CustomStringConvertible {
        case timedOut(waitingFor: Int)
        case malformedResponse(String)

        var description: String {
            switch self {
            case let .timedOut(id): "Timed out waiting for MCP response id \(id)"
            case let .malformedResponse(line): "Malformed MCP response line: \(line)"
            }
        }
    }

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let lock = NSLock()
    private var lines: [String] = []
    private var partial = Data()
    private var nextID = 100

    init() async throws {
        let binary = try await BinaryBuildState.shared.getBinaryPath()
        process.executableURL = binary
        process.arguments = ["mcp"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            lock.lock()
            partial.append(data)
            while let newline = partial.firstIndex(of: 0x0A) {
                let lineData = partial[partial.startIndex ..< newline]
                partial.removeSubrange(partial.startIndex ... newline)
                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                    lines.append(line)
                }
            }
            lock.unlock()
        }

        try process.run()

        _ = try request(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [:] as [String: Any],
            "clientInfo": ["name": "e2e", "version": "1"],
        ])
        try notify(method: "notifications/initialized")
    }

    deinit {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        process.terminate()
    }

    /// Sends a request and returns the matched response object.
    func request(method: String, params: [String: Any]) throws -> [String: Any] {
        nextID += 1
        let id = nextID
        try send([
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ])
        return try waitForResponse(id: id)
    }

    /// Calls an MCP tool and returns `(isError, text)` — the text content of
    /// the first content block, plus whether the server flagged an error.
    func callTool(_ name: String, arguments: [String: Any]) throws -> (isError: Bool, text: String) {
        let response = try request(method: "tools/call", params: [
            "name": name,
            "arguments": arguments,
        ])
        guard let result = response["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
        else {
            throw Error.malformedResponse("\(response)")
        }
        return (result["isError"] as? Bool ?? false, text)
    }

    /// Calls a tool expected to succeed and decodes its JSON payload.
    func callToolJSON(_ name: String, arguments: [String: Any]) throws -> [String: Any] {
        let (isError, text) = try callTool(name, arguments: arguments)
        guard !isError else { throw Error.malformedResponse("tool \(name) errored: \(text)") }
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        guard let dictionary = object as? [String: Any] else {
            throw Error.malformedResponse(text)
        }
        return dictionary
    }

    private func notify(method: String) throws {
        try send(["jsonrpc": "2.0", "method": method])
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func waitForResponse(id: Int, timeout: TimeInterval = 30) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            let snapshot = lines
            lock.unlock()
            for line in snapshot {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                      let dictionary = object as? [String: Any],
                      dictionary["id"] as? Int == id
                else { continue }
                return dictionary
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw Error.timedOut(waitingFor: id)
    }
}
