@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct ManifestLoaderTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    // MARK: - Decoding valid manifests

    @Test("decodes every entry kind, expanding GitHub shorthand")
    func decodesAllEntryKinds() throws {
        let manifest = try load("""
        templates:
          - url: Ryu0118/swift-egg-templates
            from: "0.3.0"
            only: [SwiftCLI, SwiftLibrary]
          - url: git@github.com:owner/private-templates.git
            branch: main
            exclude: [Experimental]
          - url: https://github.com/owner/repo.git
            exact: "1.2.0"
          - url: https://github.com/owner/repo2.git
            revision: 6c0f1a2b9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a
          - url: ./local-templates
        """)

        #expect(manifest.templates.count == 5)

        let shorthand = manifest.templates[0]
        #expect(shorthand.declaredURL == "Ryu0118/swift-egg-templates")
        guard case let .git(url, requirement) = shorthand.source else {
            Issue.record("expected git source")
            return
        }
        #expect(url.original == "https://github.com/Ryu0118/swift-egg-templates.git")
        #expect(requirement == .from(SemanticVersion(major: 0, minor: 3, patch: 0)))
        #expect(shorthand.filter == .include(["SwiftCLI", "SwiftLibrary"]))
        #expect(shorthand.source.lockKey == "https://github.com/Ryu0118/swift-egg-templates.git")

        guard case let .git(_, branchRequirement) = manifest.templates[1].source else {
            Issue.record("expected git source")
            return
        }
        #expect(branchRequirement == .branch("main"))
        #expect(manifest.templates[1].filter == .exclude(["Experimental"]))

        guard case let .git(_, exactRequirement) = manifest.templates[2].source else {
            Issue.record("expected git source")
            return
        }
        #expect(exactRequirement == .exact(SemanticVersion(major: 1, minor: 2, patch: 0)))

        guard case let .git(_, revisionRequirement) = manifest.templates[3].source else {
            Issue.record("expected git source")
            return
        }
        #expect(revisionRequirement == .revision("6c0f1a2b9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a"))

        let local = manifest.templates[4]
        #expect(local.source == .local(path: "./local-templates"))
        #expect(local.source.lockKey == nil)
        #expect(local.filter == TemplateFilter.none)
    }

    @Test("empty templates list and missing key are both valid no-ops")
    func emptyManifests() throws {
        #expect(try load("templates: []").templates.isEmpty)
        #expect(try load("# just a comment").templates.isEmpty)
    }

    @Test("relative and absolute paths are locals, not shorthand", arguments: [
        "./templates/foo",
        "../shared-templates",
        "/absolute/path/templates",
        "~/my-templates",
    ])
    func localPathDisambiguation(_ path: String) throws {
        let manifest = try load("""
        templates:
          - url: \(path)
        """)
        #expect(manifest.templates.first?.source == .local(path: path))
    }

    @Test("a bare two-segment name is shorthand, not a local path")
    func shorthandDisambiguation() throws {
        let manifest = try load("""
        templates:
          - url: owner/repo
            from: "1.0.0"
        """)
        guard case let .git(url, _) = manifest.templates[0].source else {
            Issue.record("expected git source")
            return
        }
        #expect(url.original == "https://github.com/owner/repo.git")
    }

    // MARK: - Invalid entries

    @Test("rejects invalid entries with a reason naming the entry", arguments: InvalidEntryTestCase.allCases)
    func invalidEntries(_ testCase: InvalidEntryTestCase) throws {
        let root = try fileManager.makeTemporaryDirectory(prefix: "ManifestLoaderTests")
        defer { try? fileManager.removeItem(at: root) }
        let manifestPath = root.appending(path: "egg.yml")
        try fileManager.writeText(testCase.yaml, at: manifestPath)

        #expect {
            try ManifestLoader(fileManager: fileManager).load(manifestPath: manifestPath)
        } throws: { error in
            guard case let ManifestLoaderError.invalidEntry(url, reason) = error else {
                return false
            }
            return url == testCase.expectedURL && reason.contains(testCase.expectedReasonFragment)
        }
    }

    struct InvalidEntryTestCase: CustomTestStringConvertible {
        let description: String
        let yaml: String
        let expectedURL: String
        let expectedReasonFragment: String

        static let allCases: [InvalidEntryTestCase] = [
            InvalidEntryTestCase(
                description: "two version keys on a git entry",
                yaml: """
                templates:
                  - url: owner/repo
                    from: "1.0.0"
                    branch: main
                """,
                expectedURL: "owner/repo",
                expectedReasonFragment: "exactly one of 'from', 'exact', 'branch', 'revision' (found 2)",
            ),
            InvalidEntryTestCase(
                description: "no version key on a git entry",
                yaml: """
                templates:
                  - url: https://github.com/owner/repo.git
                """,
                expectedURL: "https://github.com/owner/repo.git",
                expectedReasonFragment: "(found 0)",
            ),
            InvalidEntryTestCase(
                description: "version key on a local path",
                yaml: """
                templates:
                  - url: ./local-templates
                    from: "1.0.0"
                """,
                expectedURL: "./local-templates",
                expectedReasonFragment: "version specifiers are not allowed for local paths",
            ),
            InvalidEntryTestCase(
                description: "only and exclude together",
                yaml: """
                templates:
                  - url: owner/repo
                    from: "1.0.0"
                    only: [A]
                    exclude: [B]
                """,
                expectedURL: "owner/repo",
                expectedReasonFragment: "'only' and 'exclude' are mutually exclusive",
            ),
            InvalidEntryTestCase(
                description: "unparseable semver in from",
                yaml: """
                templates:
                  - url: owner/repo
                    from: "1.0"
                """,
                expectedURL: "owner/repo",
                expectedReasonFragment: "invalid semantic version '1.0' for 'from'",
            ),
            InvalidEntryTestCase(
                description: "v-prefixed semver in exact is rejected",
                yaml: """
                templates:
                  - url: owner/repo
                    exact: "v1.0.0"
                """,
                expectedURL: "owner/repo",
                expectedReasonFragment: "invalid semantic version 'v1.0.0' for 'exact'",
            ),
            InvalidEntryTestCase(
                description: "empty branch",
                yaml: """
                templates:
                  - url: owner/repo
                    branch: ""
                """,
                expectedURL: "owner/repo",
                expectedReasonFragment: "'branch' must not be empty",
            ),
            InvalidEntryTestCase(
                description: "empty url",
                yaml: """
                templates:
                  - url: ""
                """,
                expectedURL: "",
                expectedReasonFragment: "'url' must not be empty",
            ),
        ]

        var testDescription: String {
            description
        }
    }

    // MARK: - Loader errors

    @Test("missing manifest file throws manifestNotFound")
    func missingManifest() throws {
        let root = try fileManager.makeTemporaryDirectory(prefix: "ManifestLoaderTests")
        defer { try? fileManager.removeItem(at: root) }
        let manifestPath = root.appending(path: "egg.yml")

        #expect {
            try ManifestLoader(fileManager: fileManager).load(manifestPath: manifestPath)
        } throws: { error in
            guard case ManifestLoaderError.manifestNotFound = error else {
                return false
            }
            return true
        }
    }

    @Test("malformed YAML throws decodingFailed")
    func malformedYAML() throws {
        let root = try fileManager.makeTemporaryDirectory(prefix: "ManifestLoaderTests")
        defer { try? fileManager.removeItem(at: root) }
        let manifestPath = root.appending(path: "egg.yml")
        try fileManager.writeText("templates: {not: [a, list", at: manifestPath)

        #expect {
            try ManifestLoader(fileManager: fileManager).load(manifestPath: manifestPath)
        } throws: { error in
            guard case ManifestLoaderError.decodingFailed = error else {
                return false
            }
            return true
        }
    }

    // MARK: - Helpers

    private func load(_ yaml: String) throws -> Manifest {
        let root = try fileManager.makeTemporaryDirectory(prefix: "ManifestLoaderTests")
        defer { try? fileManager.removeItem(at: root) }
        let manifestPath = root.appending(path: "egg.yml")
        try fileManager.writeText(yaml, at: manifestPath)
        return try ManifestLoader(fileManager: fileManager).load(manifestPath: manifestPath)
    }
}

