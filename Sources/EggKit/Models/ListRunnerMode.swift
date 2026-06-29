import Foundation

/// Represents the mode of operation for the list runner.
package enum ListRunnerMode {
    /// Display mode - shows templates in a table format using Noora
    case display

    /// MCP mode - returns structured data for programmatic use
    /// - Parameter location: Optional location filter. If nil, lists all locations.
    case mcp(location: TemplateLocationType?)
}
