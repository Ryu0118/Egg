import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation

/// Shared option set for resolving where a hatch transaction operates.
///
/// Every transaction subcommand needs the same project/working-directory and
/// template-search resolution, so it lives here instead of being repeated.
struct HatchTransactionOptions: ParsableArguments {
    @Option(name: .long, help: "Directory where project templates are located (defaults to current directory).", completion: .directory)
    var projectDirectory: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Additional directories to search for templates.", completion: .directory)
    var templateSearchPaths: [String] = []

    static let fileManager: any FileManagerProtocol = FileManager.default

    func makeService() async throws -> MCPService {
        try await MCPService(
            fileManager: Self.fileManager,
            workingDirectory: URL(filePath: Self.fileManager.currentDirectoryPath),
            projectDirectory: resolveProjectDirectory(),
            homeDirectory: CLIEnvironment.resolveHomeDirectory(),
            additionalSearchPaths: resolveTemplateSearchPaths(),
        )
    }
}

extension HatchTransactionOptions: HasProjectDirectory, HasTemplateSearchPaths {}

/// `egg hatch preview` — run a template in a staging clone and emit the proposed
/// changes plus an apply token as JSON, without touching the working directory.
struct HatchPreviewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preview",
        abstract: "Preview a hatch as a transaction; emits JSON with an apply token.",
        discussion: """
        Runs the template in an isolated git-backed staging clone, then reports
        exactly what would change. Nothing is written to the working directory
        until you run 'egg hatch apply <token>'.

        Example:
          egg hatch preview MyTemplate --name App --enabled true
          egg hatch preview MyTemplate --exclude 'docs/**' --include dist/bundle.js
          egg hatch preview MyTemplate --no-sandbox --user-confirmed-no-sandbox
        """,
    )

    @Argument(help: "The name of the template to preview.")
    var templateName: String

    /// User-defined macro values, captured as unrecognized options (e.g. --name value).
    @Argument(parsing: .allUnrecognized, help: "User-defined macro values (e.g. --macro value).")
    var macros: [String] = []

    @Flag(name: .long, help: "Include the unified diff of each change in the output.")
    var diff = false

    @Flag(name: .long, help: "Disable sandbox-exec safety guard for preview lifecycle scripts. Requires --user-confirmed-no-sandbox.")
    var noSandbox = false

    @Flag(name: .long, help: "Confirms the user approved running preview lifecycle scripts without sandbox protection.")
    var userConfirmedNoSandbox = false

    @Option(name: .long, parsing: .upToNextOption, help: "Force normally-ignored paths into the change set (git pathspec).")
    var include: [String] = []

    @Option(name: .long, parsing: .upToNextOption, help: "Exclude paths from the change set (git pathspec).")
    var exclude: [String] = []

    @Option(name: .long, help: "Directory the generated output targets (defaults to current directory).", completion: .directory)
    var output: String?

    @OptionGroup var options: HatchTransactionOptions

    func run() async throws {
        try validateSandboxOptions()
        let service = try await options.makeService()
        let outputDirectory = output.map { URL(filePath: $0, relativeTo: URL(filePath: HatchTransactionOptions.fileManager.currentDirectoryPath)).standardizedFileURL }
        let result = try await service.previewHatchTemplate(
            templateName: templateName,
            macroArguments: macros,
            outputDirectory: outputDirectory,
            include: include,
            exclude: exclude,
            includeDiff: diff,
            sandboxDisabled: noSandbox && userConfirmedNoSandbox,
        )
        try CLIOutput.printJSON(result)
    }

    private func validateSandboxOptions() throws {
        if noSandbox, !userConfirmedNoSandbox {
            throw HatchPreviewError.sandboxDisableRequiresUserConfirmation
        }
    }
}

private enum HatchPreviewError: LocalizedError {
    case sandboxDisableRequiresUserConfirmation

    var errorDescription: String? {
        switch self {
        case .sandboxDisableRequiresUserConfirmation:
            """
            Sandbox-disabled preview requires explicit user confirmation.
            Ask the user whether to run lifecycle scripts without sandbox protection, then retry with --no-sandbox --user-confirmed-no-sandbox.
            Do not classify script contents yourself.
            """
        }
    }
}

/// `egg hatch apply <token>` — commit a previewed transaction to the working
/// directory and record a rollback bundle.
struct HatchApplyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Apply a previewed hatch transaction; emits JSON with a rollback id.",
    )

    @OptionGroup var options: HatchTransactionOptions

    @Argument(help: "The apply token returned by 'egg hatch preview'.")
    var token: String

    @Flag(name: .long, help: "Apply even if the working directory changed since the preview.")
    var force = false

    func run() async throws {
        let service = try await options.makeService()
        let result = try await service.applyHatchTransaction(applyToken: token, force: force)
        try CLIOutput.printJSON(result)
    }
}

/// `egg hatch rollback <id>` — restore files captured before a prior apply.
struct HatchRollbackCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rollback",
        abstract: "Roll back a previously applied hatch transaction; emits JSON.",
    )

    @OptionGroup var options: HatchTransactionOptions

    @Argument(help: "The rollback id returned by 'egg hatch apply'.")
    var rollbackId: String

    @Flag(name: .long, help: "Roll back even if the files changed since the apply.")
    var force = false

    func run() async throws {
        let service = try await options.makeService()
        let result = try await service.rollbackHatchTransaction(rollbackId: rollbackId, force: force)
        try CLIOutput.printJSON(result)
    }
}

/// `egg hatch discard <token>` — drop a previewed transaction without applying.
struct HatchDiscardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "discard",
        abstract: "Discard a previewed hatch transaction without applying it; emits JSON.",
    )

    @OptionGroup var options: HatchTransactionOptions

    @Argument(help: "The apply token to discard.")
    var token: String

    func run() async throws {
        let service = try await options.makeService()
        let result = try await service.discardHatchTransaction(applyToken: token)
        try CLIOutput.printJSON(result)
    }
}
