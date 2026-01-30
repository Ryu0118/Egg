import Foundation
import MCP

// MARK: - Tool Context

/// Context for tool execution, containing parsed arguments and utilities.
/// This abstraction allows for easier testing by decoupling from MCP types.
public struct ToolContext: Sendable {
    public let arguments: ToolArguments

    public init(arguments: [String: Value]) {
        self.arguments = ToolArguments(raw: arguments)
    }

    public init(arguments: ToolArguments) {
        self.arguments = arguments
    }
}
