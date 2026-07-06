import FileManagerProtocol
import Foundation
import Yams

/// A protocol for discovering templates in a template source directory.
protocol TemplateDiscovering {
    /// Discovers valid templates in the given source directory.
    ///
    /// - Parameter repositoryDirectory: The root of a cloned repository or a local path
    /// - Returns: A list of valid discovered templates
    /// - Throws: When the directory can't be read, or when the directory
    ///   itself is a template whose config is broken
    func discoverTemplates(in repositoryDirectory: URL) async throws -> [DiscoveredTemplate]
}

/// Discovers templates in a source directory (a cloned Git repository or a
/// local path) by scanning for valid `config.yml` files.
///
/// Three layouts are recognized:
/// 1. The directory itself is a template (`<dir>/config.yml`) — the same
///    shape `template validate <dir>` accepts. It is named by its declared
///    `config.name`, since a git clone's on-disk basename is a temp path.
///    A broken config here throws with the decode/validation message: the
///    caller pointed directly at this template, so skipping it silently
///    would misreport the problem as "no templates found".
/// 2. Each immediate subdirectory containing a `config.yml`, named by the
///    subdirectory. Invalid entries are skipped — a repository of templates
///    shouldn't fail wholesale over one broken entry.
/// 3. Subdirectories of `<dir>/.eggs` — egg's own project-local template
///    convention, so a project checkout can be installed from directly.
///
/// Hidden directories (starting with `.`) and common non-template directories
/// are automatically excluded from the subdirectory scans.
struct TemplateDiscoverer: TemplateDiscovering {
    private let fileManager: any FileManagerProtocol
    private let validator = ConfigValidator()
    private let decoder = YAMLDecoder()

    /// Directories to exclude from template discovery
    private static let excludedDirectories: Set<String> = [
        ".git",
        ".github",
        ".gitlab",
        ".bitbucket",
        "node_modules",
        ".vscode",
        ".idea",
    ]

    init(fileManager: some FileManagerProtocol = FileManager.default) {
        self.fileManager = fileManager
    }

    func discoverTemplates(in repositoryDirectory: URL) async throws -> [DiscoveredTemplate] {
        // Layout 1: the directory itself is a template.
        let rootConfigPath = repositoryDirectory.appendingPathComponent("config.yml")
        if fileManager.exists(rootConfigPath) {
            return try await [rootTemplate(directory: repositoryDirectory, configPath: rootConfigPath)]
        }

        // Layout 2: one template per subdirectory.
        var templates = try await validTemplatesInSubdirectories(of: repositoryDirectory)

        // Layout 3: egg's project-local convention, <dir>/.eggs/<name>/.
        let eggsDirectory = repositoryDirectory.appendingPathComponent(".eggs")
        if isDirectory(eggsDirectory) {
            templates += try await validTemplatesInSubdirectories(of: eggsDirectory)
        }

        return templates
    }

    /// The template at `directory` itself, or a thrown error explaining why
    /// its config doesn't decode or validate.
    private func rootTemplate(directory: URL, configPath: URL) async throws -> DiscoveredTemplate {
        do {
            let data = try fileManager.readFile(at: configPath)
            let config = try decoder.decode(Config.self, from: data)
            try await validator.validate(config)
            return DiscoveredTemplate(
                name: config.name,
                sourceDirectory: directory,
                config: config,
            )
        } catch let error as DecodingError {
            throw Error.invalidTemplate(
                path: directory.path(percentEncoded: false),
                reason: ConfigDecodingErrorFormatter.message(for: error),
            )
        } catch {
            throw Error.invalidTemplate(
                path: directory.path(percentEncoded: false),
                reason: error.localizedDescription,
            )
        }
    }

    /// Valid templates found one level below `parent`, named by their
    /// subdirectory. Invalid entries are skipped so one broken template
    /// doesn't fail a whole repository install.
    private func validTemplatesInSubdirectories(of parent: URL) async throws -> [DiscoveredTemplate] {
        var templates: [DiscoveredTemplate] = []

        let contents = try fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
        )

        for itemURL in contents {
            // Skip if not a directory
            guard isDirectory(itemURL) else {
                continue
            }

            let directoryName = itemURL.lastPathComponent

            // Skip hidden directories (starting with .)
            guard !directoryName.hasPrefix(".") else {
                continue
            }

            // Skip excluded directories
            guard !Self.excludedDirectories.contains(directoryName) else {
                continue
            }

            // Check for config.yml
            let configPath = itemURL.appendingPathComponent("config.yml")
            guard fileManager.exists(configPath) else {
                continue
            }

            // Try to parse and validate the template
            if let template = await parseAndValidateTemplate(
                directory: itemURL,
                configPath: configPath,
                name: directoryName,
            ) {
                templates.append(template)
            }
        }

        return templates
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func parseAndValidateTemplate(
        directory: URL,
        configPath: URL,
        name: String,
    ) async -> DiscoveredTemplate? {
        do {
            let data = try fileManager.readFile(at: configPath)
            let config = try decoder.decode(Config.self, from: data)
            try await validator.validate(config)

            return DiscoveredTemplate(
                name: name,
                sourceDirectory: directory,
                config: config,
            )
        } catch {
            // Invalid template, skip silently
            // Errors are expected for invalid configs
            return nil
        }
    }

    enum Error: LocalizedError {
        case invalidTemplate(path: String, reason: String)

        var errorDescription: String? {
            switch self {
            case let .invalidTemplate(path, reason):
                "Template at \(path) is not installable: \(reason)"
            }
        }
    }
}
