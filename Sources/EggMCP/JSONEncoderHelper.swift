import Foundation

// MARK: - JSON Encoding Helper

/// Shared JSON encoder configuration for consistent output
public enum JSONEncoderHelper {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public static func encode(_ value: some Encodable) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
