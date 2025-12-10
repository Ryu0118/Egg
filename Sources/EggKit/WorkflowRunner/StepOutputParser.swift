import Foundation

/// Parses key-value pairs from shell script stdout.
///
/// Extracts outputs in the format `key=value` from shell command stdout.
/// Each line is processed independently, and the first `=` character is used as the delimiter.
///
/// Example:
/// ```swift
/// let stdout = """
/// version=1.0.0
/// src-dir=/tmp/src
/// """
/// let outputs = StepOutputParser.parse(stdout)
/// // ["version": "1.0.0", "src-dir": "/tmp/src"]
/// ```
enum StepOutputParser {
    /// Parses stdout into key-value pairs.
    ///
    /// - Parameter stdout: Shell command stdout containing key=value pairs
    /// - Returns: Dictionary of parsed key-value pairs
    ///
    /// Parsing rules:
    /// - Split by newlines
    /// - Find first `=` in each line
    /// - Trim whitespace from keys and values
    /// - Skip empty lines
    /// - Values can contain `=` characters
    static func parse(_ stdout: String) -> [String: String] {
        var result: [String: String] = [:]

        for line in stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            guard !trimmedLine.isEmpty else {
                continue
            }

            // Find first = character
            guard let equalIndex = trimmedLine.firstIndex(of: "=") else {
                continue
            }

            let key = trimmedLine[..<equalIndex].trimmingCharacters(in: .whitespaces)
            let valueStartIndex = trimmedLine.index(after: equalIndex)
            let value = trimmedLine[valueStartIndex...].trimmingCharacters(in: .whitespaces)

            // Skip if key is empty
            guard !key.isEmpty else {
                continue
            }

            result[key] = value
        }

        return result
    }
}
