import FileManagerProtocol
import Foundation
import Yams

/// A protocol for discovering templates in a cloned Git repository.
protocol TemplateDiscovering {
    /// Discovers valid templates in the given repository directory.
    ///
    /// Scans subdirectories for `config.yml` files and validates them.
    /// Invalid templates are skipped (not included in the result).
    ///
    /// - Parameter repositoryDirectory: The root directory of the cloned repository
    /// - Returns: A list of valid discovered templates
    /// - Throws: Only throws for fatal errors (e.g., directory access issues)
    func discoverTemplates(in repositoryDirectory: URL) async throws -> [DiscoveredTemplate]
}

/// Discovers templates in a cloned Git repository by scanning for valid `config.yml` files.
///
/// Templates are discovered by:
/// 1. Listing subdirectories in the repository root
/// 2. Checking each subdirectory for a `config.yml` file
/// 3. Validating the configuration using `ConfigValidator`
/// 4. Returning only valid templates
///
/// Hidden directories (starting with `.`) and common non-template directories
/// are automatically excluded from the scan.
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
        var templates: [DiscoveredTemplate] = []

        let contents = try fileManager.contentsOfDirectory(
            at: repositoryDirectory,
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
}
