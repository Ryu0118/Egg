import Testing

@Suite(.buildBinary, .serialized)
struct EggCommandTests {
    let runner: CLIRunner

    init() async throws {
        runner = try await CLIRunner()
    }

    @Test("--help flag shows help information")
    func helpFlagShowsHelpInformation() async throws {
        let result = try await runner.run("--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW:"))
        #expect(result.stdout.contains("USAGE: egg <subcommand>"))
        #expect(result.stdout.contains("OPTIONS:"))
        #expect(result.stdout.contains("SUBCOMMANDS:"))
        #expect(result.stdout.contains("template"))
        #expect(result.stdout.contains("hatch"))
    }

    @Test("-h flag shows help information")
    func hFlagShowsHelpInformation() async throws {
        let result = try await runner.run("-h")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW:"))
        #expect(result.stdout.contains("USAGE: egg <subcommand>"))
    }

    @Test("No arguments shows help information")
    func noArgumentsShowsHelpInformation() async throws {
        let result = try await runner.run()

        #expect(result.succeeded)
        #expect(result.stdout.contains("USAGE: egg <subcommand>"))
    }

    @Test("Unknown subcommand fails with an unexpected-argument error and a hint to run --help")
    func invalidSubcommandShowsError() async throws {
        let result = try await runner.run("invalidcommand")

        #expect(!result.succeeded)
        #expect(result.stderr.contains("Unexpected argument 'invalidcommand'"))
        #expect(result.stderr.contains("See 'egg --help' for more information"))
    }

    @Test("template --help lists all template subcommands (create/install/list/delete/duplicate/move/open/validate)")
    func templateHelpShowsTemplateSubcommandHelp() async throws {
        let result = try await runner.run("template", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW: Manage templates"))
        #expect(result.stdout.contains("USAGE: egg template <subcommand>"))
        #expect(result.stdout.contains("create"))
        #expect(result.stdout.contains("install"))
        #expect(result.stdout.contains("list"))
        #expect(result.stdout.contains("delete"))
        #expect(result.stdout.contains("duplicate"))
        #expect(result.stdout.contains("move"))
        #expect(result.stdout.contains("open"))
        #expect(result.stdout.contains("validate"))
    }

    @Test("hatch --help documents the template-name argument and staging/override/sandbox/apply flags")
    func hatchHelpShowsHatchSubcommandHelp() async throws {
        let result = try await runner.run("hatch", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("USAGE: egg hatch"))
        #expect(result.stdout.contains("<template-name>"))
        #expect(result.stdout.contains("--no-staging"))
        #expect(result.stdout.contains("--override-conflicts"))
        #expect(result.stdout.contains("--no-sandbox"))
        #expect(result.stdout.contains("--apply-changes"))
    }
}
