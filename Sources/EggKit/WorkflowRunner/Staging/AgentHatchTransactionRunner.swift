import CryptoKit
import FileManagerProtocol
import Foundation
import Noora
import ProcessRunning

/// Runs `egg hatch` as a non-interactive, machine-readable transaction.
///
/// Instead of applying changes inline, a transaction is split into discrete
/// steps an agent can drive: ``preview()`` runs the template in a staging clone
/// and returns the proposed changes plus an apply token; ``apply(token:force:)``
/// commits them to the real working directory and records a rollback bundle;
/// ``rollback(id:force:)`` undoes a prior apply; and ``discard(token:)`` drops a
/// preview without applying it.
package struct AgentHatchTransactionRunner {
    private let processRunner: any ProcessRunning
    private let fileManager: any FileManagerProtocol
    private let workingDirectory: URL
    private let homeDirectory: URL
    private let noora: any Noorable
    private let templateDirectory: URL
    private let config: Config
    private let parsedMacros: [ParsedMacroDefinition]
    private let pathFilter: GitStagingChangeDetector.PathFilter
    private let store: HatchTransactionStore
    private let phaseRunner: PhaseRunner

    package init(
        processRunner: some ProcessRunning = ProcessRunner(),
        fileManager: some FileManagerProtocol,
        workingDirectory: URL,
        homeDirectory: URL,
        noora: some Noorable = Noora(),
        templateDirectory: URL,
        config: Config,
        parsedMacros: [ParsedMacroDefinition],
        include: [String] = [],
        exclude: [String] = [],
    ) {
        self.processRunner = processRunner
        self.fileManager = fileManager
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.noora = noora
        self.templateDirectory = templateDirectory
        self.config = config
        self.parsedMacros = parsedMacros
        pathFilter = GitStagingChangeDetector.PathFilter(include: include, exclude: exclude)
        store = HatchTransactionStore(fileManager: fileManager, workingDirectory: workingDirectory)
        phaseRunner = PhaseRunner(
            processRunner: processRunner,
            fileManager: fileManager,
            homeDirectory: homeDirectory,
            noora: noora,
            isInteractive: false,
            override: true,
        )
    }

    /// Runs the template in a staging clone and returns the proposed changes
    /// plus an apply token, without touching the real working directory.
    ///
    /// When `includeDiff` is set, each change carries its unified diff so a
    /// caller can review the exact content before applying.
    package func preview(includeDiff: Bool = false) async throws -> AgentHatchPreviewResult {
        if let allowedPaths = config.sandbox?.allowedPaths, !allowedPaths.isEmpty {
            throw LifecycleStepError.sandboxPermissionRequired(paths: allowedPaths)
        }

        // git is required. The whole change model — staging snapshot, .gitignore
        // suppression, change detection — is built on the working directory being
        // a git repository. There is no full-copy fallback: an agent cannot answer
        // an interactive "this may be slow, proceed?" prompt, and copying an
        // un-scoped directory (node_modules, .build, …) is exactly what we avoid.
        guard await GitRepositoryChecker(processRunner: processRunner).isGitRepository(workingDirectory) else {
            throw Error.notAGitRepository(path: workingDirectory.path(percentEncoded: false))
        }

        let token = makeToken(templateName: config.name)
        let tempBase = try fileManager.makeTemporaryDirectory(prefix: "egg-agent-\(token)")
        let tempWork = tempBase.appending(path: "work")
        let tempReference = tempBase.appending(path: "reference")

        let cloner = GitTrackedDirectoryCloner(
            processRunner: processRunner,
            fileManager: fileManager,
            noora: noora,
        )

        async let cloneWork: () = try cloner.clone(from: workingDirectory, to: tempWork)
        async let cloneReference: () = try cloner.clone(from: workingDirectory, to: tempReference)
        _ = try await (cloneWork, cloneReference)

        // Record a git baseline on the cloned tree, run the workflow, then ask
        // git what changed. The clone carries the project's tracked .gitignore,
        // so script-generated artifacts are suppressed without any hardcoded list.
        let detector = GitStagingChangeDetector(processRunner: processRunner, fileManager: fileManager)
        try await detector.recordBaseline(in: tempWork, filter: pathFilter)
        let snapshotWarnings = snapshotSizeWarnings(for: tempWork)
        let outputPath = try await runWorkflow(in: tempWork)
        let summary = try await detector.changes(in: tempWork, filter: pathFilter)
        var changes = makeAgentChanges(summary)
        if includeDiff {
            changes = try await attachDiffs(to: changes, detector: detector, workspace: tempWork)
        }
        let warnings = makeWarnings() + snapshotWarnings

        let transactionDirectory = try store.createDirectory(for: token)
        let workDestination = transactionDirectory.appending(path: "work")
        let referenceDestination = transactionDirectory.appending(path: "reference")
        try fileManager.moveItem(at: tempWork, to: workDestination)
        try fileManager.moveItem(at: tempReference, to: referenceDestination)
        try? fileManager.removeItem(at: tempBase)

        let metadata = HatchTransactionMetadata(
            applyToken: token,
            status: .preview,
            templateName: config.name,
            workingDirectory: workingDirectory.path(percentEncoded: false),
            outputDirectory: remapOutputPath(outputPath, from: workDestination),
            workDirectory: workDestination.path(percentEncoded: false),
            referenceDirectory: referenceDestination.path(percentEncoded: false),
            changes: changes.map(StoredChangeEntry.init),
            warnings: warnings,
            rollbackId: nil,
        )
        try store.save(metadata)

        return AgentHatchPreviewResult(
            applyToken: token,
            templateName: config.name,
            workingDirectory: workingDirectory.path(percentEncoded: false),
            outputDirectory: metadata.outputDirectory,
            strategy: "project_staging",
            rollbackGuarantee: "scoped",
            changes: changes,
            warnings: warnings,
            nextCommands: AgentTransactionCommands(
                apply: "egg hatch apply \(token)",
                discard: "egg hatch discard \(token)",
            ),
        )
    }

    /// Applies a previewed transaction to the real working directory.
    ///
    /// Fails if the working directory drifted from the preview baseline unless
    /// `force` is set. Backs up pre-apply content before touching anything, but
    /// only *publishes* the rollback bundle (making it discoverable to
    /// ``rollback(id:force:)``) after the apply itself succeeds — so a failed or
    /// partial apply never leaves behind a rollback bundle that looks valid for
    /// an apply that didn't actually complete.
    package func apply(token: String, force: Bool = false) async throws -> AgentHatchApplyResult {
        try Self.validateIdentifier(token, kind: "apply token")
        let metadata = try store.load(token: token)
        guard metadata.status == .preview else {
            throw Error.transactionNotPreview(token: token, status: metadata.status.rawValue)
        }

        let reference = URL(filePath: metadata.referenceDirectory)
        let work = URL(filePath: metadata.workDirectory)
        let working = URL(filePath: metadata.workingDirectory)

        let conflictDetector = WorkingDirectoryConflictDetector(fileManager: fileManager)
        let conflicts = try conflictDetector.conflictingPaths(
            referenceRoot: reference,
            workingRoot: working,
            paths: metadata.changes.map(\.path),
        )
        if !conflicts.isEmpty, !force {
            throw Error.conflictingWorkingDirectoryChanges(conflicts)
        }

        let pendingBundle = try prepareRollbackBundle(metadata: metadata, workRoot: work)
        do {
            try ApplyStagingArea.withStaging(
                workspaceRoot: work,
                workingDirectory: working,
                fileManager: fileManager,
            ) { staging, fs in
                let manifest = try staging.stage(changes: metadata.changeSummary, fileManager: fs)
                try staging.apply(manifest: manifest, fileManager: fs)
            }
        } catch {
            // The apply didn't complete: discard the bundle rather than leave an
            // orphaned rollback id that claims to back a completed apply.
            try? fileManager.removeItem(at: pendingBundle.rollbackRoot)
            throw error
        }
        try commitRollbackBundle(pendingBundle)

        let applied = try store.markApplied(token: token, rollbackId: pendingBundle.rollbackId)
        return AgentHatchApplyResult(
            status: "applied",
            applyToken: token,
            rollbackId: pendingBundle.rollbackId,
            appliedChanges: applied.changes.map(\.agentEntry),
            warnings: applied.warnings,
        )
    }

    /// Drops a previewed transaction and its staging area without applying it.
    package func discard(token: String) throws -> AgentHatchApplyResult {
        try Self.validateIdentifier(token, kind: "apply token")
        let metadata = try store.load(token: token)
        try store.discard(token: token)
        return AgentHatchApplyResult(
            status: "discarded",
            applyToken: token,
            rollbackId: nil,
            appliedChanges: metadata.changes.map(\.agentEntry),
            warnings: metadata.warnings,
        )
    }

    /// Restores files captured in a rollback bundle from a prior ``apply(token:force:)``.
    ///
    /// Refuses when the bundle was already rolled back, and — unless `force` is
    /// set — when any target file no longer matches the content the apply left
    /// behind (i.e. the user edited it after applying). This prevents a blind
    /// rollback from silently destroying post-apply work.
    ///
    /// Also refuses up front, before touching any file, if the bundle is missing
    /// a backup a `modify`/`delete` restore needs — a partial restore that still
    /// reports "rolledBack" would be a worse outcome than failing loudly.
    package func rollback(id rollbackId: String, force: Bool = false) throws -> AgentHatchRollbackResult {
        try Self.validateIdentifier(rollbackId, kind: "rollback id")
        let rollbackRoot = workingDirectory
            .appending(path: ".egg/rollback")
            .appending(path: rollbackId)
        let manifestURL = rollbackRoot.appending(path: "manifest.json")
        let data = try fileManager.readFile(at: manifestURL)
        var manifest = try JSONDecoder().decode(RollbackManifest.self, from: data)
        let beforeRoot = rollbackRoot.appending(path: "before")

        guard manifest.status != "rolledBack" else {
            throw Error.alreadyRolledBack(id: rollbackId)
        }

        if !force {
            let conflicts = rollbackConflicts(in: manifest)
            if !conflicts.isEmpty {
                throw Error.conflictingRollbackChanges(conflicts)
            }
        }

        let missingBackups = manifest.changes
            .filter { $0.kind == "modify" || $0.kind == "delete" }
            // existsAsLink, not exists: a backed-up symlink is often relative
            // and won't resolve from its new location under .egg/rollback, so
            // exists() would follow it, find nothing, and wrongly call a
            // present backup "missing".
            .filter { !fileManager.existsAsLink(beforeRoot.appending(path: $0.path)) }
            .map(\.path)
            .sorted()
        guard missingBackups.isEmpty else {
            throw Error.missingRollbackBackup(id: rollbackId, paths: missingBackups)
        }

        for change in manifest.changes.reversed() {
            let target = workingDirectory.appending(path: change.path)
            switch change.kind {
            case "add":
                // A forced apply may have overwritten a pre-existing file at an
                // "add" path; if the bundle backed it up, restore it instead of
                // just deleting.
                let source = beforeRoot.appending(path: change.path)
                if try !fileManager.copyIfExists(from: source, to: target) {
                    try fileManager.removeIfExists(target)
                    pruneEmptyDirectories(from: target.deletingLastPathComponent())
                }
            case "modify", "delete":
                let source = beforeRoot.appending(path: change.path)
                // The pre-flight check above already confirmed this exists; guard
                // again here as a defense against a TOCTOU race (backup removed
                // between the check and this copy) rather than trusting silently.
                guard try fileManager.copyIfExists(from: source, to: target) else {
                    throw Error.missingRollbackBackup(id: rollbackId, paths: [change.path])
                }
            default:
                break
            }
        }

        manifest.status = "rolledBack"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try (encoder.encode(manifest)).write(to: manifestURL)

        return AgentHatchRollbackResult(
            status: "rolledBack",
            rollbackId: rollbackId,
            restoredChanges: manifest.changes.map(\.agentEntry),
        )
    }

    /// SHA-256 hex digest used to fingerprint applied file content.
    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Paths whose current content no longer matches what the apply left behind.
    ///
    /// - `add`/`modify`: current file hash must equal the recorded `afterHash`.
    ///   A missing `add` target is not a conflict (the rollback action — remove —
    ///   is already satisfied); a missing `modify` target is.
    /// - `delete`: apply left the path absent, so its mere existence now means
    ///   the user recreated it.
    /// Legacy bundles without hashes skip the check for that entry.
    private func rollbackConflicts(in manifest: RollbackManifest) -> [String] {
        manifest.changes.compactMap { change in
            let target = workingDirectory.appending(path: change.path)
            switch change.kind {
            case "delete":
                return fileManager.exists(target) ? change.path : nil
            case "add", "modify":
                guard let afterHash = change.afterHash else { return nil }
                guard fileManager.exists(target) else {
                    return change.kind == "modify" ? change.path : nil
                }
                let currentHash = try? Self.sha256(of: fileManager.readFile(at: target))
                return currentHash == afterHash ? nil : change.path
            default:
                return nil
            }
        }
        .sorted()
    }

    /// Removes now-empty parent directories left behind after deleting an added
    /// file, walking up until a non-empty directory or the working directory root.
    private func pruneEmptyDirectories(from directory: URL) {
        var current = directory.standardizedFileURL
        let root = workingDirectory.standardizedFileURL
        while current.path(percentEncoded: false).hasPrefix(root.path(percentEncoded: false)),
              current != root,
              fileManager.isDirectory(at: current),
              (try? fileManager.contentsOfDirectory(atPath: current.path(percentEncoded: false)))?.isEmpty == true
        {
            try? fileManager.removeItem(at: current)
            current = current.deletingLastPathComponent().standardizedFileURL
        }
    }

    private func runWorkflow(in workspace: URL) async throws -> URL {
        let validator = ParsedMacroDefinitionValidator(
            config: config,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
        )
        let resolved = try validator.validate(parsedMacros)
        let macros = remapPathMacros(resolved, from: workingDirectory, to: workspace)
        let outputs = StepOutputsStorage()
        let environment = [
            "EGG_WORKING_DIRECTORY": workspace.path(percentEncoded: false),
            "EGG_WORKSPACE_ROOT": workspace.path(percentEncoded: false),
            "EGG_ORIGINAL_WORKING_DIRECTORY": workingDirectory.path(percentEncoded: false),
        ]
        let executionEnvironment = ExecutionEnvironment.sandboxed(.staging(
            root: workspace,
            originalWorkingDirectory: workingDirectory,
            allowedPaths: [],
        ))

        if let preHatch = config.preHatch {
            try await phaseRunner.executePreHatch(
                steps: preHatch,
                macros: macros,
                outputs: outputs,
                workingDirectory: workspace,
                additionalEnvironment: environment,
                executionEnvironment: executionEnvironment,
            )
        }

        let output = try await phaseRunner.executeHatch(
            config: config,
            macros: macros,
            outputs: outputs,
            templateDirectory: templateDirectory,
            workingDirectory: workspace,
            pathValidator: { path in
                guard path.isUnder(workspace) || path == workspace else {
                    throw StagingContext.Error.escapeAttempt(path: path.path(percentEncoded: false))
                }
            },
        )

        if let postHatch = config.postHatch {
            try await phaseRunner.executePostHatch(
                steps: postHatch,
                macros: macros,
                outputs: outputs,
                workingDirectory: workspace,
                additionalEnvironment: environment,
                executionEnvironment: executionEnvironment,
            )
        }

        return output
    }

    private func remapPathMacros(
        _ macros: [ResolvedMacro],
        from originalDirectory: URL,
        to workspaceRoot: URL,
    ) -> [ResolvedMacro] {
        macros.map { macro in
            guard case let .path(originalPath) = macro.value,
                  originalPath.isUnder(originalDirectory)
            else {
                return macro
            }
            return ResolvedMacro(
                name: macro.name,
                description: macro.description,
                value: .path(workspaceRoot.appending(path: originalPath.relativePath(from: originalDirectory))),
            )
        }
    }

    private func remapOutputPath(_ output: URL, from workDestination: URL) -> String {
        if output.isUnder(workDestination) || output == workDestination {
            let relative = output.relativePath(from: workDestination)
            return workingDirectory.appending(path: relative).path(percentEncoded: false)
        }
        return output.path(percentEncoded: false)
    }

    /// Warns (without failing) when the staging clone is unexpectedly large.
    ///
    /// A scoped git repo should never produce a huge snapshot, so crossing these
    /// limits usually means the project's `.gitignore` is missing entries. The
    /// warning names the limit that fired and how to narrow the snapshot, rather
    /// than silently proceeding.
    private func snapshotSizeWarnings(for workspace: URL) -> [AgentTransactionWarning] {
        var fileCount = 0
        var byteCount = 0
        if let enumerator = fileManager.enumerator(
            at: workspace,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [],
            errorHandler: nil,
        ) {
            while let item = enumerator.nextObject() as? URL {
                let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true else { continue }
                fileCount += 1
                byteCount += values?.fileSize ?? 0
            }
        }

        guard fileCount > Self.snapshotFileLimit || byteCount > Self.snapshotByteLimit else {
            return []
        }
        let megabytes = byteCount / (1024 * 1024)
        return [
            AgentTransactionWarning(
                code: "large_snapshot",
                message: "Staging snapshot is large (\(fileCount) files, \(megabytes) MB). This usually means .gitignore is missing entries. Add them, or narrow the snapshot with --exclude.",
            ),
        ]
    }

    private func makeAgentChanges(_ summary: ChangeSummary) -> [AgentChangeEntry] {
        summary.added.map { AgentChangeEntry(path: $0, kind: "add") }
            + summary.modified.map { AgentChangeEntry(path: $0, kind: "modify") }
            + summary.deleted.map { AgentChangeEntry(path: $0, kind: "delete") }
    }

    private func attachDiffs(
        to changes: [AgentChangeEntry],
        detector: GitStagingChangeDetector,
        workspace: URL,
    ) async throws -> [AgentChangeEntry] {
        var enriched: [AgentChangeEntry] = []
        enriched.reserveCapacity(changes.count)
        for change in changes {
            let diff = try await detector.unifiedDiff(for: change.path, in: workspace)
            enriched.append(AgentChangeEntry(path: change.path, kind: change.kind, diff: diff.isEmpty ? nil : diff))
        }
        return enriched
    }

    private func makeWarnings() -> [AgentTransactionWarning] {
        [
            AgentTransactionWarning(
                code: "rollback_scope",
                message: "Rollback can restore files inside the managed workspace only. External writes and network side effects from lifecycle scripts are not reversible.",
            ),
            AgentTransactionWarning(
                code: "gitignore_scoped",
                message: "Change detection follows the project's own .gitignore. Files ignored by git (build caches, node_modules, etc.) are not tracked as changes. Add a path to --include to force it in.",
            ),
        ]
    }

    /// A rollback bundle whose backups are written to disk but whose
    /// `manifest.json` has not yet been written — so ``rollback(id:force:)``
    /// (which requires `manifest.json` to exist) cannot see it yet. Call
    /// ``commitRollbackBundle(_:)`` to publish it, or delete `rollbackRoot` to
    /// discard it, once the caller knows whether the apply succeeded.
    private struct PendingRollbackBundle {
        let rollbackId: String
        let rollbackRoot: URL
        let manifestURL: URL
        let manifestData: Data
    }

    /// Backs up pre-apply content and computes post-apply hashes, without
    /// publishing the bundle. See ``PendingRollbackBundle``.
    private func prepareRollbackBundle(metadata: HatchTransactionMetadata, workRoot: URL) throws -> PendingRollbackBundle {
        let rollbackId = metadata.applyToken
        let rollbackRoot = workingDirectory
            .appending(path: ".egg/rollback")
            .appending(path: rollbackId)
        let beforeRoot = rollbackRoot.appending(path: "before")
        try fileManager.createDirectory(at: beforeRoot, withIntermediateDirectories: true)

        // Back up whatever currently exists at every target path — including
        // "add" paths: a forced apply can overwrite a file the user created
        // after the preview, and rollback must be able to restore it rather
        // than silently deleting it.
        //
        // Also record the hash of the content the apply will leave behind
        // (from the staging work tree), so rollback can detect post-apply
        // user edits instead of blindly overwriting them.
        let entries: [RollbackChangeEntry] = try metadata.changes.map { change in
            let source = workingDirectory.appending(path: change.path)
            let destination = beforeRoot.appending(path: change.path)
            _ = try fileManager.copyIfExists(from: source, to: destination)

            let appliedFile = workRoot.appending(path: change.path)
            let afterHash: String? = if change.kind == "delete" {
                nil
            } else if fileManager.exists(appliedFile) {
                try Self.sha256(of: fileManager.readFile(at: appliedFile))
            } else {
                nil
            }
            return RollbackChangeEntry(path: change.path, kind: change.kind, afterHash: afterHash)
        }

        let manifest = RollbackManifest(
            id: rollbackId,
            applyToken: metadata.applyToken,
            templateName: metadata.templateName,
            workingDirectory: metadata.workingDirectory,
            status: "applied",
            changes: entries,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestURL = rollbackRoot.appending(path: "manifest.json")
        return try PendingRollbackBundle(
            rollbackId: rollbackId,
            rollbackRoot: rollbackRoot,
            manifestURL: manifestURL,
            manifestData: encoder.encode(manifest),
        )
    }

    /// Publishes a prepared bundle by writing its `manifest.json`, making it
    /// discoverable to ``rollback(id:force:)``. Call only after the apply the
    /// bundle backs has actually succeeded.
    private func commitRollbackBundle(_ pending: PendingRollbackBundle) throws {
        try pending.manifestData.write(to: pending.manifestURL)
    }

    private func makeToken(templateName: String) -> String {
        let safeName = templateName
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
        return "\(Self.timestamp())-\(String(safeName))-\(UUID().uuidString.prefix(8))"
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
    }

    /// Rejects identifiers that aren't a single, safe path segment.
    ///
    /// `applyToken`/`rollbackId` become directory names under `.egg/`. They are
    /// normally generated by ``makeToken(templateName:)``, but `apply`/`discard`/
    /// `rollback` accept them from a caller (CLI arg or MCP tool argument), so a
    /// value like `"../../etc"` must be rejected before it reaches a file path.
    private static func validateIdentifier(_ value: String, kind: String) throws {
        guard !value.isEmpty, !value.contains("/"), !value.contains("\\"), value != ".", value != ".." else {
            throw Error.invalidIdentifier(kind: kind, value: value)
        }
    }

    private static let snapshotFileLimit = 10000
    private static let snapshotByteLimit = 100 * 1024 * 1024
}

extension AgentHatchTransactionRunner {
    enum Error: LocalizedError, Equatable {
        case transactionNotPreview(token: String, status: String)
        case conflictingWorkingDirectoryChanges([String])
        case notAGitRepository(path: String)
        case alreadyRolledBack(id: String)
        case conflictingRollbackChanges([String])
        case missingRollbackBackup(id: String, paths: [String])
        case invalidIdentifier(kind: String, value: String)

        var errorDescription: String? {
            switch self {
            case let .transactionNotPreview(token, status):
                "Transaction '\(token)' cannot be applied because its status is '\(status)'."
            case let .conflictingWorkingDirectoryChanges(paths):
                "Working directory changed since preview: \(paths.joined(separator: ", ")). Re-run preview or pass --force."
            case let .notAGitRepository(path):
                "'\(path)' is not a git repository. egg hatch needs git to scope and track changes safely. Run 'git init' first."
            case let .alreadyRolledBack(id):
                "Rollback '\(id)' was already rolled back."
            case let .conflictingRollbackChanges(paths):
                "Files changed since apply: \(paths.joined(separator: ", ")). Roll back anyway with --force (this overwrites those edits)."
            case let .missingRollbackBackup(id, paths):
                "Rollback bundle '\(id)' is missing its backup for: \(paths.joined(separator: ", ")). Refusing to restore only some files — nothing was changed."
            case let .invalidIdentifier(kind, value):
                "Invalid \(kind) '\(value)': must be a single path segment, not empty, and not '.' or '..'."
            }
        }
    }
}

private struct RollbackManifest: Codable {
    let id: String
    let applyToken: String
    let templateName: String
    let workingDirectory: String
    /// "applied" until rolled back, then "rolledBack". Legacy bundles without
    /// the field decode as nil and are treated as applied.
    var status: String?
    let changes: [RollbackChangeEntry]
}

private struct RollbackChangeEntry: Codable {
    let path: String
    let kind: String
    /// SHA-256 of the content the apply left at this path (nil for deletes and
    /// legacy bundles). Used to detect post-apply user edits before rolling back.
    let afterHash: String?

    var agentEntry: AgentChangeEntry {
        AgentChangeEntry(path: path, kind: kind)
    }
}
