import FileManagerProtocol
import Foundation
import Testing

/// End-to-end coverage of the multi-step transaction flow through the real
/// binary: preview → apply → rollback → re-apply → discard → transactions.
@Suite(.buildBinary, .serialized)
struct TransactionFlowTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    /// Creates a temp git repository containing a minimal project template.
    private func makeProjectWithTemplate() throws -> URL {
        let root = try fileManager.makeTemporaryDirectory(prefix: "cli-test-transaction")
        try runGit(["init", "-q"], in: root)
        try runGit(["commit", "--allow-empty", "-q", "-m", "init"], in: root)
        let templateDir = root.appending(path: ".eggs/Demo")
        try fileManager.createDirectory(at: templateDir.appending(path: "files"), withIntermediateDirectories: true)
        try """
        name: Demo
        description: demo
        hatch:
          output: .
        """.write(to: templateDir.appending(path: "config.yml"), atomically: true, encoding: .utf8)
        try "hello\n".write(to: templateDir.appending(path: "files/hello.txt"), atomically: true, encoding: .utf8)
        return root
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func json(_ text: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(object as? [String: Any])
    }

    @Test("Drives a transaction through preview, apply, rollback, re-apply, and discard")
    func drivesATransactionThroughItsFullLifecycle() async throws {
        let runner = try await CLIRunner()
        let root = try makeProjectWithTemplate()
        defer { try? fileManager.removeItem(at: root) }
        let generatedFile = root.appending(path: "files/hello.txt")

        // Preview: nothing written yet, an applyToken is returned.
        let preview = try await runner.run("hatch", "preview", "Demo", workingDirectory: root)
        #expect(preview.succeeded, Comment(rawValue: preview.stderr))
        let token = try #require(try json(preview.stdout)["applyToken"] as? String)
        #expect(!exists(generatedFile))

        // Listing shows the preview without a rollback bundle.
        let listed = try await runner.run("hatch", "transactions", workingDirectory: root)
        let entries = try #require(try json(listed.stdout)["transactions"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries[0]["status"] as? String == "preview")
        #expect(entries[0]["hasRollbackBundle"] as? Bool == false)

        // Apply materializes the file; rollbackId equals the applyToken.
        let applied = try await runner.run("hatch", "apply", token, workingDirectory: root)
        #expect(applied.succeeded, Comment(rawValue: applied.stderr))
        #expect(try json(applied.stdout)["rollbackId"] as? String == token)
        #expect(exists(generatedFile))

        // Rollback restores the pre-apply state and re-enables apply.
        let rolledBack = try await runner.run("hatch", "rollback", token, workingDirectory: root)
        #expect(rolledBack.succeeded, Comment(rawValue: rolledBack.stderr))
        #expect(!exists(generatedFile))

        // Re-apply succeeds and carries the reapplied warning.
        let reapplied = try await runner.run("hatch", "apply", token, workingDirectory: root)
        #expect(reapplied.succeeded, Comment(rawValue: reapplied.stderr))
        let warnings = try #require(try json(reapplied.stdout)["warnings"] as? [[String: Any]])
        #expect(warnings.contains { $0["code"] as? String == "reapplied_after_rollback" })
        #expect(exists(generatedFile))

        // Discarding an applied transaction needs --force, then deletes the
        // records as a pair while leaving the applied files alone.
        let refused = try await runner.run("hatch", "discard", token, workingDirectory: root)
        #expect(!refused.succeeded)
        #expect(refused.stderr.contains("--force"))

        let discarded = try await runner.run("hatch", "discard", token, "--force", workingDirectory: root)
        #expect(discarded.succeeded, Comment(rawValue: discarded.stderr))
        #expect(exists(generatedFile))
        #expect(!exists(root.appending(path: ".egg/transactions/\(token)")))
        #expect(!exists(root.appending(path: ".egg/rollback/\(token)")))

        let after = try await runner.run("hatch", "transactions", workingDirectory: root)
        let remaining = try #require(try json(after.stdout)["transactions"] as? [[String: Any]])
        #expect(remaining.isEmpty)
    }

    @Test("Fails fast with guidance instead of prompting when stdin is not a TTY")
    func failsFastInsteadOfPromptingWithoutATTY() async throws {
        let runner = try await CLIRunner()
        let root = try makeProjectWithTemplate()
        defer { try? fileManager.removeItem(at: root) }

        // Bare `egg hatch` would open the interactive template picker.
        let hatch = try await runner.run("hatch", workingDirectory: root)
        #expect(!hatch.succeeded)
        #expect(hatch.stderr.contains("stdin is not a TTY"))
        #expect(hatch.stderr.contains("egg hatch preview"))

        // `egg template create` with no arguments would prompt for a name.
        let create = try await runner.run("template", "create", workingDirectory: root)
        #expect(!create.succeeded)
        #expect(create.stderr.contains("stdin is not a TTY"))
    }

    @Test("template subcommands emit parseable JSON with --json")
    func templateSubcommandsEmitParseableJSONWithJSONFlag() async throws {
        let runner = try await CLIRunner()
        let root = try makeProjectWithTemplate()
        defer { try? fileManager.removeItem(at: root) }

        // list --json includes the project-local template.
        let list = try await runner.run("template", "list", "--json", workingDirectory: root)
        #expect(list.succeeded, Comment(rawValue: list.stderr))
        let templates = try #require(try json(list.stdout)["templates"] as? [[String: Any]])
        #expect(templates.contains { $0["name"] as? String == "Demo" })

        // detail --json returns structured macros and agent usage.
        let detail = try await runner.run("template", "detail", "Demo", "--json", workingDirectory: root)
        #expect(detail.succeeded, Comment(rawValue: detail.stderr))
        #expect(try json(detail.stdout)["agentUsage"] != nil)

        // detail --json without a name is a validation error, not a prompt.
        let missing = try await runner.run("template", "detail", "--json", workingDirectory: root)
        #expect(!missing.succeeded)
        #expect(missing.stderr.contains("requires a template name"))

        // create/validate/delete round-trip through JSON.
        let created = try await runner.run(
            "template", "create", "--name", "JsonTpl", "--description", "t", "--location", "project", "--json",
            workingDirectory: root,
        )
        #expect(created.succeeded, Comment(rawValue: created.stderr))
        #expect(try json(created.stdout)["name"] as? String == "JsonTpl")

        let validated = try await runner.run(
            "template", "validate", root.appending(path: ".eggs/JsonTpl").path(percentEncoded: false), "--json",
            workingDirectory: root,
        )
        #expect(validated.succeeded, Comment(rawValue: validated.stderr))
        #expect(try json(validated.stdout)["isValid"] as? Bool == true)

        let deleted = try await runner.run("template", "delete", "JsonTpl", "--json", workingDirectory: root)
        #expect(deleted.succeeded, Comment(rawValue: deleted.stderr))
        #expect(try json(deleted.stdout)["name"] as? String == "JsonTpl")
    }
}
