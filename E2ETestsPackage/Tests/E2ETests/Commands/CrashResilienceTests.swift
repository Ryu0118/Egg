import FileManagerProtocol
import Foundation
import Testing

/// SIGKILL resilience: no matter where a kill lands, the on-disk records must
/// stay readable (atomic writes), the flock must die with the process, and
/// the standard commands must recover the directory — no torn metadata, no
/// stuck locks, no unremovable records.
@Suite(.buildBinary, .serialized)
struct CrashResilienceTests {
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

    /// A project with a many-file template so apply/rollback take long enough
    /// for a kill to land mid-flight at least sometimes.
    private func makeProject(fileCount: Int = 400) throws -> URL {
        let root = try fileManager.makeTemporaryDirectory(prefix: "crash-e2e")
        try runGit(["init", "-q"], in: root)
        try runGit(["commit", "--allow-empty", "-q", "-m", "init"], in: root)
        let files = root.appending(path: ".eggs/Big/files/payload")
        try fileManager.createDirectory(at: files, withIntermediateDirectories: true)
        try "name: Big\ndescription: b\nhatch:\n  output: .\n"
            .write(to: root.appending(path: ".eggs/Big/config.yml"), atomically: true, encoding: .utf8)
        for index in 0 ..< fileCount {
            try String(repeating: "line \(index)\n", count: 20)
                .write(to: files.appending(path: "file-\(index).txt"), atomically: true, encoding: .utf8)
        }
        return root
    }

    /// Starts the binary detached, kills it with SIGKILL after `delay`, and
    /// waits for it to die.
    private func runAndKill(_ arguments: [String], in root: URL, afterMilliseconds delay: UInt64) async throws {
        let binary = try await BinaryBuildState.shared.getBinaryPath()
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        try await Task.sleep(for: .milliseconds(delay))
        let pid = process.processIdentifier
        kill(pid, SIGKILL)
        // waitUntilExit can miss the termination of a child SIGKILLed this
        // soon after launch (Foundation's termination source may not be armed
        // yet) and then spins its runloop forever — observed hanging both the
        // CI and local suites for 60+ minutes. Wait on the pid directly:
        // kill(pid, 0) fails with ESRCH once the process is fully gone. The
        // deadline turns a pathological leftover zombie into a bounded test
        // failure instead of an infinite hang.
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while kill(pid, 0) == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        if kill(pid, 0) == 0 {
            Issue.record("egg process \(pid) still present 30s after SIGKILL")
        }
    }

    /// The recovery invariants that must hold after any kill:
    /// listable records, parseable statuses, working locks, removable state.
    private func assertRecoverable(root: URL, runner: CLIRunner) async throws {
        let listed = try await runner.run("hatch", "transactions", workingDirectory: root)
        #expect(listed.succeeded, Comment(rawValue: listed.stderr))
        let entries = try #require(try json(listed.stdout)["transactions"] as? [[String: Any]])
        let validStatuses: Set = ["preview", "applied", "rolledBack", "corrupt", "orphanedRollback"]
        for entry in entries {
            let status = try #require(entry["status"] as? String)
            #expect(validStatuses.contains(status), "torn or invalid status: \(status)")
        }
        // Every leftover must be removable — proving the dead process's lock
        // released and no record is stuck half-written.
        for entry in entries {
            let token = try #require(entry["token"] as? String)
            let discarded = try await runner.run("hatch", "discard", token, "--force", workingDirectory: root)
            #expect(discarded.succeeded, Comment(rawValue: discarded.stderr))
        }
        let after = try await runner.run("hatch", "transactions", workingDirectory: root)
        #expect(try #require(try json(after.stdout)["transactions"] as? [[String: Any]]).isEmpty)
    }

    @Test("SIGKILL during apply leaves parseable records, a free lock, and a recoverable directory", arguments: [40, 120, 250] as [UInt64])
    func sigkillDuringApplyIsRecoverable(_ delayMilliseconds: UInt64) async throws {
        let runner = try await CLIRunner()
        let root = try makeProject()
        defer { try? fileManager.removeItem(at: root) }

        let preview = try await runner.run("hatch", "preview", "Big", workingDirectory: root)
        #expect(preview.succeeded, Comment(rawValue: preview.stderr))
        let token = try #require(try json(preview.stdout)["applyToken"] as? String)

        try await runAndKill(["hatch", "apply", token], in: root, afterMilliseconds: delayMilliseconds)

        // metadata.json must never be torn: it either still says preview or
        // already says applied — both parse.
        let metadataURL = root.appending(path: ".egg/transactions/\(token)/metadata.json")
        if exists(metadataURL) {
            let metadata = try json(String(contentsOf: metadataURL, encoding: .utf8))
            let status = try #require(metadata["status"] as? String)
            #expect(["preview", "applied"].contains(status), "apply must transition atomically, got \(status)")
        }

        try await assertRecoverable(root: root, runner: runner)
    }

    @Test("SIGKILL during rollback leaves the bundle retryable and the directory recoverable", arguments: [30, 100] as [UInt64])
    func sigkillDuringRollbackIsRetryable(_ delayMilliseconds: UInt64) async throws {
        let runner = try await CLIRunner()
        let root = try makeProject()
        defer { try? fileManager.removeItem(at: root) }

        let preview = try await runner.run("hatch", "preview", "Big", workingDirectory: root)
        let token = try #require(try json(preview.stdout)["applyToken"] as? String)
        let applied = try await runner.run("hatch", "apply", token, workingDirectory: root)
        #expect(applied.succeeded, Comment(rawValue: applied.stderr))

        try await runAndKill(["hatch", "rollback", token], in: root, afterMilliseconds: delayMilliseconds)

        // The manifest flips to rolledBack only after every restore: a killed
        // rollback must leave it retryable, and the retry must finish the job.
        let retried = try await runner.run("hatch", "rollback", token, workingDirectory: root)
        if retried.succeeded {
            #expect(!exists(root.appending(path: "files/payload/file-0.txt")), "retried rollback must restore the pre-apply state")
        } else {
            // The kill may have landed after completion — then retry correctly
            // reports alreadyRolledBack instead of corrupting anything.
            #expect(retried.stderr.contains("already rolled back"), Comment(rawValue: retried.stderr))
        }

        try await assertRecoverable(root: root, runner: runner)
    }

    @Test("SIGKILL during preview leaves at most a corrupt record that discard can remove")
    func sigkillDuringPreviewIsRecoverable() async throws {
        let runner = try await CLIRunner()
        let root = try makeProject()
        defer { try? fileManager.removeItem(at: root) }

        try await runAndKill(["hatch", "preview", "Big"], in: root, afterMilliseconds: 200)

        // Whatever the kill left behind (nothing, a shell, or a corrupt
        // record), the listing parses it and force-discard removes it. A
        // fresh preview afterwards must work normally.
        let listed = try await runner.run("hatch", "transactions", workingDirectory: root)
        #expect(listed.succeeded, Comment(rawValue: listed.stderr))
        let entries = try #require(try json(listed.stdout)["transactions"] as? [[String: Any]])
        for entry in entries {
            let token = try #require(entry["token"] as? String)
            let discarded = try await runner.run("hatch", "discard", token, "--force", workingDirectory: root)
            #expect(discarded.succeeded, Comment(rawValue: discarded.stderr))
        }

        let fresh = try await runner.run("hatch", "preview", "Big", workingDirectory: root)
        #expect(fresh.succeeded, Comment(rawValue: fresh.stderr))
        let token = try #require(try json(fresh.stdout)["applyToken"] as? String)
        _ = try await runner.run("hatch", "discard", token, workingDirectory: root)
    }
}
