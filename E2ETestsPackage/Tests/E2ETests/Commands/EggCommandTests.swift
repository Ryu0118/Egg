import Testing

@Suite(.buildBinary, .serialized)
struct EggCommandTests {
    let runner: CLIRunner

    init() async throws {
        runner = try await CLIRunner()
    }

    @Test
    func `--help flag shows help information`() async throws {
        let result = try await runner.run("--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW:"))
        #expect(result.stdout.contains("USAGE: egg <subcommand>"))
        #expect(result.stdout.contains("OPTIONS:"))
        #expect(result.stdout.contains("SUBCOMMANDS:"))
        #expect(result.stdout.contains("template"))
        #expect(result.stdout.contains("hatch"))
    }

    @Test
    func `-h flag shows help information`() async throws {
        let result = try await runner.run("-h")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW:"))
        #expect(result.stdout.contains("USAGE: egg <subcommand>"))
    }

    @Test
    func `No arguments shows help information`() async throws {
        let result = try await runner.run()

        #expect(result.succeeded)
        #expect(result.stdout.contains("USAGE: egg <subcommand>"))
    }

    @Test
    func `Invalid subcommand shows error`() async throws {
        let result = try await runner.run("invalidcommand")

        #expect(!result.succeeded)
        #expect(result.stderr.contains("Unexpected argument 'invalidcommand'"))
        #expect(result.stderr.contains("See 'egg --help' for more information"))
    }

    @Test
    func `template --help shows template subcommand help`() async throws {
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

    @Test
    func `hatch --help shows hatch subcommand help`() async throws {
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
