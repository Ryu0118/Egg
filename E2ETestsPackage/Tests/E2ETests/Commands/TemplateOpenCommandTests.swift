import Foundation
import Testing

@Suite(.buildBinary, .serialized)
struct TemplateOpenCommandTests {
    @Test("--help shows open command help")
    func helpShowsOpenCommandHelp() async throws {
        let runner = try await CLIRunner()
        let result = try await runner.run("template", "open", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW: Open a template directory in Finder"))
        #expect(result.stdout.contains("USAGE: egg template open"))
        #expect(result.stdout.contains("<template-name>"))
        #expect(result.stdout.contains("--project-directory"))
        #expect(result.stdout.contains("--template-search-paths"))
    }
}
