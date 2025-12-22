import Foundation

/// Parser for JSON array strings like `["a","b","c"]`
enum ArrayStringParser {
    /// Checks if the string is a valid JSON array format
    static func isValidArrayString(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
    }

    /// Parses a JSON array string and returns the elements
    /// e.g., `["iOS","macOS","tvOS"]` → `["iOS", "macOS", "tvOS"]`
    static func parse(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            return []
        }

        // Try JSON decoding first for proper handling
        if let data = trimmed.data(using: .utf8),
           let array = try? JSONDecoder().decode([String].self, from: data)
        {
            return array
        }

        // Fallback to manual parsing for simple cases
        let inner = String(trimmed.dropFirst().dropLast())
        return inner.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
    }

    /// Converts a JSON array string to space-separated format
    /// e.g., `["iOS","macOS"]` → `"iOS macOS"`
    /// Returns the original value if not a valid array format
    static func toSpaceSeparated(_ value: String) -> String {
        guard isValidArrayString(value) else {
            return value
        }
        return parse(value).joined(separator: " ")
    }
}
