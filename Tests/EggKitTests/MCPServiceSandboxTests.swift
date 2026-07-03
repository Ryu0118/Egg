@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct MCPServiceSandboxTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    @Test
    func `preview sandbox disable requires explicit MCP confirmation`() async throws {
        let workspace = try makeWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }

        let service = MCPService(
            fileManager: fileManager,
            workingDirectory: workspace.projectDirectory,
            projectDirectory: workspace.projectDirectory,
            homeDirectory: workspace.homeDirectory,
        )

        do {
            _ = try await service.previewHatchTemplate(
                templateName: "SandboxedPreview",
                macros: [:],
                disableSandbox: true,
            )
            Issue.record("Expected sandbox disable confirmation error")
        } catch let error as MCPServiceError {
            #expect(error.localizedDescription.contains("user_confirmed_no_sandbox: true"))
        }
    }

    private func makeWorkspace() throws -> Workspace {
        let root = try fileManager.makeTemporaryDirectory(prefix: "MCPServiceSandboxTests")
        let projectDirectory = root.appending(path: "project")
        let homeDirectory = root.appending(path: "home")
        let templateDirectory = projectDirectory.appending(path: ".eggs/SandboxedPreview")
        try fileManager.createDirectory(at: templateDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try fileManager.writeText(
            """
            name: SandboxedPreview
            description: Preview template
            hatch:
              output: .
            """,
            at: templateDirectory.appending(path: "config.yml"),
        )
        return Workspace(root: root, projectDirectory: projectDirectory, homeDirectory: homeDirectory)
    }

    private struct Workspace {
        let root: URL
        let projectDirectory: URL
        let homeDirectory: URL
    }
}
