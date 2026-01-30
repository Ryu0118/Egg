import ArgumentParser
import EggMCP
import Foundation

package struct MCPCommand: AsyncParsableCommand {
    package static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Start the MCP (Model Context Protocol) server for AI assistant integration."
    )

    package init() {}

    package func run() async throws {
        let server = EggMCPServer()
        try await server.start()
    }
}
