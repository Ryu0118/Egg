@testable import EggKit
import FileManagerProtocol
import Foundation
import ProcessRunning
import Testing

/// The large-staging guard must measure before cloning: agent previews
/// refuse oversized staging with the escape hatches named, and the count
/// must reflect what the cloner would actually copy.
@Suite("StagingPreflight and the large-staging guard")
struct StagingPreflightTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    @Test("counts exactly the files a git-aware clone would copy, ignoring gitignored ones")
    func gitCountMatchesCloneScope() async throws {
        let root = try makeGitWorkspace(trackedFiles: ["a.txt", "sub/b.txt"])
        defer { try? fileManager.removeItem(at: root) }
        // gitignored files are not cloned, so they must not count
        try fileManager.writeText("ignored\n", at: root.appending(path: "ignored.log"))
        try fileManager.writeText("*.log\n", at: root.appending(path: ".gitignore"))

        let count = try await StagingPreflight(fileManager: fileManager)
            .countGitCloneableFiles(in: root)

        // a.txt, sub/b.txt, .gitignore — not ignored.log
        #expect(count == 3)
    }

    @Test("non-git counting stops at the cap instead of enumerating a huge tree")
    func nonGitCountIsCapped() throws {
        let root = try fileManager.makeTemporaryDirectory(prefix: "StagingPreflightTests")
        defer { try? fileManager.removeItem(at: root) }
        for index in 0 ..< 5 {
            try fileManager.writeText("x", at: root.appending(path: "f\(index).txt"))
        }

        let capped = StagingPreflight(fileManager: fileManager).countAllFiles(in: root, cap: 3)
        #expect(capped.count == 4)
        #expect(!capped.isExact)

        let exact = StagingPreflight(fileManager: fileManager).countAllFiles(in: root, cap: 100)
        #expect(exact.count == 5)
        #expect(exact.isExact)
    }

    @Test("preview refuses staging above the limit and names the escape hatches")
    func previewRefusesOversizedStaging() async throws {
        let workspace = try makePreviewWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }

        do {
            _ = try await makeRunner(workspace: workspace, stagingFileLimit: 1).preview()
            Issue.record("expected stagingTooLarge")
        } catch let error as AgentHatchTransactionRunner.Error {
            guard case let .stagingTooLarge(fileCount, limit) = error else {
                Issue.record("expected stagingTooLarge, got \(error)")
                return
            }
            #expect(fileCount > limit)
            let message = error.localizedDescription
            #expect(message.contains("--allow-large-staging"))
            #expect(message.contains("staging_root"))
            #expect(message.contains("--no-staging"))
        }
    }

    @Test("allowLargeStaging bypasses the guard and the preview succeeds")
    func allowLargeStagingBypassesGuard() async throws {
        let workspace = try makePreviewWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }

        let result = try await makeRunner(
            workspace: workspace,
            stagingFileLimit: 1,
            allowLargeStaging: true,
        ).preview()

        #expect(result.changes.contains { $0.path == "Generated.txt" })
    }

    @Test("a failed preview leaves no temp clone and no transaction shell behind")
    func failedPreviewLeavesNoDebris() async throws {
        let workspace = try makePreviewWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }
        try fileManager.createDirectory(at: workspace.homeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspace.templateDirectory, withIntermediateDirectories: true)
        try fileManager.writeText("generated\n", at: workspace.templateDirectory.appending(path: "Generated.txt"))

        // A pre_hatch step that exits nonzero fails the preview after the
        // temp clone was created — the exact window that used to leak.
        let runner = AgentHatchTransactionRunner(
            fileManager: fileManager,
            workingDirectory: workspace.workingDirectory,
            homeDirectory: workspace.homeDirectory,
            templateDirectory: workspace.templateDirectory,
            config: Config(
                name: "LeakProbe",
                description: "d",
                preHatch: [Config.LifecycleStep(run: "exit 7")],
                hatch: .init(output: "."),
            ),
            parsedMacros: [],
            sandboxDisabled: true,
        )

        await #expect(throws: (any Swift.Error).self) {
            _ = try await runner.preview()
        }

        let leakedClones = (try? fileManager.contentsOfDirectory(
            at: FileManager.default.temporaryDirectory,
            includingPropertiesForKeys: nil,
            options: [],
        ))?.filter { $0.lastPathComponent.hasPrefix("egg-agent-") && $0.lastPathComponent.contains("-leakprobe-") } ?? []
        #expect(leakedClones.isEmpty, "temp staging clone must be removed on failure: \(leakedClones)")
        #expect(
            !fileManager.exists(workspace.workingDirectory.appending(path: ".egg/transactions")) ||
                (try? fileManager.contentsOfDirectory(
                    at: workspace.workingDirectory.appending(path: ".egg/transactions"),
                    includingPropertiesForKeys: nil,
                    options: [],
                ))?.isEmpty == true,
            "no transaction shell may remain after a failed preview",
        )
    }

    @Test("previewing from a subdirectory of the repository warns; from the root it doesn't")
    func subdirectoryPreviewWarns() async throws {
        let workspace = try makePreviewWorkspace()
        defer { try? fileManager.removeItem(at: workspace.root) }
        let subdirectory = workspace.workingDirectory.appending(path: "nested/deeper")
        try fileManager.createDirectory(at: subdirectory, withIntermediateDirectories: true)

        let fromSubdirectory = try await makeRunner(
            workspace: Workspace(
                root: workspace.root,
                workingDirectory: subdirectory,
                homeDirectory: workspace.homeDirectory,
                templateDirectory: workspace.templateDirectory,
            ),
            stagingFileLimit: StagingPreflight.defaultFileLimit,
        ).preview()
        #expect(fromSubdirectory.warnings.contains { $0.code == "subdirectory_of_repository" })

        let fromRoot = try await makeRunner(
            workspace: workspace,
            stagingFileLimit: StagingPreflight.defaultFileLimit,
        ).preview()
        #expect(!fromRoot.warnings.contains { $0.code == "subdirectory_of_repository" })
    }

    // MARK: - Fixtures

    private struct Workspace {
        let root: URL
        let workingDirectory: URL
        let homeDirectory: URL
        let templateDirectory: URL
    }

    /// A git working directory holding several files (above a limit of 1)
    /// plus a trivial template to preview.
    private func makePreviewWorkspace() throws -> Workspace {
        let root = try makeGitWorkspace(trackedFiles: ["one.txt", "two.txt"], nested: true)
        return Workspace(
            root: root.deletingLastPathComponent(),
            workingDirectory: root,
            homeDirectory: root.deletingLastPathComponent().appending(path: "home"),
            templateDirectory: root.deletingLastPathComponent().appending(path: "template"),
        )
    }

    private func makeRunner(
        workspace: Workspace,
        stagingFileLimit: Int,
        allowLargeStaging: Bool = false,
    ) throws -> AgentHatchTransactionRunner {
        try fileManager.createDirectory(at: workspace.homeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspace.templateDirectory, withIntermediateDirectories: true)
        try fileManager.writeText("generated\n", at: workspace.templateDirectory.appending(path: "Generated.txt"))
        return AgentHatchTransactionRunner(
            fileManager: fileManager,
            workingDirectory: workspace.workingDirectory,
            homeDirectory: workspace.homeDirectory,
            templateDirectory: workspace.templateDirectory,
            config: Config(name: "T", description: "d", hatch: .init(output: ".")),
            parsedMacros: [],
            sandboxDisabled: true,
            allowLargeStaging: allowLargeStaging,
            stagingFileLimit: stagingFileLimit,
        )
    }

    /// A temp directory initialized as a git repository containing `trackedFiles`.
    /// With `nested`, the repository lives in a `work` subdirectory of the temp root.
    private func makeGitWorkspace(trackedFiles: [String], nested: Bool = false) throws -> URL {
        let base = try fileManager.makeTemporaryDirectory(prefix: "StagingPreflightTests")
        let root = nested ? base.appending(path: "work") : base
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for file in trackedFiles {
            let url = root.appending(path: file)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.writeText("content\n", at: url)
        }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["init", "--quiet"]
        process.currentDirectoryURL = root
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            struct GitInitFailed: Error {}
            throw GitInitFailed()
        }
        return root
    }
}
