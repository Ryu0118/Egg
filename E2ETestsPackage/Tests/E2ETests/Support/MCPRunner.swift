import Foundation

/// Drives a live `egg mcp` server over its stdio JSON-RPC transport.
///
/// Requests are newline-delimited JSON on stdin; responses arrive as
/// newline-delimited JSON on stdout. All mutable state (the line buffer,
/// pending waiters) is actor-isolated — no manual locks, and every value
/// crossing the actor boundary is the `Sendable` `JSONValue`. The only
/// non-isolated code is `Process`'s `readabilityHandler`, which the OS
/// invokes on its own dispatch queue; it immediately hops back into the
/// actor via a `Task`, so it never touches actor state directly.
actor MCPRunner {
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
    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle
    private var partial = Data()
    private var responses: [Int: JSONValue] = [:]
    private var waiters: [Int: CheckedContinuation<JSONValue, Swift.Error>] = [:]
    private var nextID = 100

    static func start() async throws -> MCPRunner {
        let binary = try await BinaryBuildState.shared.getBinaryPath()
        let runner = try MCPRunner(binary: binary)
        _ = try await runner.request(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [:] as [String: Any],
            "clientInfo": ["name": "e2e", "version": "1"],
        ])
        try await runner.notify(method: "notifications/initialized")
        return runner
    }

    private init(binary: URL) throws {
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.executableURL = binary
        process.arguments = ["mcp"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading

        try process.run()

        let handle = stdoutHandle
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard let self, !data.isEmpty else { return }
            Task { await self.ingest(data) }
        }
    }

    /// Deterministically stops the server. Closing stdin delivers EOF to the
    /// server's read loop for a clean exit; a SIGKILL fallback covers a
    /// server that ignores it. Callers must await this before the test ends
    /// (see `withMCPRunner` in the tests) — a leaked `egg mcp` child holds
    /// inherited pipe fds and can wedge the whole test run at exit.
    func shutdown() {
        stdoutHandle.readabilityHandler = nil
        try? stdinHandle.close()
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        for (_, continuation) in waiters {
            continuation.resume(throwing: Error.malformedResponse("runner shut down"))
        }
        waiters.removeAll()
    }

    deinit {
        // Backstop only — shutdown() is the contract. SIGKILL because the
        // server ignores SIGTERM (its stdin loop keeps it alive).
        stdoutHandle.readabilityHandler = nil
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    /// Sends a request and returns the matched response object, or throws
    /// `.timedOut` after 30s.
    func request(method: String, params: [String: Any]) async throws -> JSONValue {
        nextID += 1
        let id = nextID
        try send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        if let already = responses.removeValue(forKey: id) {
            return already
        }

        // The continuation is registered synchronously (within this actor
        // method, before any suspension), so `ingest` can never observe the
        // request as neither answered nor awaited.
        return try await withCheckedThrowingContinuation { continuation in
            waiters[id] = continuation
            Task {
                try await Task.sleep(for: .seconds(30))
                await self.timeOut(id)
            }
        }
    }

    /// Calls an MCP tool and returns `(isError, text)` — the text content of
    /// the first content block, plus whether the server flagged an error.
    func callTool(_ name: String, arguments: [String: Any]) async throws -> (isError: Bool, text: String) {
        let response = try await request(method: "tools/call", params: ["name": name, "arguments": arguments])
        guard let text = response["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue else {
            throw Error.malformedResponse("\(response)")
        }
        return (response["result"]?["isError"]?.boolValue ?? false, text)
    }

    /// Calls a tool expected to succeed and decodes its JSON payload.
    func callToolJSON(_ name: String, arguments: [String: Any]) async throws -> JSONValue {
        let (isError, text) = try await callTool(name, arguments: arguments)
        guard !isError else { throw Error.malformedResponse("tool \(name) errored: \(text)") }
        return try JSONValue.decode(text)
    }

    /// Resolves a still-pending waiter with a timeout error. A no-op if the
    /// response already arrived and removed the waiter first.
    private func timeOut(_ id: Int) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.resume(throwing: Error.timedOut(waitingFor: id))
    }

    // MARK: - Private

    private func notify(method: String) throws {
        try send(["jsonrpc": "2.0", "method": method])
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try stdinHandle.write(contentsOf: data)
    }

    /// Called only from the `Task` the readability handler spawns — always
    /// on the actor, never concurrently with itself.
    private func ingest(_ data: Data) {
        partial.append(data)
        while let newline = partial.firstIndex(of: 0x0A) {
            let lineData = partial[partial.startIndex ..< newline]
            partial.removeSubrange(partial.startIndex ... newline)
            guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty,
                  let value = try? JSONValue.decode(line),
                  let id = value["id"]?.numberValue
            else { continue }
            let intID = Int(id)

            if let waiter = waiters.removeValue(forKey: intID) {
                waiter.resume(returning: value)
            } else {
                responses[intID] = value
            }
        }
    }
}

private extension JSONValue {
    var numberValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }
}
