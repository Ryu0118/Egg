@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct MCPServiceSandboxTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    @Test("previewHatchTemplate rejects a disableSandbox request over MCP unless the caller has explicitly confirmed user_confirmed_no_sandbox")
    func previewSandboxDisableRequiresExplicitMCPConfirmation() async throws {
        let workspace = try makeWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }

        let service = EggService(
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
        } catch let error as EggServiceError {
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

/// Over MCP there is no prompt channel: reaching the human flow's non-git
/// confirmation exits the process and kills the server mid-request. The
/// service must refuse a staged hatch of a non-git directory up front with
/// a structured, actionable error instead. MCP only exposes the transaction
/// flow (preview/apply), so this is exercised through previewHatchTemplate —
/// the same StagingFeasibility guard previewHatchTemplate and apply share.
extension MCPServiceSandboxTests {
    @Test("previewing a staged hatch of a non-git directory throws instead of reaching the process-killing prompt")
    func stagedHatchOnNonGitDirectoryThrows() async throws {
        let workspace = try makeWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }

        let service = EggService(
            fileManager: fileManager,
            workingDirectory: workspace.projectDirectory,
            projectDirectory: workspace.projectDirectory,
            homeDirectory: workspace.homeDirectory,
        )

        do {
            _ = try await service.previewHatchTemplate(
                templateName: "SandboxedPreview",
                macros: [:],
            )
            Issue.record("expected nonGitStagingRequiresConsent")
        } catch let error as AgentHatchTransactionRunner.Error {
            #expect(error.localizedDescription.contains("--no-staging"))
            #expect(error.localizedDescription.contains("git init"))
            #expect(error.localizedDescription.contains("allow-non-git-staging"))
            #expect(error.localizedDescription.contains("files"), "the refusal must report the measured size")
        }
    }

    @Test("allow_non_git_staging previews, and apply stages the non-git directory and applies the template")
    func consentedNonGitStagedHatchSucceeds() async throws {
        let workspace = try makeWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }
        try fileManager.writeText("hello\n", at: workspace.projectDirectory.appending(path: ".eggs/SandboxedPreview/Made.txt"))

        let service = EggService(
            fileManager: fileManager,
            workingDirectory: workspace.projectDirectory,
            projectDirectory: workspace.projectDirectory,
            homeDirectory: workspace.homeDirectory,
        )

        let preview = try await service.previewHatchTemplate(
            templateName: "SandboxedPreview",
            macros: [:],
            allowNonGitStaging: true,
        )
        _ = try await service.applyHatchTransaction(applyToken: preview.applyToken)

        #expect(fileManager.exists(workspace.projectDirectory.appending(path: "Made.txt")))
    }
}
