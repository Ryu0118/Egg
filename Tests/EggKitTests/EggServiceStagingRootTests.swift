@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

/// The MCP `egg_hatch_preview` tool declares `staging_root`, which used to
/// drop the parameter on the floor — the service signature swallowed it with
/// `stagingRoot _:`. These prove preview honors it with the direct flow's
/// semantics: the staging clones from and applies back into that directory,
/// and the transaction records live under it.
@Suite("EggService.previewHatchTemplate honors stagingRoot")
struct EggServiceStagingRootTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    @Test("preview stages the stagingRoot directory and apply lands the file there")
    func previewAndApplyTargetTheStagingRoot() async throws {
        let root = try fileManager.makeTemporaryDirectory(prefix: "EggServiceStagingRootTests")
        defer { try? fileManager.removeItem(at: root) }
        let project = root.appending(path: "project")
        let staging = root.appending(path: "staging-target")
        let home = root.appending(path: "home")
        let template = project.appending(path: ".eggs/RootedTemplate")
        try fileManager.createDirectory(at: template, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.writeText(
            """
            name: RootedTemplate
            description: d
            hatch:
              output: .
            """,
            at: template.appending(path: "config.yml"),
        )
        try fileManager.writeText("hello\n", at: template.appending(path: "Rooted.txt"))
        try initializeGitRepository(at: project)
        try initializeGitRepository(at: staging)

        let service = EggService(
            fileManager: fileManager,
            workingDirectory: project,
            projectDirectory: project,
            homeDirectory: home,
        )

        let preview = try await service.previewHatchTemplate(
            templateName: "RootedTemplate",
            macros: [:],
            stagingRoot: staging,
        )

        #expect(preview.changes.contains { $0.path == "Rooted.txt" })
        #expect(
            fileManager.exists(staging.appending(path: ".egg/transactions")),
            "transaction records must live under the staging root, not the working directory",
        )
        #expect(!fileManager.exists(project.appending(path: ".egg")))

        let applied = try await service.applyHatchTransaction(
            applyToken: preview.applyToken,
            workingDirectory: staging,
        )

        #expect(applied.status == "applied")
        #expect(fileManager.exists(staging.appending(path: "Rooted.txt")))
        #expect(!fileManager.exists(project.appending(path: "Rooted.txt")))
    }

    private func initializeGitRepository(at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["init", "--quiet"]
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            struct GitInitFailed: Error {}
            throw GitInitFailed()
        }
    }
}
