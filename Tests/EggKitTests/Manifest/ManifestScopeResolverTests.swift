@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct ManifestScopeResolverTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    @Test("default selection returns every scope whose manifest exists")
    func allSelection() throws {
        let env = try TestDirectories(fileManager: fileManager)
        defer { env.tearDown() }
        try env.writeGlobalManifest()
        try env.writeProjectManifest()

        let scopes = try resolve(.all, env: env)

        #expect(scopes.map(\.kind) == [.global, .project])
        #expect(scopes[0].manifestURL == env.globalManifestURL)
        #expect(scopes[0].lockfileURL == env.globalManifestURL.deletingLastPathComponent().appending(path: "egg-lock.yml"))
        #expect(scopes[1].manifestURL == env.projectManifestURL)
    }

    @Test("default selection tolerates a single existing scope")
    func allSelectionSingleScope() throws {
        let env = try TestDirectories(fileManager: fileManager)
        defer { env.tearDown() }
        try env.writeProjectManifest()

        let scopes = try resolve(.all, env: env)

        #expect(scopes.map(\.kind) == [.project])
    }

    @Test("default selection with no manifest anywhere lists both searched paths")
    func allSelectionNoManifest() throws {
        let env = try TestDirectories(fileManager: fileManager)
        defer { env.tearDown() }

        #expect(throws: ManifestScopeError.noManifestFound(searchedPaths: [
            env.globalManifestURL.path(percentEncoded: false),
            env.projectManifestURL.path(percentEncoded: false),
        ])) {
            try resolve(.all, env: env)
        }
    }

    @Test("explicitly requested scopes must exist", arguments: [
        ManifestScopeSelection.global,
        ManifestScopeSelection.project,
    ])
    func explicitScopeMissing(_ selection: ManifestScopeSelection) throws {
        let env = try TestDirectories(fileManager: fileManager)
        defer { env.tearDown() }
        let expectedScope = selection == .global ? "global" : "project"

        let error = try #require(throws: ManifestScopeError.self) {
            try resolve(selection, env: env)
        }
        guard case let .scopeManifestNotFound(scope, _) = error else {
            Issue.record("expected .scopeManifestNotFound, got \(error)")
            return
        }
        #expect(scope == expectedScope)
    }

    @Test("global scope honors XDG_CONFIG_HOME")
    func xdgOverride() throws {
        let env = try TestDirectories(fileManager: fileManager)
        defer { env.tearDown() }
        let xdgDirectory = env.root.appending(path: "xdg")
        let manifestURL = xdgDirectory.appending(path: "egg/egg.yml")
        try fileManager.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try fileManager.writeText("templates: []", at: manifestURL)

        let scopes = try ManifestScopeResolver.resolve(
            selection: .global,
            projectDirectory: env.projectDirectory,
            homeDirectory: env.homeDirectory,
            fileManager: fileManager,
            environment: ["XDG_CONFIG_HOME": xdgDirectory.path(percentEncoded: false)],
        )

        #expect(scopes.first?.manifestURL.path(percentEncoded: false) == manifestURL.path(percentEncoded: false))
    }

    // MARK: - Helpers

    private func resolve(
        _ selection: ManifestScopeSelection,
        env: TestDirectories,
    ) throws -> [TemplateSyncRunner.Scope] {
        try ManifestScopeResolver.resolve(
            selection: selection,
            projectDirectory: env.projectDirectory,
            homeDirectory: env.homeDirectory,
            fileManager: fileManager,
            environment: [:],
        )
    }

    private struct TestDirectories {
        let root: URL
        let homeDirectory: URL
        let projectDirectory: URL
        let fileManager: any FileManagerProtocol

        var globalManifestURL: URL {
            homeDirectory.appending(path: ".config/egg/egg.yml")
        }

        var projectManifestURL: URL {
            projectDirectory.appending(path: "egg.yml")
        }

        init(fileManager: any FileManagerProtocol) throws {
            self.fileManager = fileManager
            root = try fileManager.makeTemporaryDirectory(prefix: "ManifestScopeResolverTests")
            homeDirectory = root.appending(path: "home")
            projectDirectory = root.appending(path: "project")
            for directory in [homeDirectory, projectDirectory] {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }

        func tearDown() {
            try? fileManager.removeItem(at: root)
        }

        func writeGlobalManifest() throws {
            try fileManager.createDirectory(
                at: globalManifestURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try fileManager.writeText("templates: []", at: globalManifestURL)
        }

        func writeProjectManifest() throws {
            try fileManager.writeText("templates: []", at: projectManifestURL)
        }
    }
}

struct EggServiceManifestTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    @Test("syncTemplates routes through the runner for the project scope")
    func syncProjectScope() async throws {
        let root = try fileManager.makeTemporaryDirectory(prefix: "EggServiceManifestTests")
        defer { try? fileManager.removeItem(at: root) }
        let home = root.appending(path: "home")
        let project = root.appending(path: "project")
        let localTemplates = project.appending(path: "local-templates/MyTemplate")
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: localTemplates, withIntermediateDirectories: true)
        try fileManager.writeText(
            """
            name: "MyTemplate"
            description: "A test template"
            hatch:
              output: "./output"
            """,
            at: localTemplates.appending(path: "config.yml"),
        )
        try fileManager.writeText(
            """
            templates:
              - url: ./local-templates
            """,
            at: project.appending(path: "egg.yml"),
        )

        let service = EggService(
            fileManager: fileManager,
            workingDirectory: project,
            projectDirectory: project,
            homeDirectory: home,
        )

        let result = try await service.syncTemplates(scope: "project")

        #expect(!result.hasFailures)
        #expect(result.scopes.first?.entries.first?.installed == ["MyTemplate"])
        #expect(fileManager.exists(project.appending(path: ".eggs/MyTemplate/config.yml")))
    }

    @Test("an unknown scope string is rejected")
    func invalidScope() async throws {
        let service = EggService()

        await #expect(throws: EggServiceError.self) {
            try await service.syncTemplates(scope: "elsewhere")
        }
    }
}
