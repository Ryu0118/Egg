import CryptoKit
import FileManagerProtocol
import Foundation
import Interaction
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
    private let templateDirectory: URL
    private let config: Config
    private let parsedMacros: [ParsedMacroDefinition]
    private let pathFilter: GitStagingChangeDetector.PathFilter
    private let sandboxDisabled: Bool
    private let allowedWritePaths: [String]
    private let allowLargeStaging: Bool
    private let allowNonGitStaging: Bool
    private let stagingFileLimit: Int
    private let store: HatchTransactionStore
    private let phaseRunner: PhaseRunner

    package init(
        processRunner: some ProcessRunning = ProcessRunner(),
        fileManager: some FileManagerProtocol,
        workingDirectory: URL,
        homeDirectory: URL,
        templateDirectory: URL,
        config: Config,
        parsedMacros: [ParsedMacroDefinition],
        include: [String] = [],
        exclude: [String] = [],
        sandboxDisabled: Bool = false,
        allowedWritePaths: [String] = [],
        allowLargeStaging: Bool = false,
        allowNonGitStaging: Bool = false,
        stagingFileLimit: Int = StagingPreflight.defaultFileLimit,
    ) {
        self.processRunner = processRunner
        self.fileManager = fileManager
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.templateDirectory = templateDirectory
        self.config = config
        self.parsedMacros = parsedMacros
        self.sandboxDisabled = sandboxDisabled
        self.allowedWritePaths = allowedWritePaths
        self.allowLargeStaging = allowLargeStaging
        self.allowNonGitStaging = allowNonGitStaging
        self.stagingFileLimit = stagingFileLimit
        pathFilter = GitStagingChangeDetector.PathFilter(include: include, exclude: exclude)
        store = HatchTransactionStore(fileManager: fileManager, workingDirectory: workingDirectory)
        phaseRunner = PhaseRunner(
            processRunner: processRunner,
            fileManager: fileManager,
            homeDirectory: homeDirectory,
            interaction: GuardedTerminal(),
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
        // Macros are resolved up front (not inside runWorkflow) because the
        // declared sandbox.allowed_paths may reference them, and the consent
        // check below must fail fast — before any clone or script runs.
        let validator = ParsedMacroDefinitionValidator(
            config: config,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
        )
        let resolvedMacros = try await validator.validate(parsedMacros)
        let grant = try await resolveWriteGrant(resolvedMacros: resolvedMacros)

        // Staging strongly prefers git: the change model — staging snapshot,
        // .gitignore suppression of build artifacts, scoped change detection —
        // rides on it. A non-git directory is stageable with explicit consent
        // (`allowNonGitStaging`): the refusal below reports the resolved
        // directory and its measured size, so an agent can inspect the facts
        // and decide, the way a human answers the interactive prompt.
        //
        // The decision itself (git? how many files? within the guard?) is
        // shared with EggService.hatchTemplate's MCP path via
        // StagingFeasibility, so the two entry points can't drift apart on
        // what "too large" or "needs consent" means — only the error type
        // each throws differs.
        var contextWarnings: [AgentTransactionWarning] = []

        if let repositoryRoot = await GitRepositoryChecker(processRunner: processRunner).repositoryRoot(of: workingDirectory) {
            // Running from a subdirectory of the repository is legal, but every
            // relative path — hatch.output above all — resolves against the
            // subdirectory, not the repository root. That mismatch is silent and
            // lands files in the wrong place, so the result says it out loud.
            if !workingDirectory.isSamePath(to: repositoryRoot) {
                contextWarnings.append(AgentTransactionWarning(
                    code: "subdirectory_of_repository",
                    message: "The working directory is a subdirectory of the git repository at \(repositoryRoot.path(percentEncoded: false)). Staging and relative output paths (hatch.output) resolve against the subdirectory, not the repository root — run from the root if the template should target it.",
                ))
            }
        }

        let feasibility = StagingFeasibility(processRunner: processRunner, fileManager: fileManager)
        let facts = try await feasibility.facts(for: workingDirectory, processRunner: processRunner, countCap: stagingFileLimit)
        switch feasibility.decide(facts: facts, allowLargeStaging: allowLargeStaging, allowNonGitStaging: allowNonGitStaging, limit: stagingFileLimit) {
        case let .proceed(warnings):
            if warnings.contains(.nonGitStaging) {
                contextWarnings.append(AgentTransactionWarning(
                    code: "non_git_staging",
                    message: "'\(workingDirectory.path(percentEncoded: false))' is not a git repository: every file was copied into staging and script-generated artifacts (build directories, caches) will be reported as changes. Run 'git init' there so staging follows .gitignore.",
                ))
            }
        case let .nonGitConsentRequired(fileCount, isExact):
            throw Error.nonGitStagingRequiresConsent(
                path: workingDirectory.path(percentEncoded: false),
                fileCount: fileCount,
                isExact: isExact,
            )
        case let .tooLarge(fileCount, limit):
            throw Error.stagingTooLarge(fileCount: fileCount, limit: limit)
        }

        let token = makeToken(templateName: config.name)
        let tempBase = try fileManager.makeTemporaryDirectory(prefix: "egg-agent-\(token)")

        do {
            // Stage in the temp clone and materialize the transaction record.
            return try await materializePreview(
                token: token,
                tempBase: tempBase,
                resolvedMacros: resolvedMacros,
                grant: grant,
                includeDiff: includeDiff,
                contextWarnings: contextWarnings,
            )
        } catch {
            // Nothing observable was committed — metadata.json is written
            // last, inside the lock — so leave no debris behind: without
            // this, every failed preview (a broken lifecycle script, a
            // read-only .egg, a failed clone) leaked the temp clone in
            // TMPDIR and, past the lock step, an empty transaction shell.
            try? fileManager.removeItem(at: tempBase)
            let transactionDirectory = store.directory(for: token)
            if !fileManager.exists(transactionDirectory.appending(path: "metadata.json")) {
                try? fileManager.removeItem(at: transactionDirectory)
            }
            throw error
        }
    }

    /// Applies a previewed — or previously rolled-back — transaction to the
    /// real working directory.
    ///
    /// A `rolledBack` transaction re-applies from its retained staging tree:
    /// lifecycle scripts ran at preview time, so re-apply is a pure file copy,
    /// and a fresh rollback bundle replaces the consumed one under the same id.
    ///
    /// Fails if the working directory drifted from the preview baseline unless
    /// `force` is set. Backs up pre-apply content before touching anything, but
    /// only *publishes* the rollback bundle (making it discoverable to
    /// ``rollback(id:force:)``) after the apply itself succeeds — so a failed or
    /// partial apply never leaves behind a rollback bundle that looks valid for
    /// an apply that didn't actually complete.
    package func apply(token: String, force: Bool = false) async throws -> AgentHatchApplyResult {
        try Self.validateIdentifier(token, kind: "apply token")
        // The whole read-check-mutate sequence is one critical section: two
        // concurrent applies of the same token both observing an applicable
        // status before either writes anything is a lost-update race
        // (whichever finishes last wins, silently corrupting the other's
        // rollback bundle and working-directory writes). Locking per-token
        // means unrelated transactions never serialize against each other.
        return try await TransactionLock.shared.withLock(directory: store.directory(for: token), fileManager: fileManager) {
            guard store.metadataExists(token: token) else {
                // Drop the empty shell this lock's directory creation may have
                // just made (final act before the throw, per the lock protocol).
                removeLockShell(at: store.directory(for: token))
                throw Error.transactionNotFound(token: token)
            }
            guard let metadata = try? store.load(token: token) else {
                throw Error.corruptTransactionRecord(token: token)
            }
            guard metadata.status == .preview || metadata.status == .rolledBack else {
                throw Error.transactionNotApplicable(token: token, status: metadata.status.rawValue)
            }
            let isReapply = metadata.status == .rolledBack

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

            // A consumed bundle from the previous apply would otherwise merge
            // with the fresh backups under before/ and corrupt the new bundle.
            // Safe unconditionally: for preview the directory normally doesn't
            // exist, and a rolled-back bundle's restore already happened.
            try fileManager.removeIfExists(rollbackRoot(for: metadata.applyToken))

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
            var warnings = applied.warnings
            if isReapply {
                warnings.append(AgentTransactionWarning(
                    code: "reapplied_after_rollback",
                    message: "Transaction was re-applied after rollback. A fresh rollback bundle replaced the consumed one; the rollbackId is unchanged: \(pendingBundle.rollbackId).",
                ))
            }
            return AgentHatchApplyResult(
                status: "applied",
                applyToken: token,
                rollbackId: pendingBundle.rollbackId,
                appliedChanges: applied.changes.map(\.agentEntry),
                warnings: warnings,
            )
        }
    }

    /// Deletes a transaction's records — `.egg/transactions/<token>/` and its
    /// rollback bundle `.egg/rollback/<token>/` — as a pair, from any state.
    ///
    /// What is lost depends on the status: a `preview` loses only its staged
    /// proposal, a `rolledBack` transaction loses the option to re-apply, and
    /// an `applied` transaction loses its rollback bundle — the only way to
    /// undo the apply — which is why that state requires `force`.
    ///
    /// Also accepts orphaned rollback bundles left by pre-unification egg
    /// versions (whose discard removed only the transaction directory).
    package func discard(token: String, force: Bool = false) async throws -> AgentHatchDiscardResult {
        try Self.validateIdentifier(token, kind: "apply token")
        return try await TransactionLock.shared.withLocks(
            outer: store.directory(for: token),
            inner: rollbackRoot(for: token),
            fileManager: fileManager,
        ) {
            try discardLocked(token: token, bundleRoot: rollbackRoot(for: token), force: force)
        }
    }

    /// Lists every transaction record under `.egg/` — transactions and
    /// orphaned rollback bundles alike — so leftovers are visible and can be
    /// cleaned up with ``discard(token:force:)``.
    ///
    /// Read-only and lock-free: a torn read during a concurrent mutation can
    /// at worst misreport one entry's status, which the next listing corrects.
    /// Corrupt metadata surfaces as `"corrupt"` rather than failing the whole
    /// listing; bundles without a transaction directory as `"orphanedRollback"`.
    ///
    /// `includeSizes` walks every record's full directory tree to compute its
    /// disk footprint — cost proportional to the total staged bytes on disk,
    /// not the number of records — so it is off by default and a plain
    /// listing stays a cheap metadata read.
    package func transactions(includeSizes: Bool = false) -> AgentHatchTransactionsResult {
        var summaries: [AgentHatchTransactionSummary] = []
        let decoder = JSONDecoder()

        for token in store.tokens() {
            let transactionDir = store.directory(for: token)
            let bundleDir = rollbackRoot(for: token)
            let hasBundle = fileManager.exists(bundleDir.appending(path: "manifest.json"))
            let sizeBytes: Int? = includeSizes
                ? directoryFootprint(of: transactionDir).byteCount
                + (hasBundle ? directoryFootprint(of: bundleDir).byteCount : 0)
                : nil
            if let metadata = try? store.load(token: token) {
                summaries.append(AgentHatchTransactionSummary(
                    token: token,
                    status: AgentHatchTransactionStatus(rawValue: metadata.status.rawValue) ?? .corrupt,
                    templateName: metadata.templateName,
                    sizeBytes: sizeBytes,
                    hasRollbackBundle: hasBundle,
                ))
            } else {
                summaries.append(AgentHatchTransactionSummary(
                    token: token,
                    status: .corrupt,
                    templateName: nil,
                    sizeBytes: sizeBytes,
                    hasRollbackBundle: hasBundle,
                ))
            }
        }

        let knownTokens = Set(summaries.map(\.token))
        let bundlesRoot = workingDirectory.appending(path: ".egg/rollback")
        let bundleDirs = (try? fileManager.contentsOfDirectory(at: bundlesRoot, includingPropertiesForKeys: nil, options: [])) ?? []
        for bundleDir in bundleDirs where fileManager.isDirectory(at: bundleDir) {
            let id = bundleDir.lastPathComponent
            guard !knownTokens.contains(id) else { continue }
            let manifest = (try? fileManager.readFile(at: bundleDir.appending(path: "manifest.json")))
                .flatMap { try? decoder.decode(RollbackManifest.self, from: $0) }
            summaries.append(AgentHatchTransactionSummary(
                token: id,
                status: .orphanedRollback,
                templateName: manifest?.templateName,
                sizeBytes: includeSizes ? directoryFootprint(of: bundleDir).byteCount : nil,
                hasRollbackBundle: true,
            ))
        }

        return AgentHatchTransactionsResult(
            status: "ok",
            workingDirectory: workingDirectory.path(percentEncoded: false),
            // Tokens start with an ISO timestamp, so this sorts chronologically.
            transactions: summaries.sorted { $0.token < $1.token },
        )
    }

    /// Restores files captured in a rollback bundle from a prior ``apply(token:force:)``,
    /// then marks the transaction `rolledBack` in both the bundle manifest and
    /// the transaction metadata — re-enabling ``apply(token:force:)`` for the
    /// same token.
    ///
    /// Refuses when the bundle was already rolled back, and — unless `force` is
    /// set — when any target file no longer matches the content the apply left
    /// behind (i.e. the user edited it after applying). This prevents a blind
    /// rollback from silently destroying post-apply work.
    ///
    /// Also refuses up front, before touching any file, if the bundle is missing
    /// a backup a `modify`/`delete` restore needs — a partial restore that still
    /// reports "rolledBack" would be a worse outcome than failing loudly.
    package func rollback(id rollbackId: String, force: Bool = false) async throws -> AgentHatchRollbackResult {
        try Self.validateIdentifier(rollbackId, kind: "rollback id")
        let rollbackRoot = rollbackRoot(for: rollbackId)
        // Both per-token locks via withLocks. The whole
        // read-check-restore-rewrite sequence is one critical section: two
        // concurrent rollbacks of the same id both read status == "applied"
        // before either writes, so without the locks both proceed to restore
        // (harmless-ish for idempotent copies, but a racing
        // pruneEmptyDirectories can throw, and the final manifest write —
        // last writer wins — risks a reader observing torn JSON). The outer
        // transactions lock additionally covers the metadata.json rewrite.
        return try await TransactionLock.shared.withLocks(
            outer: store.directory(for: rollbackId),
            inner: rollbackRoot,
            fileManager: fileManager,
        ) {
            let manifestURL = rollbackRoot.appending(path: "manifest.json")
            guard fileManager.exists(manifestURL) else {
                // Drop the empty shells the locks' directory creation may have
                // just made (final act before the throw, per the lock
                // protocol). Directories with real content are never touched.
                removeLockShell(at: rollbackRoot)
                if !store.metadataExists(token: rollbackId) {
                    removeLockShell(at: store.directory(for: rollbackId))
                }
                throw Error.transactionNotFound(token: rollbackId)
            }
            let data = try fileManager.readFile(at: manifestURL)
            guard var manifest = try? JSONDecoder().decode(RollbackManifest.self, from: data) else {
                throw Error.corruptTransactionRecord(token: rollbackId)
            }
            let beforeRoot = rollbackRoot.appending(path: "before")

            guard manifest.status != .rolledBack else {
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

            manifest.status = .rolledBack
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            // Atomic: a reader outside the lock (e.g. a status inspection)
            // must never observe a torn write.
            try (encoder.encode(manifest)).write(to: manifestURL, options: .atomic)

            // Keep metadata.json — the status source of truth — in step with
            // the manifest. An orphaned bundle (pre-unification discard removed
            // the transaction dir) has no metadata; drop the empty shell the
            // outer lock's directory creation left behind instead.
            //
            // Deleting the shell unlinks the outer lock's file while it is
            // still held, which TransactionLock's protocol permits only as
            // the final act before release — no guarded work may follow.
            if try store.markRolledBackIfPresent(token: rollbackId) == nil {
                removeLockShell(at: store.directory(for: rollbackId))
            }

            return AgentHatchRollbackResult(
                status: "rolledBack",
                rollbackId: rollbackId,
                restoredChanges: manifest.changes.map(\.agentEntry),
            )
        }
    }

    /// SHA-256 hex digest used to fingerprint applied file content.
    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Clones the working directory into `tempBase`, runs the template
    /// workflow there, and materializes the transaction record under
    /// `.egg/transactions/<token>` — the staging half of `preview`, split
    /// out so the caller can guarantee cleanup on any failure.
    private func materializePreview(
        token: String,
        tempBase: URL,
        resolvedMacros: [ResolvedMacro],
        grant: WriteGrant,
        includeDiff: Bool,
        contextWarnings: [AgentTransactionWarning] = [],
    ) async throws -> AgentHatchPreviewResult {
        let tempWork = tempBase.appending(path: "work")
        let tempReference = tempBase.appending(path: "reference")

        let cloner = GitTrackedDirectoryCloner(
            processRunner: processRunner,
            fileManager: fileManager,
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
        let outputPath = try await runWorkflow(in: tempWork, resolvedMacros: resolvedMacros, allowedPaths: grant.granted)
        let summary = try await detector.changes(in: tempWork, filter: pathFilter)
        var changes = makeAgentChanges(summary)
        if includeDiff {
            changes = try await attachDiffs(to: changes, detector: detector, workspace: tempWork)
        }
        let warnings = makeWarnings() + grant.warnings + snapshotWarnings + contextWarnings

        // Only the final directory-materialization step is locked — cheap
        // insurance against a concurrent discard()/apply() enumerating or
        // cleaning up .egg/transactions/ at the same moment. The expensive
        // clone + workflow run above stays unlocked so concurrent previews
        // (of the same or different templates) don't serialize against each
        // other; each gets its own uniquely-tokened transaction directory, so
        // there's no shared mutable state until this point.
        let metadata = try await TransactionLock.shared.withLock(directory: store.directory(for: token), fileManager: fileManager) {
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
            return metadata
        }

        // The transaction records live under this runner's workingDirectory.
        // When that differs from the caller's process cwd (preview ran with
        // --output/staging_root), a bare `egg hatch apply <token>` from cwd
        // cannot find them — so the suggested commands must carry
        // --working-directory, not just hope the caller cd's first.
        let workingDirectoryArgument = workingDirectory.isSamePath(to: URL(filePath: fileManager.currentDirectoryPath))
            ? ""
            : " --working-directory '\(workingDirectory.path(percentEncoded: false))'"

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
                apply: "egg hatch apply \(token)\(workingDirectoryArgument)",
                discard: "egg hatch discard \(token)\(workingDirectoryArgument)",
            ),
        )
    }

    private func rollbackRoot(for id: String) -> URL {
        workingDirectory
            .appending(path: ".egg/rollback")
            .appending(path: id)
    }

    /// Removes a lock-shell directory — one containing nothing but the lock
    /// file the caller's own acquisition just created — left behind when an
    /// operation targeted a token that has no records. A directory with any
    /// real content (crash-orphaned `before/` backups, a staged `work/` tree)
    /// is never touched.
    private func removeLockShell(at directory: URL) {
        let contents = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: []))?
            .map(\.lastPathComponent) ?? []
        if contents.allSatisfy({ $0 == ".lock" }) {
            try? fileManager.removeItem(at: directory)
        }
    }

    /// What a discard is aimed at, resolved before any authorization or
    /// deletion happens.
    private enum DiscardTarget {
        case transaction(HatchTransactionMetadata)
        /// metadata.json exists but cannot be decoded: whether an undoable
        /// apply is at stake is unknowable.
        case corruptTransaction
        /// A rollback bundle with no transaction directory, left by a
        /// pre-unification egg version. nil manifest means it too is corrupt.
        case orphanedBundle(RollbackManifest?)
        case missing
    }

    private func classifyDiscardTarget(token: String, bundleRoot: URL) -> DiscardTarget {
        if store.metadataExists(token: token) {
            guard let metadata = try? store.load(token: token) else { return .corruptTransaction }
            return .transaction(metadata)
        }
        if fileManager.exists(bundleRoot.appending(path: "manifest.json")) {
            let manifest = (try? fileManager.readFile(at: bundleRoot.appending(path: "manifest.json")))
                .flatMap { try? JSONDecoder().decode(RollbackManifest.self, from: $0) }
            return .orphanedBundle(manifest)
        }
        return .missing
    }

    /// Every deletion below unlinks the very lock files the caller is holding
    /// (they live inside the deleted directories). TransactionLock's protocol
    /// permits that only as the final act before release: each branch deletes
    /// and then immediately returns or throws, with no guarded work after.
    private func discardLocked(token: String, bundleRoot: URL, force: Bool) throws -> AgentHatchDiscardResult {
        let bundleExists = fileManager.exists(bundleRoot.appending(path: "manifest.json"))

        switch classifyDiscardTarget(token: token, bundleRoot: bundleRoot) {
        case let .transaction(metadata):
            guard metadata.status != .applied || force else {
                throw Error.discardRequiresForce(token: token, status: metadata.status.rawValue)
            }
            // Bundle first: it holds the only rollback backup. removeItem
            // recurses child-first, so a container it can't remove (e.g. a
            // read-only parent) throws after already deleting the backup
            // files inside — doing this second would leave that partial
            // delete with no transaction record left to retry discard from.
            try fileManager.removeIfExists(bundleRoot)
            try store.discard(token: token)
            return AgentHatchDiscardResult(
                status: "discarded",
                applyToken: token,
                rollbackId: bundleExists ? token : nil,
                discardedChanges: metadata.changes.map(\.agentEntry),
                warnings: metadata.warnings,
            )

        case .corruptTransaction:
            guard force else {
                throw Error.discardRequiresForce(token: token, status: "corrupt")
            }
            try fileManager.removeIfExists(bundleRoot)
            try store.discard(token: token)
            return AgentHatchDiscardResult(
                status: "discarded",
                applyToken: token,
                rollbackId: bundleExists ? token : nil,
                discardedChanges: [],
                warnings: [],
            )

        case let .orphanedBundle(manifest):
            // A nil manifest status means applied (legacy bundles), so it
            // still guards an undoable apply and needs force.
            let manifestStatus = manifest?.status ?? .applied
            guard manifestStatus == .rolledBack || force else {
                throw Error.discardRequiresForce(token: token, status: manifest == nil ? "corrupt" : manifestStatus.rawValue)
            }
            try fileManager.removeIfExists(bundleRoot)
            // Drop the empty shell the outer lock's directory creation left.
            removeLockShell(at: store.directory(for: token))
            return AgentHatchDiscardResult(
                status: "discarded",
                applyToken: token,
                rollbackId: token,
                discardedChanges: manifest.map { $0.changes.map(\.agentEntry) } ?? [],
                warnings: [],
            )

        case .missing:
            removeLockShell(at: store.directory(for: token))
            removeLockShell(at: bundleRoot)
            throw Error.transactionNotFound(token: token)
        }
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

    /// Declared external write paths the caller consented to, plus any
    /// warnings the consent resolution produced.
    private struct WriteGrant {
        let granted: [URL]
        let warnings: [AgentTransactionWarning]

        static let none = WriteGrant(granted: [], warnings: [])
    }

    /// Resolves which of the template's declared `sandbox.allowed_paths` are
    /// actually writable in this preview run.
    ///
    /// The declaration in config.yml is the *template's* request, not the
    /// caller's consent — a template must never gain external write access just
    /// by declaring it. Consent is expressed by naming each path explicitly
    /// (`--allow-write` / `allowed_write_paths`), and only paths that are both
    /// declared and consented are granted:
    ///
    /// - consented but not declared → error (typo, or the template changed)
    /// - declared but nothing consented → fail fast with the expanded list so
    ///   the caller can ask the user and retry, before anything runs
    /// - declared but only partially consented → proceed; unconsented paths
    ///   stay denied by the sandbox, reported as a warning
    private func resolveWriteGrant(resolvedMacros: [ResolvedMacro]) async throws -> WriteGrant {
        let declared = try await SandboxAllowedPathsResolver(homeDirectory: homeDirectory)
            .expandAllowedPaths(
                config.sandbox?.allowedPaths,
                macros: resolvedMacros,
                workingDirectory: workingDirectory,
            )
        // --no-sandbox (already double-confirmed upstream) makes everything
        // writable; per-path consent is moot.
        guard !sandboxDisabled else { return .none }

        let declaredPaths = declared.map { Self.normalizePath($0.path(percentEncoded: false)) }
        let consented = allowedWritePaths.map(Self.normalizePath)

        let undeclared = consented.filter { !declaredPaths.contains($0) }
        guard undeclared.isEmpty else {
            throw Error.writeConsentNotDeclared(paths: undeclared.sorted(), declaredPaths: declaredPaths.sorted())
        }
        guard declaredPaths.isEmpty || !consented.isEmpty else {
            throw Error.writeConsentRequired(declaredPaths: declaredPaths.sorted())
        }

        let granted = zip(declared, declaredPaths)
            .filter { consented.contains($0.1) }
            .map(\.0)
        var warnings: [AgentTransactionWarning] = []
        if !granted.isEmpty {
            warnings.append(AgentTransactionWarning(
                code: "external_writes_immediate",
                message: "Lifecycle scripts may write to consented external paths during preview. Those writes happen immediately and are not reverted by discard or rollback.",
            ))
        }
        let denied = declaredPaths.filter { !consented.contains($0) }
        if !denied.isEmpty {
            warnings.append(AgentTransactionWarning(
                code: "declared_paths_not_granted",
                message: "Declared sandbox.allowed_paths without consent stay write-denied: \(denied.sorted().joined(separator: ", ")). Scripts touching them will fail.",
            ))
        }
        return WriteGrant(granted: granted, warnings: warnings)
    }

    /// Normalizes a path for consent comparison: standardized, no trailing slash.
    private static func normalizePath(_ raw: String) -> String {
        var path = URL(filePath: raw).standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private func runWorkflow(in workspace: URL, resolvedMacros: [ResolvedMacro], allowedPaths: [URL]) async throws -> URL {
        let macros = remapPathMacros(resolvedMacros, from: workingDirectory, to: workspace)
        let outputs = StepOutputsStorage()
        let environment = [
            "EGG_WORKING_DIRECTORY": workspace.path(percentEncoded: false),
            "EGG_WORKSPACE_ROOT": workspace.path(percentEncoded: false),
            "EGG_ORIGINAL_WORKING_DIRECTORY": workingDirectory.path(percentEncoded: false),
        ]
        let executionEnvironment: ExecutionEnvironment = if sandboxDisabled {
            .unsandboxed
        } else {
            .sandboxed(.staging(
                root: workspace,
                originalWorkingDirectory: workingDirectory,
                allowedPaths: allowedPaths,
            ))
        }

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
        let (fileCount, byteCount) = directoryFootprint(of: workspace)

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

    private func directoryFootprint(of directory: URL) -> (fileCount: Int, byteCount: Int) {
        var fileCount = 0
        var byteCount = 0
        if let enumerator = fileManager.enumerator(
            at: directory,
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
        return (fileCount, byteCount)
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
        let rollbackRoot = rollbackRoot(for: rollbackId)
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
            // A symlink (e.g. a directory alias like `.claude/rules -> ../.agents/rules`,
            // which lifecycle scripts commonly create) reports `exists(_:)` true but
            // `readFile` follows it and throws `.fileReadNoSuchFile` when the target is a
            // directory — content can't be read through a link that way. Hash the link's
            // destination string instead of its target's bytes: it still changes if the
            // link is redirected, which is all this hash needs to detect.
            let afterHash: String? = if change.kind == "delete" {
                nil
            } else if fileManager.isSymbolicLink(at: appliedFile) {
                try Self.sha256(of: Data(
                    fileManager.destinationOfSymbolicLink(atPath: appliedFile.path(percentEncoded: false)).utf8,
                ))
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
            status: .applied,
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
        // Atomic: transactions() reads manifests lock-free, so the initial
        // publish must never be observable half-written — same invariant as
        // every other metadata/manifest write.
        try pending.manifestData.write(to: pending.manifestURL, options: .atomic)
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
        // 255 bytes is the filename-component limit on APFS and most POSIX
        // filesystems; past it, FileManager surfaces its own raw Cocoa "file
        // name is invalid" error instead of this one.
        guard !value.isEmpty, value.utf8.count <= 255,
              !value.contains("/"), !value.contains("\\"), value != ".", value != ".."
        else {
            throw Error.invalidIdentifier(kind: kind, value: value)
        }
    }

    private static let snapshotFileLimit = 10000
    private static let snapshotByteLimit = 100 * 1024 * 1024
}

extension AgentHatchTransactionRunner {
    enum Error: LocalizedError, Equatable {
        case transactionNotApplicable(token: String, status: String)
        case conflictingWorkingDirectoryChanges([String])
        case notAGitRepository(path: String)
        case alreadyRolledBack(id: String)
        case conflictingRollbackChanges([String])
        case discardRequiresForce(token: String, status: String)
        case transactionNotFound(token: String)
        case corruptTransactionRecord(token: String)
        case missingRollbackBackup(id: String, paths: [String])
        case invalidIdentifier(kind: String, value: String)
        case writeConsentRequired(declaredPaths: [String])
        case writeConsentNotDeclared(paths: [String], declaredPaths: [String])
        case stagingTooLarge(fileCount: Int, limit: Int)
        case nonGitStagingRequiresConsent(path: String, fileCount: Int, isExact: Bool)

        var errorDescription: String? {
            switch self {
            case let .transactionNotApplicable(token, status):
                "Transaction '\(token)' cannot be applied because its status is '\(status)'. Only 'preview' and 'rolledBack' transactions can be applied; an 'applied' transaction must be rolled back first: egg hatch rollback \(token)."
            case let .conflictingWorkingDirectoryChanges(paths):
                "Working directory changed since preview: \(paths.joined(separator: ", ")). Re-run preview or pass --force."
            case let .notAGitRepository(path):
                "'\(path)' is not a git repository. egg hatch needs git to scope and track changes safely. Run 'git init' first."
            case let .alreadyRolledBack(id):
                "Rollback '\(id)' was already rolled back. Re-apply with 'egg hatch apply \(id)' or delete the transaction with 'egg hatch discard \(id)'."
            case let .conflictingRollbackChanges(paths):
                "Files changed since apply: \(paths.joined(separator: ", ")). Roll back anyway with --force (this overwrites those edits)."
            case let .discardRequiresForce(token, status):
                "Discarding transaction '\(token)' (status: '\(status)') deletes its rollback bundle — the only way to undo the apply. To undo the changes instead, run 'egg hatch rollback \(token)' first. To delete the records anyway and keep the applied files as they are, pass --force (CLI) or force: true (MCP)."
            case let .transactionNotFound(token):
                "No transaction or rollback bundle found for '\(token)'. Run 'egg hatch transactions' to list known transactions. If the preview ran with --output <dir> (or staging_root over MCP), its records live under that directory — pass --working-directory <dir> (working_directory over MCP)."
            case let .corruptTransactionRecord(token):
                "Transaction '\(token)' has a corrupt record on disk and cannot be applied or rolled back. Delete its records with 'egg hatch discard \(token) --force', then re-run preview."
            case let .missingRollbackBackup(id, paths):
                "Rollback bundle '\(id)' is missing its backup for: \(paths.joined(separator: ", ")). Refusing to restore only some files — nothing was changed."
            case let .invalidIdentifier(kind, value):
                "Invalid \(kind) '\(value)': must be a single path segment, not empty, and not '.' or '..'."
            case let .nonGitStagingRequiresConsent(path, fileCount, isExact):
                "'\(path)' is not a git repository. Staging it would copy all \(fileCount)\(isExact ? "" : "+") files in that directory — no .gitignore filtering, so build artifacts and caches are included — twice (workspace + reference). Recommended: run 'git init' in '\(path)' so staging follows .gitignore. To proceed anyway, retry with --allow-non-git-staging (allow_non_git_staging over MCP); a count above the large-staging guard additionally needs --allow-large-staging. For a direct write without preview/rollback, use 'egg hatch direct --no-staging'."
            case let .stagingTooLarge(fileCount, limit):
                "Staging would clone \(fileCount) files (guard limit: \(limit)) — twice, once for the workspace and once for the reference copy. Scope it down by previewing against a smaller directory (--output <subdir> on the CLI, staging_root over MCP), write directly with 'egg hatch direct <template> --no-staging' (no preview/rollback), or pass --allow-large-staging (allow_large_staging over MCP) to proceed anyway."
            case let .writeConsentRequired(declaredPaths):
                """
                ⚠️ SANDBOX EXTENDED WRITE ACCESS REQUIRED

                This template declares write access to paths outside the staging sandbox:
                \(declaredPaths.map { "  - \($0)" }.joined(separator: "\n"))

                Ask the user whether to allow writing to these exact paths. Do not decide yourself.
                If the user approves, retry naming each approved path explicitly:
                  CLI: egg hatch preview <template> ... \(declaredPaths.map { "--allow-write \($0)" }.joined(separator: " "))
                  MCP: pass allowed_write_paths: [\(declaredPaths.map { "\"\($0)\"" }.joined(separator: ", "))]

                Writes to approved paths happen during preview and are NOT reverted by discard or rollback.
                Nothing has been executed yet.
                """
            case let .writeConsentNotDeclared(paths, declaredPaths):
                """
                Consented write paths are not declared by the template's sandbox.allowed_paths: \(paths.joined(separator: ", ")).
                Only declared paths can be granted. Declared paths: \(declaredPaths.isEmpty ? "(none)" : declaredPaths.joined(separator: ", ")).
                Check for typos, or update the template's config.yml if the template should write there.
                """
            }
        }
    }
}

private struct RollbackManifest: Codable {
    let id: String
    let applyToken: String
    let templateName: String
    let workingDirectory: String
    /// `.applied` until rolled back, then `.rolledBack` — the same vocabulary
    /// as the transaction metadata's status. Legacy bundles without the field
    /// decode as nil and are treated as applied.
    var status: HatchTransactionMetadata.Status?
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
