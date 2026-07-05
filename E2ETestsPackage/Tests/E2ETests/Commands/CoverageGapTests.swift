import FileManagerProtocol
import Foundation
import Testing

/// Closes the gaps the coverage matrix surfaced: preview pathspecs,
/// install --tag, direct --staging-root, and an end-to-end lifecycle
/// fixture (step outputs, `if` conditions, hatch.exclude, built-ins)
/// that the unit suites cover only below the binary.
@Suite(.buildBinary, .serialized)
struct CoverageGapTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func json(_ text: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(object as? [String: Any])
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func makeProject() throws -> URL {
        let root = try fileManager.makeTemporaryDirectory(prefix: "cli-test-gaps")
        try runGit(["init", "-q"], in: root)
        try runGit(["commit", "--allow-empty", "-q", "-m", "init"], in: root)
        return root
    }

    private func writeTemplate(named name: String, in root: URL, config: String, files: [String: String]) throws {
        let dir = root.appending(path: ".eggs/\(name)")
        try fileManager.createDirectory(at: dir.appending(path: "files"), withIntermediateDirectories: true)
        try config.write(to: dir.appending(path: "config.yml"), atomically: true, encoding: .utf8)
        for (path, contents) in files {
            let target = dir.appending(path: "files/\(path)")
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: target, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - G2: preview --include / --exclude pathspecs

    @Test("preview --exclude drops matching paths and --include forces gitignored ones back in")
    func previewPathspecsFilterTheChangeSet() async throws {
        let runner = try await CLIRunner()
        let root = try makeProject()
        defer { try? fileManager.removeItem(at: root) }

        // The project ignores generated/, so its files normally never appear.
        try "generated/\n".write(to: root.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try runGit(["add", ".gitignore"], in: root)
        try runGit(["commit", "-q", "-m", "ignore generated"], in: root)

        try writeTemplate(named: "Filters", in: root, config: """
        name: Filters
        description: d
        hatch:
          output: .
        """, files: [
            "kept.txt": "kept\n",
            "dropped.txt": "dropped\n",
            "generated/artifact.txt": "artifact\n",
        ])

        // --exclude removes a path from the change set.
        let excluded = try await runner.run(
            "hatch", "preview", "Filters", "--exclude", "files/dropped.txt",
            workingDirectory: root,
        )
        #expect(excluded.succeeded, Comment(rawValue: excluded.stderr))
        var paths = try #require(try json(excluded.stdout)["changes"] as? [[String: Any]]).compactMap { $0["path"] as? String }
        #expect(paths.contains("files/kept.txt"))
        #expect(!paths.contains("files/dropped.txt"))
        // gitignored path is absent by default.
        #expect(!paths.contains("files/generated/artifact.txt"))
        var token = try #require(try json(excluded.stdout)["applyToken"] as? String)
        _ = try await runner.run("hatch", "discard", token, workingDirectory: root)

        // --include forces the gitignored path back into the change set.
        let included = try await runner.run(
            "hatch", "preview", "Filters", "--include", "files/generated/artifact.txt",
            workingDirectory: root,
        )
        #expect(included.succeeded, Comment(rawValue: included.stderr))
        paths = try #require(try json(included.stdout)["changes"] as? [[String: Any]]).compactMap { $0["path"] as? String }
        #expect(paths.contains("files/generated/artifact.txt"))
        token = try #require(try json(included.stdout)["applyToken"] as? String)
        _ = try await runner.run("hatch", "discard", token, workingDirectory: root)
    }

    // MARK: - G3: install --tag against a real git fixture

    @Test("install --tag checks out the tagged commit's templates")
    func installTagChecksOutTheTaggedCommit() async throws {
        let runner = try await CLIRunner()
        let root = try makeProject()
        defer { try? fileManager.removeItem(at: root) }

        // Fixture repo: v1 tag carries TaggedTpl with old content; HEAD moves on.
        let repo = root.appending(path: "fixture-repo")
        try fileManager.createDirectory(at: repo.appending(path: "TaggedTpl/files"), withIntermediateDirectories: true)
        try runGit(["init", "-q", "--initial-branch", "main"], in: repo)
        try "name: TaggedTpl\ndescription: tagged\nhatch:\n  output: .\n"
            .write(to: repo.appending(path: "TaggedTpl/config.yml"), atomically: true, encoding: .utf8)
        try "v1 content\n".write(to: repo.appending(path: "TaggedTpl/files/marker.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "-A"], in: repo)
        try runGit(["commit", "-q", "-m", "v1"], in: repo)
        try runGit(["tag", "v1.0.0"], in: repo)
        try "v2 content\n".write(to: repo.appending(path: "TaggedTpl/files/marker.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "-A"], in: repo)
        try runGit(["commit", "-q", "-m", "v2"], in: repo)

        // A plain local path cannot honor a ref — the --json path must refuse
        // it just like the interactive validator does, never silently install
        // HEAD while the caller believes they pinned a version.
        let refused = try await runner.run(
            "template", "install", repo.path(percentEncoded: false), "--tag", "v1.0.0", "--json",
            workingDirectory: root,
        )
        #expect(!refused.succeeded)
        #expect(refused.stderr.contains("cannot be used with the local path"))

        // A file:// git URL honors the tag: v1 content, not HEAD's v2.
        let result = try await runner.run(
            "template", "install", "file://" + repo.path(percentEncoded: false), "--tag", "v1.0.0", "--json",
            workingDirectory: root,
        )
        #expect(result.succeeded, Comment(rawValue: result.stderr))
        #expect(try json(result.stdout)["installed"] as? [String] == ["TaggedTpl"])

        let marker = root.appending(path: ".eggs/TaggedTpl/files/marker.txt")
        let contents = try String(contentsOf: marker, encoding: .utf8)
        #expect(contents == "v1 content\n", "tag checkout must carry v1, not HEAD's v2")
    }

    // MARK: - G4: hatch direct --staging-root

    @Test("direct hatch --staging-root clones and applies into the named directory, not the cwd")
    func directHatchStagingRootTargetsTheNamedDirectory() async throws {
        let runner = try await CLIRunner()
        let root = try makeProject()
        defer { try? fileManager.removeItem(at: root) }
        try writeTemplate(named: "Rooted", in: root, config: """
        name: Rooted
        description: d
        hatch:
          output: .
        """, files: ["out.txt": "content\n"])
        // --staging-root names the directory the changes are staged for and
        // applied back into — a second working directory, not a temp location.
        let target = root.appending(path: "target-dir")
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)

        let result = try await runner.run(
            "hatch", "direct", "Rooted",
            "--apply-changes", "--override-conflicts",
            "--staging-root", target.path(percentEncoded: false),
            "--picker", "text",
            workingDirectory: root,
        )
        #expect(result.succeeded, Comment(rawValue: result.stderr))
        #expect(exists(target.appending(path: "files/out.txt")), "changes must land in the staging-root target")
        #expect(!exists(root.appending(path: "files/out.txt")), "the cwd must stay untouched")
    }

    // MARK: - G5: lifecycle features through the real binary

    @Test("a template using step outputs, if conditions, hatch.exclude, and built-ins hatches end to end")
    func lifecycleKitchenSinkHatchesEndToEnd() async throws {
        let runner = try await CLIRunner()
        let root = try makeProject()
        defer { try? fileManager.removeItem(at: root) }

        try writeTemplate(named: "Sink", in: root, config: """
        name: Sink
        description: kitchen sink
        macros:
          - name: ___ENABLE_DOCS___
            description: docs flag
            type: boolean
          - name: ___FLAVOR___
            description: flavor
            type: choice
            choices: [vanilla, matcha]
        pre_hatch:
          - id: setup
            run: |
              echo "stamp=stamped-by-pre-hatch"
          - id: skipped
            if: ___ENABLE_DOCS___ === true
            run: |
              echo "never=ran"
        hatch:
          output: .
          exclude:
            - "files/always-excluded.txt"
            - if: ___FLAVOR___ === 'matcha'
              paths: ["files/matcha-only-excluded.txt"]
        post_hatch:
          - run: echo "post ran with ${{ pre_hatch.setup.outputs.stamp }}"
        """, files: [
            "stamped.txt": "value=${{ pre_hatch.setup.outputs.stamp }} year=___YEAR___\n",
            "always-excluded.txt": "never lands\n",
            "matcha-only-excluded.txt": "flavor gated\n",
        ])

        // vanilla + docs off: conditional step skipped, conditional exclude inactive.
        let preview = try await runner.run(
            "hatch", "preview", "Sink", "--no-enable-docs", "--flavor", "vanilla",
            workingDirectory: root,
        )
        #expect(preview.succeeded, Comment(rawValue: preview.stderr))
        let paths = try #require(try json(preview.stdout)["changes"] as? [[String: Any]]).compactMap { $0["path"] as? String }
        #expect(paths.contains("files/stamped.txt"))
        #expect(!paths.contains("files/always-excluded.txt"), "unconditional exclude must drop the file")
        #expect(paths.contains("files/matcha-only-excluded.txt"), "vanilla must not trigger the matcha-gated exclude")

        let token = try #require(try json(preview.stdout)["applyToken"] as? String)
        let applied = try await runner.run("hatch", "apply", token, workingDirectory: root)
        #expect(applied.succeeded, Comment(rawValue: applied.stderr))

        let stamped = try String(contentsOf: root.appending(path: "files/stamped.txt"), encoding: .utf8)
        #expect(stamped.contains("value=stamped-by-pre-hatch"), "step output must resolve in file content")
        let year = Calendar.current.component(.year, from: Date())
        #expect(stamped.contains("year=\(year)"), "___YEAR___ built-in must resolve")

        _ = try await runner.run("hatch", "discard", token, "--force", workingDirectory: root)
    }
}
