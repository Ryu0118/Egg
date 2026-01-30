import Foundation
import MCP

/// Actor-based registry for tool handlers.
/// Maps tool names to their handlers, following Open/Closed principle -
/// new tools can be added by registering new handlers without modifying existing code.
/// Using actor ensures thread-safe access to the registry.
public actor ToolHandlerRegistry {
    /// Shared instance
    public static let shared = ToolHandlerRegistry()

    /// Dictionary mapping tool names to their handlers
    private let handlers: [String: any ToolHandler] = [
        // Template management handlers
        ListHandler.toolName: ListHandler(),
        DetailHandler.toolName: DetailHandler(),
        ValidateHandler.toolName: ValidateHandler(),
        CreateHandler.toolName: CreateHandler(),
        DeleteHandler.toolName: DeleteHandler(),
        DuplicateHandler.toolName: DuplicateHandler(),
        MoveHandler.toolName: MoveHandler(),
        InstallHandler.toolName: InstallHandler(),

        // Hatch handler
        HatchHandler.toolName: HatchHandler(),
    ]

    /// Get handler for a tool name
    public func handler(for toolName: String) -> (any ToolHandler)? {
        handlers[toolName]
    }

    /// Execute a tool call
    public func execute(toolName: String, arguments: [String: Value]) async throws -> String {
        guard let handler = handler(for: toolName) else {
            throw ToolRegistryError.unknownTool(toolName)
        }

        let context = ToolContext(arguments: arguments)
        return try await handler.execute(with: context)
    }

    /// Get all registered tool names
    public var registeredToolNames: [String] {
        Array(handlers.keys)
    }
}

// MARK: - Tool Registry Error

public enum ToolRegistryError: LocalizedError, Equatable {
    case unknownTool(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownTool(name):
            "Unknown tool: \(name)"
        }
    }
}
