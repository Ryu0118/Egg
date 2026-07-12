import Foundation

/// Computes the eggs.yml / eggs-lock.yml locations for both manifest scopes.
///
/// - Global: `$XDG_CONFIG_HOME/egg/eggs.yml`, falling back to
///   `~/.config/egg/eggs.yml` — dotfiles-friendly.
/// - Project: `<projectDirectory>/eggs.yml`.
package struct ManifestLocator {
    private let environment: [String: String]

    package init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    /// The global manifest location, honoring `XDG_CONFIG_HOME`.
    package func globalManifestURL(homeDirectory: URL) -> URL {
        let configDirectory: URL = if let xdgConfigHome = environment["XDG_CONFIG_HOME"], !xdgConfigHome.isEmpty {
            URL(filePath: xdgConfigHome, directoryHint: .isDirectory)
        } else {
            homeDirectory.appending(path: ".config", directoryHint: .isDirectory)
        }
        return configDirectory
            .appending(path: "egg", directoryHint: .isDirectory)
            .appending(path: "eggs.yml")
    }

    /// The project manifest location at the project root.
    package func projectManifestURL(projectDirectory: URL) -> URL {
        projectDirectory.appending(path: "eggs.yml")
    }

    /// The lockfile sits next to its manifest.
    package static func lockfileURL(forManifestAt manifestURL: URL) -> URL {
        manifestURL.deletingLastPathComponent().appending(path: "eggs-lock.yml")
    }
}
