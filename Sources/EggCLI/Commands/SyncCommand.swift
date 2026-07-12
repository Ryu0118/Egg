import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation

package extension EggCommand.TemplateCommand {
    struct SyncCommand: AsyncParsableCommand, HasProjectDirectory {
        @Flag(name: .long, help: "Sync only the global manifest ($XDG_CONFIG_HOME/egg/egg.yml).")
        package var global: Bool = false

        @Flag(name: .long, help: "Sync only the project manifest (./egg.yml).")
        package var project: Bool = false

        @Flag(name: .long, help: "Resolve versions and report without installing or writing the lockfile.")
        package var dryRun: Bool = false

        @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of the human-readable output.")
        package var json: Bool = false

        @Option(name: .long, help: "Project directory.", completion: .directory)
        package var projectDirectory: String?

        package static let configuration = CommandConfiguration(
            commandName: "sync",
            abstract: "Install templates declared in egg.yml, honoring egg-lock.yml.",
            discussion: """
            Reads the manifest(s) and installs every declared template:

              Global:  $XDG_CONFIG_HOME/egg/egg.yml (default ~/.config/egg/egg.yml) → ~/.eggs
              Project: ./egg.yml → ./.eggs

            By default both manifests are synced when they exist. Locked
            resolutions are reused while they satisfy the manifest (like
            Package.resolved); use 'egg template update' to move to the
            latest eligible versions. Templates not declared in a manifest
            are never touched.

            Example manifest:

              templates:
                - url: owner/repo            # GitHub shorthand
                  from: "1.0.0"              # upToNextMajor range
                - url: git@github.com:owner/private.git
                  branch: main
                - url: ./local-templates     # never locked
            """,
        )

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws {
            try await ManifestSyncCLI.run(
                mode: .sync,
                global: global,
                project: project,
                dryRun: dryRun,
                json: json,
                projectDirectory: resolveProjectDirectory(),
                fileManager: Self.fileManager,
            )
        }
    }
}

/// Shared implementation for `egg template sync` and `egg template update`;
/// the two commands differ only in the runner mode.
enum ManifestSyncCLI {
    static func run(
        mode: TemplateSyncRunner.SyncMode,
        global: Bool,
        project: Bool,
        dryRun: Bool,
        json: Bool,
        projectDirectory: URL,
        fileManager: any FileManagerProtocol,
    ) async throws {
        // --global and --project together mean both, same as the default.
        let selection: ManifestScopeSelection = global == project ? .all : (global ? .global : .project)

        if json {
            let service = EggService(
                fileManager: fileManager,
                projectDirectory: projectDirectory,
                homeDirectory: CLIEnvironment.resolveHomeDirectory(),
            )
            // EggService keeps strings at its boundary (like installTemplates'
            // location) because MCP callers arrive with strings.
            let scope: String? = switch selection {
            case .all: nil
            case .global: "global"
            case .project: "project"
            }
            let result: SyncResult = switch mode {
            case .sync:
                try await service.syncTemplates(scope: scope, dryRun: dryRun)
            case .update:
                try await service.updateTemplates(scope: scope, dryRun: dryRun)
            }
            try CLIOutput.printJSON(result.encoded)
            if result.hasFailures {
                throw ExitCode.failure
            }
            return
        }

        do {
            let homeDirectory = CLIEnvironment.resolveHomeDirectory()
            let scopes = try ManifestScopeResolver.resolve(
                selection: selection,
                projectDirectory: projectDirectory,
                homeDirectory: homeDirectory,
                fileManager: fileManager,
            )

            let result = try await TemplateSyncRunner(
                mode: mode,
                dryRun: dryRun,
                scopes: scopes,
                projectDirectory: projectDirectory,
                workingDirectory: URL(filePath: fileManager.currentDirectoryPath),
                homeDirectory: homeDirectory,
                fileManager: fileManager,
            ).run()

            displaySyncSummary(result)
            if result.hasFailures {
                throw ExitCode.failure
            }
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            CLIOutput.printError(error.localizedDescription)
            throw ExitCode.failure
        }
    }

    private static func displaySyncSummary(_ result: SyncResult) {
        let entries = result.scopes.flatMap(\.entries)
        let installedCount = entries.reduce(0) { $0 + $1.installed.count }
        let skippedCount = entries.reduce(0) { $0 + $1.skipped.count }
        let failedSourceCount = entries.count { !$0.failed.isEmpty }

        if result.dryRun {
            CLIOutput.printWarning("[dry-run] Resolution only; no templates were installed.")
        } else {
            let skippedSuffix = skippedCount > 0 ? " (\(skippedCount) skipped)" : ""
            CLIOutput.printSuccess("Synced \(installedCount) template(s)\(skippedSuffix).")
        }

        if failedSourceCount > 0 {
            CLIOutput.printError("\(failedSourceCount) source(s) failed.")
        }
    }
}
