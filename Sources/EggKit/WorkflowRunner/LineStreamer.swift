/// Buffers streaming output and emits complete lines.
///
/// Use when processing chunked output that may split across line boundaries.
///
/// ```swift
/// let streamer = LineStreamer { line in
///     print("Line: \(line)")
/// }
/// streamer.append("Hello\nWor")
/// streamer.append("ld\n")
/// streamer.flush()
/// // Output:
/// // Line: Hello
/// // Line: World
/// ```
final class LineStreamer {
    private var buffer = ""
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    /// Appends a chunk and emits any complete lines.
    func append(_ chunk: String) {
        buffer += chunk
        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newlineIndex])
            onLine(line)
            buffer = String(buffer[buffer.index(after: newlineIndex)...])
        }
    }

    /// Flushes remaining buffer content (for lines without trailing newline).
    func flush() {
        if !buffer.isEmpty {
            onLine(buffer)
            buffer = ""
        }
    }
}
