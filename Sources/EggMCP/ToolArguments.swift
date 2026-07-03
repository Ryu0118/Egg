import Foundation
import MCP

// MARK: - Tool Arguments

/// Type-safe wrapper for tool arguments with convenient accessors.
public struct ToolArguments: Sendable {
    private let raw: [String: Value]

    public init(raw: [String: Value]) {
        self.raw = raw
    }

    /// Get a required string argument
    public func requireString(_ key: String) throws -> String {
        guard let value = raw[key]?.stringValue else {
            throw ToolArgumentError.missingParameter(key)
        }
        return value
    }

    /// Get an optional string argument
    public func optionalString(_ key: String) -> String? {
        raw[key]?.stringValue
    }

    /// Get a required boolean argument with default value
    public func bool(_ key: String, default defaultValue: Bool) -> Bool {
        raw[key]?.boolValue ?? defaultValue
    }

    /// Get a required array of strings
    public func requireStringArray(_ key: String) throws -> [String] {
        guard let arrayValue = raw[key]?.arrayValue else {
            throw ToolArgumentError.missingParameter(key)
        }
        return arrayValue.compactMap(\.stringValue)
    }

    /// Get an optional array of strings
    public func optionalStringArray(_ key: String) -> [String]? {
        raw[key]?.arrayValue?.compactMap(\.stringValue)
    }

    /// Get a required object (dictionary) of string to any value
    public func requireObject(_ key: String) throws -> [String: Value] {
        guard let objectValue = raw[key]?.objectValue else {
            throw ToolArgumentError.missingParameter(key)
        }
        return objectValue
    }

    /// Get an optional object (dictionary) of string to any value
    public func optionalObject(_ key: String) -> [String: Value]? {
        raw[key]?.objectValue
    }

    /// Get a required macros dictionary (string to any JSON value)
    /// Converts MCP Value types to appropriate Swift types for macro resolution
    public func requireMacros(_ key: String) throws -> [String: Any] {
        guard let objectValue = raw[key]?.objectValue else {
            throw ToolArgumentError.missingParameter(key)
        }
        return parseMacros(from: objectValue)
    }

    /// Get an optional macros dictionary
    public func optionalMacros(_ key: String) -> [String: Any]? {
        guard let objectValue = raw[key]?.objectValue else {
            return nil
        }
        return parseMacros(from: objectValue)
    }

    /// Parse macros from a Value object, converting to appropriate Swift types
    private func parseMacros(from objectValue: [String: Value]) -> [String: Any] {
        var macros: [String: Any] = [:]
        for (name, value) in objectValue {
            macros[name] = convertValue(value)
        }
        return macros
    }

    /// Convert a Value to its Swift equivalent
    private func convertValue(_ value: Value) -> Any {
        if let stringValue = value.stringValue {
            return stringValue
        }
        if let boolValue = value.boolValue {
            return boolValue
        }
        if let intValue = value.intValue {
            return intValue
        }
        if let doubleValue = value.doubleValue {
            return doubleValue
        }
        if let arrayValue = value.arrayValue {
            return arrayValue.map { convertValue($0) }
        }
        if let objectValue = value.objectValue {
            return parseMacros(from: objectValue)
        }
        return ""
    }
}

// MARK: - Tool Argument Error

public enum ToolArgumentError: LocalizedError, Equatable {
    case missingParameter(String)
    case invalidParameter(String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .missingParameter(key):
            "Missing required parameter: '\(key)'"
        case let .invalidParameter(key, reason):
            "Invalid parameter '\(key)': \(reason)"
        }
    }
}
