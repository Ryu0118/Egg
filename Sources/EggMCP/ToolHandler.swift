import Foundation
import MCP

// MARK: - Tool Handler Protocol

/// Protocol for handling individual MCP tool calls.
/// Each tool handler is responsible for a single tool, following Single Responsibility Principle.
public protocol ToolHandler: Sendable {
    /// The name of the tool this handler handles
    static var toolName: String { get }

    /// Execute the tool with the given context
    /// - Parameter context: The execution context containing parsed arguments
    /// - Returns: The result string to return to the client
    func execute(with context: ToolContext) async throws -> String
}