struct ManifestLocatorTests {
    @Test("global manifest honors XDG_CONFIG_HOME")
    func xdgOverride() {
        let locator = ManifestLocator(environment: ["XDG_CONFIG_HOME": "/custom/xdg"])
        let url = locator.globalManifestURL(homeDirectory: URL(filePath: "/Users/tester", directoryHint: .isDirectory))
        #expect(url.path(percentEncoded: false) == "/custom/xdg/egg/egg.yml")
    }

    @Test("global manifest falls back to ~/.config, ignoring empty XDG_CONFIG_HOME")
    func xdgFallback() {
        let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)
        for environment in [[String: String](), ["XDG_CONFIG_HOME": ""]] {
            let url = ManifestLocator(environment: environment).globalManifestURL(homeDirectory: home)
            #expect(url.path(percentEncoded: false) == "/Users/tester/.config/egg/egg.yml")
        }
    }

    @Test("project manifest and lockfile sit at the project root")
    func projectPaths() {
        let locator = ManifestLocator(environment: [:])
        let projectDirectory = URL(filePath: "/repo", directoryHint: .isDirectory)
        let manifestURL = locator.projectManifestURL(projectDirectory: projectDirectory)
        #expect(manifestURL.path(percentEncoded: false) == "/repo/egg.yml")
        let lockURL = ManifestLocator.lockfileURL(forManifestAt: manifestURL)
        #expect(lockURL.path(percentEncoded: false) == "/repo/egg-lock.yml")
    }
}
