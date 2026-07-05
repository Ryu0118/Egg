@testable import EggKit
import FileManagerProtocol
import Foundation
import ProcessRunning
import Testing

@Suite("Preview transactions run lifecycle hooks in a sandboxed staging area")
struct AgentHatchPreviewTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    @Test("Fails fast with writeConsentRequired listing the declared paths when nothing was consented")
    func rejectsDeclaredAllowedPathsWithoutConsent() async throws {
        let workspace = try makeWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }

        await #expect(throws: AgentHatchTransactionRunner.Error.writeConsentRequired(declaredPaths: ["/tmp/egg-preview-test"])) {
            try await makeRunner(workspace: workspace, sandboxDisabled: false).preview()
        }
    }

    @Test("Fails with writeConsentNotDeclared when a consented path is not declared in config")
    func rejectsConsentForUndeclaredPath() async throws {
        let workspace = try makeWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }

        await #expect(throws: AgentHatchTransactionRunner.Error.writeConsentNotDeclared(
            paths: ["/tmp/not-declared"],
            declaredPaths: ["/tmp/egg-preview-test"],
        )) {
            try await makeRunner(
                workspace: workspace,
                sandboxDisabled: false,
                allowedWritePaths: ["/tmp/not-declared"],
            ).preview()
        }
    }

    @Test("Succeeds and reports the generated file when sandboxDisabled is true, bypassing the consent check")
    func allowsPreviewSandboxBypassWhenExplicitlyDisabled() async throws {
        let workspace = try makeWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }

        let result = try await makeRunner(workspace: workspace, sandboxDisabled: true).preview()

        #expect(result.templateName == "PreviewTemplate")
        #expect(result.changes.contains { $0.path == "Generated.txt" && $0.kind == "add" })
    }

    @Test("Grants write access to a consented declared path and warns that external writes are immediate")
    func grantsConsentedDeclaredPathAndWarns() async throws {
        let workspace = try makeWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }
        // Outside the system temp tree: the sandbox profile blanket-allows
        // writes under /private/tmp and /private/var/folders, so a temp-based
        // path would be writable regardless of the grant.
        let externalDirectory = try makeExternalDirectory()
        defer { try? fileManager.removeItem(at: externalDirectory) }
        let externalPath = externalDirectory.path(percentEncoded: false)
        let externalFile = externalDirectory.appending(path: "marker.txt")

        let result = try await makeRunner(
            workspace: workspace,
            sandboxDisabled: false,
            declaredPaths: [externalPath],
            allowedWritePaths: [externalPath],
            postHatch: [Config.LifecycleStep(run: "echo written > '\(externalFile.path(percentEncoded: false))'")],
        ).preview()

        #expect(result.warnings.contains { $0.code == "external_writes_immediate" })
        #expect(fileManager.exists(externalFile), "post_hatch should be able to write to the consented external path")
    }

    @Test("Keeps unconsented declared paths denied and reports them in a warning when consent is partial")
    func partialConsentKeepsRemainingPathsDenied() async throws {
        let workspace = try makeWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }
        // Outside the system temp tree — see grantsConsentedDeclaredPathAndWarns.
        let externalRoot = try makeExternalDirectory()
        defer { try? fileManager.removeItem(at: externalRoot) }
        let grantedDirectory = externalRoot.appending(path: "granted")
        let deniedDirectory = externalRoot.appending(path: "denied")
        try fileManager.createDirectory(at: grantedDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: deniedDirectory, withIntermediateDirectories: true)
        let grantedPath = grantedDirectory.path(percentEncoded: false)
        let deniedPath = deniedDirectory.path(percentEncoded: false)
        let deniedFile = deniedDirectory.appending(path: "marker.txt")

        let result = try await makeRunner(
            workspace: workspace,
            sandboxDisabled: false,
            declaredPaths: [grantedPath, deniedPath],
            allowedWritePaths: [grantedPath],
            // `|| true`: the sandbox denial must not fail the step — the test
            // asserts the write was blocked, not that the workflow aborted.
            postHatch: [Config.LifecycleStep(run: "echo written > '\(deniedFile.path(percentEncoded: false))' || true")],
        ).preview()

        #expect(result.warnings.contains { $0.code == "declared_paths_not_granted" })
        #expect(!fileManager.exists(deniedFile), "unconsented declared path must stay write-denied")
    }

    private func makeWorkspace() throws -> Workspace {
        let root = try fileManager.makeTemporaryDirectory(prefix: "AgentHatchPreviewTests")
        let workingDirectory = root.appending(path: "work")
        let homeDirectory = root.appending(path: "home")
        let templateDirectory = root.appending(path: "template")
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: templateDirectory, withIntermediateDirectories: true)
        try initializeGitRepository(at: workingDirectory)
        try fileManager.writeText("Generated by preview\n", at: templateDirectory.appending(path: "Generated.txt"))
        return Workspace(
            root: root,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            templateDirectory: templateDirectory,
        )
    }

    private func makeRunner(
        workspace: Workspace,
        sandboxDisabled: Bool,
        declaredPaths: [String] = ["/tmp/egg-preview-test"],
        allowedWritePaths: [String] = [],
        postHatch: [Config.LifecycleStep]? = nil,
    ) -> AgentHatchTransactionRunner {
        AgentHatchTransactionRunner(
            processRunner: ProcessRunner(),
            fileManager: fileManager,
            workingDirectory: workspace.workingDirectory,
            homeDirectory: workspace.homeDirectory,
            templateDirectory: workspace.templateDirectory,
            config: Config(
                name: "PreviewTemplate",
                description: "Preview template",
                sandbox: .init(allowedPaths: declaredPaths),
                hatch: .init(output: "."),
                postHatch: postHatch,
            ),
            parsedMacros: [],
            sandboxDisabled: sandboxDisabled,
            allowedWritePaths: allowedWritePaths,
        )
    }

    /// Creates a directory outside the system temp tree (which the sandbox
    /// profile blanket-allows) so write-denial behavior is actually observable.
    private func makeExternalDirectory() throws -> URL {
        let directory = URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: ".build/egg-preview-tests")
            .appending(path: UUID().uuidString)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func initializeGitRepository(at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["init", "--quiet"]
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw GitInitializationError.failed(status: process.terminationStatus)
        }
    }

    private struct Workspace {
        let root: URL
        let workingDirectory: URL
        let homeDirectory: URL
        let templateDirectory: URL
    }

    private enum GitInitializationError: Error {
        case failed(status: Int32)
    }
}
