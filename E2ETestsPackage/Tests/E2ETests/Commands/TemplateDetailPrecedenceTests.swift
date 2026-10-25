import FileManagerProtocol
import Foundation
import Testing

@Suite(.buildBinary, .serialized)
struct TemplateDetailPrecedenceTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    @Test(
        "detail resolves a project template before a global one of the same name unless --location restricts the search",
        arguments: [
            (location: nil as String?, expectedLocation: "project", expectedMacro: "___PROJECT_ONLY___"),
            (location: "project", expectedLocation: "project", expectedMacro: "___PROJECT_ONLY___"),
            (location: "global", expectedLocation: "global", expectedMacro: "___GLOBAL_ONLY___"),
        ],
    )
    func detailPrecedence(location: String?, expectedLocation: String, expectedMacro: String) async throws {
        let runner = try await CLIRunner()
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test-detail-precedence")
        defer { try? fileManager.removeItem(at: tempDir) }

        let homeDir = tempDir.appending(path: "home")
        let projectDir = tempDir.appending(path: "project")
        try writeTemplate(at: homeDir.appending(path: ".eggs/Feature"), macro: "___GLOBAL_ONLY___")
        try writeTemplate(at: projectDir.appending(path: ".eggs/Feature"), macro: "___PROJECT_ONLY___")

        var arguments = ["template", "detail", "Feature", "--json", "--project-directory", projectDir.path(percentEncoded: false)]
        if let location {
            arguments += ["--location", location]
        }
        let result = try await runner.run(
            arguments: arguments,
            workingDirectory: projectDir,
            environment: ["HOME": homeDir.path(percentEncoded: false)],
        )

        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")
        let json = try #require(JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
        let basicInfo = try #require(json["basicInfo"] as? [String: Any])
        let macros = try #require(json["macros"] as? [[String: Any]])
        #expect(basicInfo["locationName"] as? String == expectedLocation)
        #expect(macros.compactMap { $0["name"] as? String } == [expectedMacro])
    }

    @Test("detail --location project fails instead of falling back to a global template")
    func projectLocationDoesNotFallBack() async throws {
        let runner = try await CLIRunner()
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test-detail-no-fallback")
        defer { try? fileManager.removeItem(at: tempDir) }

        let homeDir = tempDir.appending(path: "home")
        let projectDir = tempDir.appending(path: "project")
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try writeTemplate(at: homeDir.appending(path: ".eggs/Feature"), macro: "___GLOBAL_ONLY___")

        let result = try await runner.run(
            "template", "detail", "Feature", "--json", "--location", "project",
            "--project-directory", projectDir.path(percentEncoded: false),
            workingDirectory: projectDir,
            environment: ["HOME": homeDir.path(percentEncoded: false)],
        )

        #expect(!result.succeeded)
    }

    private func writeTemplate(at directory: URL, macro: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = """
        name: Feature
        description: Test template
        macros:
          - name: \(macro)
            description: Test macro
            type: string
        hatch:
          output: .
        """
        try config.write(to: directory.appending(path: "config.yml"), atomically: true, encoding: .utf8)
    }
}
