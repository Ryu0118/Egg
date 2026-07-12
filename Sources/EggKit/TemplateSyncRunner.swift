import FileManagerProtocol
import Foundation
import Interaction

/// Runs the declarative template workflow for `egg template sync` and
/// `egg template update`.
///
/// Per scope (global/project): load eggs.yml → load eggs-lock.yml → resolve
/// each entry (lock-aware for sync, always fresh for update) → install the
/// entry's templates (manifest-managed templates are always overwritten;
/// templates not in the manifest are never touched) → regenerate the
/// lockfile from the manifest.
///
/// Entry failures do not abort the run: they aggregate into the result and
/// preserve the entry's previous lock pin, so a transient auth failure
/// cannot drop a pin.
package struct TemplateSyncRunner {
    /// Whether locked resolutions may be reused (`sync`) or everything
    /// re-resolves to the latest eligible version (`update`).
    package enum SyncMode {
        case sync
        case update
    }

    /// One manifest scope to process.
    package struct Scope {
        package let kind: TemplateLocationType.Kind
        package let manifestURL: URL
        package let lockfileURL: URL

        package init(kind: TemplateLocationType.Kind, manifestURL: URL, lockfileURL: URL) {
            self.kind = kind
            self.manifestURL = manifestURL
            self.lockfileURL = lockfileURL
        }
    }

    private let mode: SyncMode
    private let dryRun: Bool
    private let scopes: [Scope]
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let homeDirectory: URL
    private let fileManager: any FileManagerProtocol
    private let interaction: any InteractionProviding
    private let gitCloner: any GitCloning
    private let tagLister: any GitTagListing
    private let directoryCloner: any DirectoryCloning
    private let templateDiscoverer: any TemplateDiscovering
    private let templateLocation: TemplateLocation

    package init(
        mode: SyncMode,
        dryRun: Bool,
        scopes: [Scope],
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol = FileManager.default,
        interaction: some InteractionProviding = GuardedTerminal(),
        gitCloner: some GitCloning = GitCloner(),
        tagLister: some GitTagListing = GitTagLister(),
        directoryCloner: some DirectoryCloning = APFSDirectoryCloner(),
    ) {
        self.init(
            mode: mode,
            dryRun: dryRun,
            scopes: scopes,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            interaction: interaction,
            gitCloner: gitCloner,
            tagLister: tagLister,
            directoryCloner: directoryCloner,
            templateDiscoverer: TemplateDiscoverer(fileManager: fileManager),
        )
    }

    /// Internal initializer for testing with a custom template discoverer.
    init(
        mode: SyncMode,
        dryRun: Bool,
        scopes: [Scope],
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol,
        interaction: some InteractionProviding,
        gitCloner: some GitCloning,
        tagLister: some GitTagListing,
        directoryCloner: some DirectoryCloning,
        templateDiscoverer: some TemplateDiscovering,
    ) {
        self.mode = mode
        self.dryRun = dryRun
        self.scopes = scopes
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.interaction = interaction
        self.gitCloner = gitCloner
        self.tagLister = tagLister
        self.directoryCloner = directoryCloner
        self.templateDiscoverer = templateDiscoverer
        templateLocation = TemplateLocation(homeDirectory: homeDirectory)
    }

    /// Runs the workflow over every scope.
    ///
    /// - Throws: `ManifestLoaderError` / `LockfileError` for unreadable
    ///   manifests or lockfiles (user input to fix — not aggregated).
    package func run() async throws -> SyncResult {
        var scopeResults: [SyncScopeResult] = []
        for scope in scopes {
            try await scopeResults.append(processScope(scope))
        }
        return SyncResult(dryRun: dryRun, scopes: scopeResults)
    }

    // MARK: - Scope processing

    private func processScope(_ scope: Scope) async throws -> SyncScopeResult {
        let manifestPath = scope.manifestURL.path(percentEncoded: false)
        let lockfilePath = scope.lockfileURL.path(percentEncoded: false)
        let prefix = dryRun ? "[dry-run] " : ""
        interaction.writeInfo("\(prefix)Syncing \(scope.kind.rawValue) manifest: \(manifestPath)")

        let manifest = try ManifestLoader(fileManager: fileManager).load(manifestPath: scope.manifestURL)
        let lockStore = LockfileStore(fileManager: fileManager)
        let lockfile = try lockStore.load(lockfilePath: scope.lockfileURL)

        if manifest.templates.isEmpty {
            interaction.writeWarning("no templates declared in \(manifestPath); nothing to sync")
        }

        let location = scope.kind.toConcreteType(projectDirectory, workingDirectory: workingDirectory)
        // Template name → declared URL of the entry that installed it this
        // run. Manifest order wins on collisions.
        var claimedNames: [String: String] = [:]
        var entryResults: [SyncEntryResult] = []
        var newLockEntries: [LockedTemplate] = []

        for entry in manifest.templates {
            switch entry.source {
            case let .git(url, requirement):
                let (result, lockEntry) = await processGitEntry(
                    entry: entry,
                    url: url,
                    requirement: requirement,
                    lockfile: lockfile,
                    location: location,
                    claimedNames: &claimedNames,
                )
                entryResults.append(result)
                if let lockEntry {
                    newLockEntries.append(lockEntry)
                }

            case let .local(path):
                await entryResults.append(processLocalEntry(
                    entry: entry,
                    path: path,
                    manifestURL: scope.manifestURL,
                    location: location,
                    claimedNames: &claimedNames,
                ))
            }
        }

        // Regenerate the lock from the manifest: entries that left the
        // manifest drop out. Skip writing when there is nothing to record
        // and no stale lock to prune.
        var lockfileWritten = false
        if !dryRun, !newLockEntries.isEmpty || lockfile != nil {
            try lockStore.save(Lockfile(templates: newLockEntries), to: scope.lockfileURL)
            lockfileWritten = true
            interaction.writeInfo("Lockfile written: \(lockfilePath)")
        } else if dryRun {
            interaction.writeInfo("[dry-run] Lockfile NOT written.")
        }

        return SyncScopeResult(
            scope: scope.kind.rawValue,
            manifestPath: manifestPath,
            lockfilePath: lockfilePath,
            entries: entryResults,
            lockfileWritten: lockfileWritten,
        )
    }

    // MARK: - Git entries

    private func processGitEntry(
        entry: ManifestEntry,
        url: GitURL,
        requirement: VersionRequirement,
        lockfile: Lockfile?,
        location: TemplateLocationType,
        claimedNames: inout [String: String],
    ) async -> (SyncEntryResult, LockedTemplate?) {
        let lockKey = url.original
        let previousLockEntry = lockfile?.entry(forURL: lockKey)

        let resolution: Resolution
        do {
            resolution = try await resolve(
                requirement: requirement,
                url: url,
                locked: previousLockEntry?.resolved,
            )
        } catch {
            interaction.writeWarning("✘ \(entry.declaredURL): \(error.localizedDescription)")
            // Preserve the previous pin: a transient failure must not drop it.
            return (
                SyncEntryResult(
                    url: lockKey,
                    requirement: requirement.description,
                    failed: [SyncFailure(name: nil, error: error)],
                ),
                previousLockEntry,
            )
        }

        interaction.writeInfo("✔ \(entry.declaredURL)")
        let verb = dryRun ? "would resolve" : (resolution.reusedLock ? "reusing locked" : "resolved")
        interaction.writeInfo("    \(verb) \(describe(resolution)) for '\(requirement)'")

        let newLockEntry = LockedTemplate(
            url: lockKey,
            requirement: LockedRequirement(requirement),
            resolved: LockedResolution(
                version: resolution.version?.description,
                tag: resolution.tag,
                branch: resolution.branch,
                revision: resolution.revision,
            ),
        )

        if dryRun {
            return (gitEntryResult(lockKey: lockKey, requirement: requirement, resolution: resolution), newLockEntry)
        }

        do {
            let outcome = try await cloneAndInstall(
                url: url,
                resolution: resolution,
                entry: entry,
                location: location,
                claimedNames: &claimedNames,
            )
            return (
                gitEntryResult(lockKey: lockKey, requirement: requirement, resolution: resolution, outcome: outcome),
                newLockEntry,
            )
        } catch {
            interaction.writeWarning("✘ \(entry.declaredURL): \(error.localizedDescription)")
            // The remote could not be fetched at the resolved revision;
            // keep the previous pin rather than recording an uninstalled one.
            return (
                gitEntryResult(
                    lockKey: lockKey,
                    requirement: requirement,
                    resolution: resolution,
                    outcome: InstallOutcome(failed: [SyncFailure(name: nil, error: error)]),
                ),
                previousLockEntry,
            )
        }
    }

    private func cloneAndInstall(
        url: GitURL,
        resolution: Resolution,
        entry: ManifestEntry,
        location: TemplateLocationType,
        claimedNames: inout [String: String],
    ) async throws -> InstallOutcome {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "egg-sync-")
        defer { try? fileManager.removeItem(at: tempDir) }

        // Install from the exact resolved revision, not the tag/branch:
        // byte-exact reproducibility even if a tag is re-pointed upstream.
        try await gitCloner.clone(url: url, to: tempDir, ref: .revision(resolution.revision))
        return try await installTemplates(
            from: tempDir,
            entry: entry,
            location: location,
            claimedNames: &claimedNames,
        )
    }

    private func gitEntryResult(
        lockKey: String,
        requirement: VersionRequirement,
        resolution: Resolution,
        outcome: InstallOutcome = InstallOutcome(),
    ) -> SyncEntryResult {
        SyncEntryResult(
            url: lockKey,
            requirement: requirement.description,
            resolvedVersion: resolution.version?.description,
            resolvedRevision: resolution.revision,
            reusedLock: resolution.reusedLock,
            installed: outcome.installed,
            skipped: outcome.skipped,
            failed: outcome.failed,
        )
    }

    private func resolve(
        requirement: VersionRequirement,
        url: GitURL,
        locked: LockedResolution?,
    ) async throws -> Resolution {
        if mode == .sync,
           let reused = VersionResolver.reusableResolution(for: requirement, locked: locked)
        {
            return reused
        }

        switch requirement {
        case .from, .exact:
            let tags = try await tagLister.listTags(url: url)
            return try VersionResolver.resolve(requirement: requirement, tags: tags, url: url.original)

        case let .branch(name):
            guard let revision = try await tagLister.remoteBranchRevision(url: url, branch: name) else {
                throw ResolutionError.branchNotFound(url: url.original, branch: name)
            }
            return Resolution(revision: revision, branch: name)

        case let .revision(sha):
            return Resolution(revision: sha)
        }
    }

    // MARK: - Local entries

    private func processLocalEntry(
        entry: ManifestEntry,
        path: String,
        manifestURL: URL,
        location: TemplateLocationType,
        claimedNames: inout [String: String],
    ) async -> SyncEntryResult {
        if dryRun {
            interaction.writeInfo("✔ \(entry.declaredURL)")
            interaction.writeInfo("    would install from local path (not locked)")
            return SyncEntryResult(url: entry.declaredURL, requirement: nil)
        }

        do {
            // Relative paths resolve against the manifest's own directory,
            // so a dotfiles-managed global manifest can carry its templates.
            let sourceDirectory = try PathResolver.resolveToAbsoluteURL(
                path,
                workingDirectory: manifestURL.deletingLastPathComponent(),
                homeDirectory: homeDirectory,
            )
            interaction.writeInfo("✔ \(entry.declaredURL)")
            let outcome = try await installTemplates(
                from: sourceDirectory,
                entry: entry,
                location: location,
                claimedNames: &claimedNames,
            )
            return SyncEntryResult(
                url: entry.declaredURL,
                requirement: nil,
                installed: outcome.installed,
                skipped: outcome.skipped,
                failed: outcome.failed,
            )
        } catch {
            interaction.writeWarning("✘ \(entry.declaredURL): \(error.localizedDescription)")
            return SyncEntryResult(
                url: entry.declaredURL,
                requirement: nil,
                failed: [SyncFailure(name: nil, error: error)],
            )
        }
    }

    // MARK: - Installation

    private struct InstallOutcome {
        var installed: [String] = []
        var skipped: [SkippedTemplate] = []
        var failed: [SyncFailure] = []
    }

    private func installTemplates(
        from sourceDirectory: URL,
        entry: ManifestEntry,
        location: TemplateLocationType,
        claimedNames: inout [String: String],
    ) async throws -> InstallOutcome {
        let templates = try await templateDiscoverer.discoverTemplates(in: sourceDirectory)
        guard !templates.isEmpty else {
            throw Error.noTemplatesFound(url: entry.declaredURL)
        }

        let destinationDir = templateLocation.templateDir(for: location)
        if !fileManager.existsAsLink(destinationDir) {
            try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }

        var outcome = InstallOutcome()
        for template in templates {
            guard entry.filter.shouldInclude(template.name) else {
                outcome.skipped.append(SkippedTemplate(name: template.name, reason: .excludedByFilter))
                interaction.writeWarning("    Skipped '\(template.name)': excluded by filter")
                continue
            }

            if let winner = claimedNames[template.name] {
                let error = Error.nameCollision(name: template.name, winnerURL: winner, loserURL: entry.declaredURL)
                outcome.failed.append(SyncFailure(name: template.name, error: error))
                interaction.writeWarning("    \(error.localizedDescription)")
                continue
            }

            do {
                let destination = templateLocation.template(template.name, type: location)
                // Manifest-managed templates are always overwritten: the
                // manifest is the declared source of truth for these names.
                let existed = fileManager.existsAsLink(destination)
                if existed {
                    try fileManager.removeItem(at: destination)
                }
                try await directoryCloner.clone(from: template.sourceDirectory, to: destination)
                claimedNames[template.name] = entry.declaredURL
                outcome.installed.append(template.name)
                interaction.writeSuccess("    Installed '\(template.name)'\(existed ? " (overwritten)" : "")")
            } catch {
                outcome.failed.append(SyncFailure(name: template.name, error: error))
                interaction.writeWarning("    Failed to install '\(template.name)': \(error.localizedDescription)")
            }
        }
        return outcome
    }

    private func describe(_ resolution: Resolution) -> String {
        if let version = resolution.version {
            let tagSuffix = resolution.tag.map { " (tag \($0))" } ?? ""
            return "\(version)\(tagSuffix)"
        }
        if let branch = resolution.branch {
            return "branch '\(branch)' at \(resolution.revision.prefix(7))"
        }
        return "revision \(resolution.revision.prefix(7))"
    }
}

package extension TemplateSyncRunner {
    /// Errors surfaced as per-entry / per-template failures during sync.
    enum Error: LocalizedError, Equatable {
        /// The resolved source contains no valid egg templates.
        case noTemplatesFound(url: String)
        /// Two manifest entries provide a template with the same name.
        /// Manifest order wins; the later entry's template is not installed.
        case nameCollision(name: String, winnerURL: String, loserURL: String)

        package var errorDescription: String? {
            switch self {
            case let .noTemplatesFound(url):
                "no valid templates found in '\(url)'. egg looks for <root>/config.yml, <root>/<name>/config.yml, and <root>/.eggs/<name>/config.yml."
            case let .nameCollision(name, winnerURL, loserURL):
                "template '\(name)' from \(loserURL) conflicts with the same name already installed by \(winnerURL) (first entry in eggs.yml wins). Use 'only:'/'exclude:' to disambiguate."
            }
        }
    }
}
