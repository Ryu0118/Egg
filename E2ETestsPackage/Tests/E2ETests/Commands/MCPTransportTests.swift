import FileManagerProtocol
import Foundation
import Testing

/// Exercises the MCP tools through the real stdio transport — the frontend
/// the unit suites cover only at the service layer.
@Suite(.buildBinary, .serialized)
struct MCPTransportTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
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

    private func makeProject(template: (name: String, config: String, files: [String: String])? = nil) throws -> URL {
        let root = try fileManager.makeTemporaryDirectory(prefix: "mcp-e2e")
        try runGit(["init", "-q"], in: root)
        try runGit(["commit", "--allow-empty", "-q", "-m", "init"], in: root)
        if let template {
            let dir = root.appending(path: ".eggs/\(template.name)")
            try fileManager.createDirectory(at: dir.appending(path: "files"), withIntermediateDirectories: true)
            try template.config.write(to: dir.appending(path: "config.yml"), atomically: true, encoding: .utf8)
            for (path, contents) in template.files {
                let target = dir.appending(path: "files/\(path)")
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try contents.write(to: target, atomically: true, encoding: .utf8)
            }
        }
        return root
    }

    private var demoTemplate: (name: String, config: String, files: [String: String]) {
        (
            name: "Demo",
            config: "name: Demo\ndescription: d\nhatch:\n  output: .\n",
            files: ["hello.txt": "hello\n"],
        )
    }

    @Test("tools/list declares every tool the registry can execute")
    func toolsListDeclaresEveryTool() async throws {
        let mcp = try await MCPRunner()
        let response = try mcp.request(method: "tools/list", params: [:])
        let result = try #require(response["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })

        let expected: Set = [
            "egg_template_list", "egg_template_detail", "egg_template_create",
            "egg_template_delete", "egg_template_duplicate", "egg_template_move",
            "egg_template_validate", "egg_template_install",
            "egg_hatch", "egg_hatch_preview", "egg_hatch_apply",
            "egg_hatch_rollback", "egg_hatch_discard", "egg_hatch_transactions",
        ]
        #expect(names == expected)
    }

    @Test("the transaction flow works end to end over the transport, with force gates intact")
    func transactionFlowWorksOverTheTransport() async throws {
        let root = try makeProject(template: demoTemplate)
        defer { try? fileManager.removeItem(at: root) }
        let cwd = root.path(percentEncoded: false)
        let mcp = try await MCPRunner()

        // Preview: token returned, nothing written.
        let preview = try mcp.callToolJSON("egg_hatch_preview", arguments: [
            "template_name": "Demo",
            "output_directory": cwd,
            "project_directory": cwd,
        ])
        let token = try #require(preview["applyToken"] as? String)
        #expect(!exists(root.appending(path: "files/hello.txt")))

        // Apply materializes the file.
        let applied = try mcp.callToolJSON("egg_hatch_apply", arguments: [
            "apply_token": token, "working_directory": cwd,
        ])
        #expect(applied["status"] as? String == "applied")
        #expect(exists(root.appending(path: "files/hello.txt")))

        // Discard without force is refused with isError, not a protocol crash.
        let refused = try mcp.callTool("egg_hatch_discard", arguments: [
            "apply_token": token, "working_directory": cwd,
        ])
        #expect(refused.isError)
        #expect(refused.text.contains("force"))

        // Rollback restores, transactions reports rolledBack, forced discard cleans up.
        let rolledBack = try mcp.callToolJSON("egg_hatch_rollback", arguments: [
            "rollback_id": token, "working_directory": cwd,
        ])
        #expect(rolledBack["status"] as? String == "rolledBack")
        #expect(!exists(root.appending(path: "files/hello.txt")))

        let listed = try mcp.callToolJSON("egg_hatch_transactions", arguments: [
            "working_directory": cwd,
        ])
        let entries = try #require(listed["transactions"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries[0]["status"] as? String == "rolledBack")

        let discarded = try mcp.callToolJSON("egg_hatch_discard", arguments: [
            "apply_token": token, "working_directory": cwd, "force": true,
        ])
        #expect(discarded["status"] as? String == "discarded")
        #expect(!exists(root.appending(path: ".egg/transactions/\(token)")))
        #expect(!exists(root.appending(path: ".egg/rollback/\(token)")))
    }

    @Test("sandbox consent is enforced over the transport and satisfied by allowed_write_paths")
    func sandboxConsentIsEnforcedOverTheTransport() async throws {
        let root = try makeProject()
        defer { try? fileManager.removeItem(at: root) }
        let cwd = root.path(percentEncoded: false)
        let external = root.appending(path: "external-consented")
        try fileManager.createDirectory(at: external, withIntermediateDirectories: true)
        let externalPath = external.path(percentEncoded: false)

        let dir = root.appending(path: ".eggs/NeedsConsent")
        try fileManager.createDirectory(at: dir.appending(path: "files"), withIntermediateDirectories: true)
        try """
        name: NeedsConsent
        description: d
        sandbox:
          allowed_paths:
            - \(externalPath)
        post_hatch:
          - run: echo consented > \(externalPath)/proof.txt
        hatch:
          output: .
        """.write(to: dir.appending(path: "config.yml"), atomically: true, encoding: .utf8)
        try "x\n".write(to: dir.appending(path: "files/x.txt"), atomically: true, encoding: .utf8)

        let mcp = try await MCPRunner()

        // No consent → fail fast, naming the declared path, before any script runs.
        let refused = try mcp.callTool("egg_hatch_preview", arguments: [
            "template_name": "NeedsConsent",
            "output_directory": cwd,
            "project_directory": cwd,
        ])
        #expect(refused.isError)
        #expect(refused.text.contains("SANDBOX EXTENDED WRITE ACCESS REQUIRED"))
        // The message lists the symlink-resolved path (/private/var/...), so
        // match on the unique directory name rather than the literal prefix.
        #expect(refused.text.contains("external-consented"))
        #expect(!exists(external.appending(path: "proof.txt")), "nothing may run before consent")

        // disable_sandbox without user confirmation is refused too.
        let unconfirmed = try mcp.callTool("egg_hatch_preview", arguments: [
            "template_name": "NeedsConsent",
            "output_directory": cwd,
            "project_directory": cwd,
            "disable_sandbox": true,
        ])
        #expect(unconfirmed.isError)

        // Consenting to the declared path lets the script write there.
        let granted = try mcp.callToolJSON("egg_hatch_preview", arguments: [
            "template_name": "NeedsConsent",
            "output_directory": cwd,
            "project_directory": cwd,
            "allowed_write_paths": [externalPath],
        ])
        #expect(exists(external.appending(path: "proof.txt")), "consented external write happens at preview time")
        let token = try #require(granted["applyToken"] as? String)
        _ = try mcp.callToolJSON("egg_hatch_discard", arguments: [
            "apply_token": token, "working_directory": cwd,
        ])
    }

    @Test("the legacy egg_hatch tool previews by default and writes only with apply_changes")
    func legacyHatchToolPreviewsByDefault() async throws {
        let root = try makeProject(template: demoTemplate)
        defer { try? fileManager.removeItem(at: root) }
        let cwd = root.path(percentEncoded: false)
        let mcp = try await MCPRunner()

        // Default: no writes to the working directory.
        let previewed = try mcp.callTool("egg_hatch", arguments: [
            "template_name": "Demo",
            "output_directory": cwd,
            "project_directory": cwd,
        ])
        #expect(!previewed.isError, Comment(rawValue: previewed.text))
        #expect(!exists(root.appending(path: "files/hello.txt")))

        // apply_changes: true materializes the files.
        let applied = try mcp.callTool("egg_hatch", arguments: [
            "template_name": "Demo",
            "output_directory": cwd,
            "project_directory": cwd,
            "apply_changes": true,
        ])
        #expect(!applied.isError, Comment(rawValue: applied.text))
        #expect(exists(root.appending(path: "files/hello.txt")))
    }

    @Test("template list and detail answer over the transport with structured payloads")
    func templateListAndDetailAnswerOverTheTransport() async throws {
        let root = try makeProject(template: demoTemplate)
        defer { try? fileManager.removeItem(at: root) }
        let cwd = root.path(percentEncoded: false)
        let mcp = try await MCPRunner()

        let list = try mcp.callToolJSON("egg_template_list", arguments: [
            "project_directory": cwd,
        ])
        let templates = try #require(list["templates"] as? [[String: Any]])
        #expect(templates.contains { $0["name"] as? String == "Demo" })

        let detail = try mcp.callToolJSON("egg_template_detail", arguments: [
            "template_name": "Demo",
            "project_directory": cwd,
        ])
        let basicInfo = try #require(detail["basicInfo"] as? [String: Any])
        #expect(basicInfo["name"] as? String == "Demo")
        #expect(detail["agentUsage"] != nil)
    }
}
