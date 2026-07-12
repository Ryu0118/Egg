import FileManagerProtocol
import Foundation

/// Which manifest scopes a sync/update run should process.
package enum ManifestScopeSelection: Equatable {
    /// Every scope whose manifest exists (global and/or project).
    case all
    case global
    case project
}

/// Resolves manifest scope selections into concrete
/// ``TemplateSyncRunner/Scope`` values, enforcing the existence rules:
/// an explicitly requested scope must have a manifest; the default
/// selection requires at least one.
package enum ManifestScopeResolver {
    package static func resolve(
        selection: ManifestScopeSelection,
        projectDirectory: URL,
        homeDirectory: URL,
        fileManager: any FileManagerProtocol,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) throws -> [TemplateSyncRunner.Scope] {
        let locator = ManifestLocator(environment: environment)
        let globalManifestURL = locator.globalManifestURL(homeDirectory: homeDirectory)
        let projectManifestURL = locator.projectManifestURL(projectDirectory: projectDirectory)

        func scope(_ kind: TemplateLocationType.Kind, _ manifestURL: URL) -> TemplateSyncRunner.Scope {
            TemplateSyncRunner.Scope(
                kind: kind,
                manifestURL: manifestURL,
                lockfileURL: ManifestLocator.lockfileURL(forManifestAt: manifestURL),
            )
        }

        switch selection {
        case .global:
            guard fileManager.exists(globalManifestURL) else {
                throw ManifestScopeError.scopeManifestNotFound(
                    scope: "global",
                    path: globalManifestURL.path(percentEncoded: false),
                )
            }
            return [scope(.global, globalManifestURL)]

        case .project:
            guard fileManager.exists(projectManifestURL) else {
                throw ManifestScopeError.scopeManifestNotFound(
                    scope: "project",
                    path: projectManifestURL.path(percentEncoded: false),
                )
            }
            return [scope(.project, projectManifestURL)]

        case .all:
            var scopes: [TemplateSyncRunner.Scope] = []
            if fileManager.exists(globalManifestURL) {
                scopes.append(scope(.global, globalManifestURL))
            }
            if fileManager.exists(projectManifestURL) {
                scopes.append(scope(.project, projectManifestURL))
            }
            guard !scopes.isEmpty else {
                throw ManifestScopeError.noManifestFound(searchedPaths: [
                    globalManifestURL.path(percentEncoded: false),
                    projectManifestURL.path(percentEncoded: false),
                ])
            }
            return scopes
        }
    }
}

/// Errors resolving which manifests to process.
package enum ManifestScopeError: Error, LocalizedError, Equatable {
    /// An explicitly requested scope has no manifest.
    case scopeManifestNotFound(scope: String, path: String)
    /// The default selection found no manifest in any scope.
    case noManifestFound(searchedPaths: [String])

    package var errorDescription: String? {
        switch self {
        case let .scopeManifestNotFound(scope, path):
            "no \(scope) manifest found at \(path)"
        case let .noManifestFound(searchedPaths):
            "no manifest found. Searched: \(searchedPaths.joined(separator: ", "))"
        }
    }
}
