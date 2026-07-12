@testable import EggMCP
import Foundation
import Testing

@Suite("EggMCP module builds and exposes its public entry points")
struct EggMCPTests {
    @Test("EggMCP module can be imported and its public API compiles without linking errors")
    func eggMCPModuleIsImportable() {
        #expect(Bool(true))
    }

    @Test("Every declared tool has a registered handler, and vice versa")
    func everyDeclaredToolHasARegisteredHandler() async {
        let declared = Set(EggMCPServer.tools.map(\.name))
        let registered = await Set(ToolHandlerRegistry.shared.registeredToolNames)
        #expect(declared == registered)
        #expect(declared.contains("egg_hatch_transactions"))
        #expect(declared.contains("egg_template_sync"))
        #expect(declared.contains("egg_template_update"))
    }

    @Test("egg_template_sync installs a project manifest's local entry and returns encoded JSON")
    func syncToolExecutesEndToEnd() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(path: "EggMCPSyncTests-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let project = root.appending(path: "project")
        let templateDir = project.appending(path: "local-templates/MCPTemplate")
        try fileManager.createDirectory(at: templateDir, withIntermediateDirectories: true)
        try """
        name: "MCPTemplate"
        description: "A test template"
        hatch:
          output: "./output"
        """.write(to: templateDir.appending(path: "config.yml"), atomically: true, encoding: .utf8)
        try """
        eggs:
          - url: ./local-templates
        """.write(to: project.appending(path: "eggs.yml"), atomically: true, encoding: .utf8)

        let json = try await ToolHandlerRegistry.shared.execute(
            toolName: "egg_template_sync",
            arguments: [
                "scope": "project",
                "project_directory": .string(project.path(percentEncoded: false)),
            ],
        )

        #expect(json.contains("\"MCPTemplate\""))
        #expect(json.contains("\"scope\" : \"project\""))
        #expect(fileManager.fileExists(atPath: project.appending(path: ".eggs/MCPTemplate/config.yml").path))
    }
}
