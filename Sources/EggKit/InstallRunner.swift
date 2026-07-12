import FileManagerProtocol
import Foundation
import Interaction

/// Runs the template installation workflow.
///
/// Supports two modes:
/// - **Interactive mode**: Prompts the user for repository URL, ref, location, and template selection
/// - **Direct mode**: Uses all parameters provided via command-line arguments
///
/// The installation workflow:
/// 1. Clone the Git repository to a temporary directory
/// 2. Discover valid templates in the repository
/// 3. Apply the template filter (include/exclude)
/// 4. Copy each template to the destination using APFS cloning
/// 5. Clean up the temporary directory
package struct InstallRunner {
    private let mode: InstallRunnerMode
    private let force: Bool
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let homeDirectory: URL
    private let templateLocation: TemplateLocation
    private let fileManager: any FileManagerProtocol
    private let interaction: any InteractionProviding
    private let gitCloner: any GitCloning
    private let directoryCloner: any DirectoryCloning
    private let templateDiscoverer: any TemplateDiscovering
    private let gitTagLister: any GitTagListing
    private let manifestLocator: ManifestLocator
    private let manifestLoader: ManifestLoader
    private let manifestWriter: ManifestWriter
    private let lockfileStore: LockfileStore

    /// Creates a new InstallRunner.
    ///
    /// - Parameters:
    ///   - mode: The runner mode (interactive or direct)
    ///   - force: Whether to overwrite existing templates
    ///   - projectDirectory: The project directory path
    ///   - workingDirectory: The current working directory
    ///   - homeDirectory: The user's home directory
    ///   - fileManager: File manager for file operations
    ///   - interaction: CLI interaction handler
    ///   - gitCloner: Git cloning implementation
    ///   - directoryCloner: Directory cloning implementation
    ///   - gitTagLister: Lists remote tags, used to resolve a `--tag`
    ///     install's commit SHA for manifest registration without an extra
    ///     clone
    package init(
        mode: InstallRunnerMode,
        force: Bool,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol = FileManager.default,
        interaction: some InteractionProviding = GuardedTerminal(),
        gitCloner: some GitCloning = GitCloner(),
        directoryCloner: some DirectoryCloning = APFSDirectoryCloner(),
        gitTagLister: some GitTagListing = GitTagLister(),
    ) {
        self.mode = mode
        self.force = force
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.interaction = interaction
        self.gitCloner = gitCloner
        self.directoryCloner = directoryCloner
        self.gitTagLister = gitTagLister
        templateDiscoverer = TemplateDiscoverer(fileManager: fileManager)
        templateLocation = TemplateLocation(homeDirectory: homeDirectory)
        manifestLocator = ManifestLocator()
        manifestLoader = ManifestLoader(fileManager: fileManager)
        manifestWriter = ManifestWriter(fileManager: fileManager)
        lockfileStore = LockfileStore(fileManager: fileManager)
    }

    /// Internal initializer for testing with custom template discoverer.
    init(
        mode: InstallRunnerMode,
        force: Bool,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol,
        interaction: some InteractionProviding = GuardedTerminal(),
        gitCloner: some GitCloning,
        directoryCloner: some DirectoryCloning,
        templateDiscoverer: some TemplateDiscovering,
        gitTagLister: some GitTagListing = GitTagLister(),
    ) {
        self.mode = mode
        self.force = force
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.interaction = interaction
        self.gitCloner = gitCloner
        self.directoryCloner = directoryCloner
        self.templateDiscoverer = templateDiscoverer
        self.gitTagLister = gitTagLister
        templateLocation = TemplateLocation(homeDirectory: homeDirectory)
        manifestLocator = ManifestLocator()
        manifestLoader = ManifestLoader(fileManager: fileManager)
        manifestWriter = ManifestWriter(fileManager: fileManager)
        lockfileStore = LockfileStore(fileManager: fileManager)
    }

    /// Runs the installation workflow.
    ///
    /// - Returns: The installation result
    /// - Throws: `Error` if a fatal error occurs
    package func run() async throws -> InstallResult {
        switch mode {
        case .interactive:
            return try await runInteractiveMode()
        case let .direct(source, locationKind, filter):
            let location = locationKind.toConcreteType(projectDirectory, workingDirectory: workingDirectory)
            return try await runDirectMode(source: source, locationKind: locationKind, location: location, filter: filter)
        }
    }

    private func runInteractiveMode() async throws -> InstallResult {
        // Prompt for repository URL
        let urlString = await interaction.textPrompt(
            title: "Repository URL",
            prompt: "Enter the Git repository URL:",
            description: "HTTPS (https://...) or SSH (git@...) URL of the repository",
        )

        guard let gitURL = GitURLParser().parse(urlString) else {
            throw Error.invalidURL(urlString)
        }

        // Prompt for ref (optional)
        let ref = await promptForRef()

        // Prompt for location
        let location = promptForLocation()

        // Prompt for filter - we'll do this after discovering templates
        // Clone and discover first
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "egg-install-")
        defer { try? fileManager.removeItem(at: tempDir) }

        interaction.writeInfo("Cloning repository...")
        try await gitCloner.clone(url: gitURL, to: tempDir, ref: ref)

        interaction.writeInfo("Discovering templates...")
        let allTemplates = try await templateDiscoverer.discoverTemplates(in: tempDir)

        guard !allTemplates.isEmpty else {
            throw Error.noTemplatesFound(source: .git(url: gitURL, ref: ref))
        }

        // Prompt for template selection
        let selectedTemplates = promptForTemplateSelection(allTemplates)

        guard !selectedTemplates.isEmpty else {
            return InstallResult(installed: [], skipped: [], failed: [])
        }

        // Install selected templates
        return try await installTemplates(selectedTemplates, to: location)
    }

    private func promptForRef() async -> GitRef? {
        let options = ["Default branch", "Specific branch", "Tag", "Commit SHA"]
        let selected = interaction.singleChoicePrompt(
            title: "Git Reference",
            question: "Which reference would you like to use?",
            options: options,
            description: "Select how to specify the version",
        )

        switch selected {
        case "Default branch":
            return nil
        case "Specific branch":
            let branch = await interaction.textPrompt(
                title: "Branch Name",
                prompt: "Enter the branch name:",
                description: "The branch to clone from",
            )
            return .branch(branch)
        case "Tag":
            let tag = await interaction.textPrompt(
                title: "Tag Name",
                prompt: "Enter the tag name:",
                description: "The tag to clone from",
            )
            return .tag(tag)
        case "Commit SHA":
            let sha = await interaction.textPrompt(
                title: "Commit SHA",
                prompt: "Enter the commit SHA:",
                description: "The commit to checkout",
            )
            return .revision(sha)
        default:
            return nil
        }
    }

    private func promptForLocation() -> TemplateLocationType {
        let globalOption = TemplateLocationType.global
        let projectOption = TemplateLocationType.project(projectDirectory, workingDirectory: workingDirectory)

        return interaction.singleChoicePrompt(
            title: "Installation Location",
            question: "Where would you like to install the templates?",
            options: [globalOption, projectOption],
            description: "Select the installation location",
        )
    }

    private func promptForTemplateSelection(_ templates: [DiscoveredTemplate]) -> [DiscoveredTemplate] {
        let templateNames = templates.map(\.name)

        let selectedNames = interaction.multipleChoicePrompt(
            title: "Select Templates",
            question: "Which templates would you like to install?",
            options: templateNames,
            description: "Select the templates to install",
        )

        return templates.filter { selectedNames.contains($0.name) }
    }

    private func runDirectMode(
        source: TemplateSource,
        locationKind: TemplateLocationType.Kind,
        location: TemplateLocationType,
        filter: TemplateFilter,
    ) async throws -> InstallResult {
        let templatesDirectory: URL
        var cleanupDirectory: URL?

        switch source {
        case let .git(url, ref):
            // Clone repository to temporary directory
            let tempDir = try fileManager.makeTemporaryDirectory(prefix: "egg-install-")
            cleanupDirectory = tempDir

            interaction.writeInfo("Cloning repository...")
            try await gitCloner.clone(url: url, to: tempDir, ref: ref)

            templatesDirectory = tempDir

        case let .local(path):
            // Use local path directly
            interaction.writeInfo("Using local path: \(path.path(percentEncoded: false))")
            templatesDirectory = path
        }

        defer {
            if let cleanupDirectory {
                try? fileManager.removeItem(at: cleanupDirectory)
            }
        }

        interaction.writeInfo("Discovering templates...")
        let allTemplates = try await templateDiscoverer.discoverTemplates(in: templatesDirectory)

        guard !allTemplates.isEmpty else {
            throw Error.noTemplatesFound(source: source)
        }

        // Apply filter and track skipped templates
        var templatesToInstall: [DiscoveredTemplate] = []
        var skippedByFilter: [SkippedTemplate] = []

        for template in allTemplates {
            if filter.shouldInclude(template.name) {
                templatesToInstall.append(template)
            } else {
                skippedByFilter.append(SkippedTemplate(name: template.name, reason: .excludedByFilter))
            }
        }

        // Install filtered templates
        var result = try await installTemplates(templatesToInstall, to: location)

        // Add filter-skipped templates to the result
        result = InstallResult(
            installed: result.installed,
            skipped: result.skipped + skippedByFilter,
            failed: result.failed,
        )

        // Global git-source installs that landed at least one template
        // register themselves into the global manifest, so `sync`/`update`
        // pick them up going forward. Must run before the temp-dir cleanup
        // `defer` above fires, since resolving a floating ref's SHA reads
        // the clone at `templatesDirectory`.
        if locationKind == .global, case let .git(url, ref) = source, !result.installed.isEmpty {
            let manifestPath = manifestLocator.globalManifestURL(homeDirectory: homeDirectory)
            do {
                let manifestPath = try await registerGlobalInstall(
                    url: url,
                    ref: ref,
                    filter: filter,
                    clonedDirectory: templatesDirectory,
                    manifestPath: manifestPath,
                )
                result = InstallResult(
                    installed: result.installed,
                    skipped: result.skipped,
                    failed: result.failed,
                    manifestUpdated: manifestPath,
                )
                interaction.writeSuccess("Registered in \(manifestPath)")
            } catch {
                interaction.writeWarning("Installed, but failed to register in \(manifestPath.path(percentEncoded: false)): \(error.localizedDescription)")
            }
        }

        return result
    }

    /// Resolves the requirement to record for a global git install and
    /// upserts it into the manifest and lockfile.
    ///
    /// - Returns: The manifest path, for the caller's success message.
    private func registerGlobalInstall(
        url: GitURL,
        ref: GitRef?,
        filter: TemplateFilter,
        clonedDirectory: URL,
        manifestPath: URL,
    ) async throws -> String {
        let (requirement, revision) = try await resolveRequirement(url: url, ref: ref, clonedDirectory: clonedDirectory)

        let entry = ManifestEntry(
            declaredURL: url.original,
            source: .git(url: url, requirement: requirement),
            filter: filter,
        )
        let manifest = (try? manifestLoader.load(manifestPath: manifestPath)) ?? Manifest(templates: [])
        try manifestWriter.save(manifest.upserting(entry), to: manifestPath)

        let lockfilePath = ManifestLocator.lockfileURL(forManifestAt: manifestPath)
        let resolved = switch requirement {
        case let .exact(version):
            LockedResolution(version: version.description, tag: version.description, revision: revision)
        case let .branch(name):
            LockedResolution(branch: name, revision: revision)
        case .revision, .from:
            LockedResolution(revision: revision)
        }
        let lockedTemplate = LockedTemplate(
            url: url.original,
            requirement: LockedRequirement(requirement),
            resolved: resolved,
        )
        let lockfile = (try? lockfileStore.load(lockfilePath: lockfilePath)) ?? Lockfile(templates: [])
        try lockfileStore.save(lockfile.upserting(lockedTemplate), to: lockfilePath)

        return manifestPath.path(percentEncoded: false)
    }

    /// Maps the install's `ref` onto the requirement to record in the
    /// manifest, alongside the resolved commit SHA to lock: a tag becomes
    /// `exact:` when it parses as SemVer, otherwise (or with no ref at all)
    /// a resolved commit SHA becomes `revision:`, and a branch is recorded
    /// as-is (matching sync/update's floating semantics).
    private func resolveRequirement(
        url: GitURL,
        ref: GitRef?,
        clonedDirectory: URL,
    ) async throws -> (requirement: VersionRequirement, revision: String) {
        switch ref {
        case let .branch(name):
            let revision = try await gitCloner.headRevision(at: clonedDirectory)
            return (.branch(name), revision)
        case let .tag(name):
            let revision = try await resolvedTagRevision(named: name, url: url, clonedDirectory: clonedDirectory)
            if let (version, _) = SemanticVersion.parse(tag: name) {
                return (.exact(version), revision)
            }
            return (.revision(revision), revision)
        case let .revision(sha):
            return (.revision(sha), sha)
        case nil:
            let revision = try await gitCloner.headRevision(at: clonedDirectory)
            return (.revision(revision), revision)
        }
    }

    /// Resolves a tag's commit SHA, preferring a remote `ls-remote` lookup
    /// (no extra clone) and falling back to the local checkout's HEAD when
    /// the tag isn't found that way.
    private func resolvedTagRevision(named name: String, url: GitURL, clonedDirectory: URL) async throws -> String {
        if let revision = try await tagRevision(named: name, url: url) {
            return revision
        }
        return try await gitCloner.headRevision(at: clonedDirectory)
    }

    /// Looks up a tag's resolved commit SHA from the remote without an
    /// extra clone, falling back to `nil` (letting the caller use the local
    /// checkout's HEAD instead) if the tag can't be found this way.
    private func tagRevision(named name: String, url: GitURL) async throws -> String? {
        let tags = try await gitTagLister.listTags(url: url)
        return tags.first { $0.name == name }?.revision
    }

    private func installTemplates(
        _ templates: [DiscoveredTemplate],
        to location: TemplateLocationType,
    ) async throws -> InstallResult {
        var installed: [String] = []
        var skipped: [SkippedTemplate] = []
        var failed: [FailedTemplate] = []

        // Ensure destination directory exists
        let destinationDir = templateLocation.templateDir(for: location)
        if !fileManager.existsAsLink(destinationDir) {
            try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }

        for template in templates {
            let destinationPath = templateLocation.template(template.name, type: location)
            // existsAsLink, not fileExists: a dangling symlink already sitting
            // at the destination must be recognized so it's cleared (with
            // --force) rather than making clonefile fail with EEXIST while
            // --force silently has no effect.
            let destinationExists = fileManager.existsAsLink(destinationPath)

            if destinationExists, !force {
                skipped.append(SkippedTemplate(name: template.name, reason: .alreadyExists))
                interaction.writeWarning("Skipped '\(template.name)': already exists (use --force to overwrite)")
                continue
            }

            do {
                if destinationExists {
                    try fileManager.removeItem(at: destinationPath)
                }
                try await directoryCloner.clone(from: template.sourceDirectory, to: destinationPath)
                installed.append(template.name)
                let suffix = destinationExists ? " (overwritten)" : ""
                interaction.writeSuccess("Installed '\(template.name)'\(suffix)")
            } catch {
                failed.append(FailedTemplate(name: template.name, error: error))
                interaction.writeWarning("Failed to install '\(template.name)': \(error.localizedDescription)")
            }
        }

        return InstallResult(installed: installed, skipped: skipped, failed: failed)
    }
}

extension InstallRunner {
    /// Errors that can occur during template installation.
    enum Error: LocalizedError, Equatable {
        /// The provided URL is not a valid Git URL
        case invalidURL(String)
        /// No valid templates were found in the source
        case noTemplatesFound(source: TemplateSource)

        var errorDescription: String? {
            switch self {
            case let .invalidURL(url):
                "Invalid Git URL: \(url)"
            case let .noTemplatesFound(source):
                switch source {
                case let .git(url, _):
                    "No valid templates found in repository: \(url.original). egg looks for <root>/config.yml, <root>/<name>/config.yml, and <root>/.eggs/<name>/config.yml."
                case let .local(path):
                    "No valid templates found in directory: \(path.path(percentEncoded: false)). egg looks for <dir>/config.yml, <dir>/<name>/config.yml, and <dir>/.eggs/<name>/config.yml."
                }
            }
        }
    }
}
