@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

/// A project-local template must win over a global template with the same
/// name, and an explicit location must restrict the search to that location.
/// Every lookup path (CLI detail/hatch, MCP detail/hatch preview) funnels
/// through `TemplatesFinder`, so the resolver is tested directly and through
/// `EggService`, which the MCP handlers call.
@Suite("Template resolution precedence")
struct TemplatePrecedenceTests {
    private struct Fixture {
        let root: URL
        let home: URL
        let project: URL
        let custom: URL

        init() throws {
            let fileManager: any FileManagerProtocol = FileManager.default
            root = try fileManager.makeTemporaryDirectory(prefix: "template-precedence-test")
            home = root.appending(path: "home")
            project = root.appending(path: "project")
            custom = root.appending(path: "custom")
            for directory in [home, project, custom] {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }

        @discardableResult
        func addTemplate(
            in base: URL,
            dirName: String,
            configName: String,
            macro: String,
        ) throws -> URL {
            let dir = base.appending(path: dirName)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try """
            name: \(configName)
            description: Test template
            macros:
              - name: \(macro)
                description: Test macro
                type: string
            hatch:
              output: .
            """.write(to: dir.appending(path: "config.yml"), atomically: true, encoding: .utf8)
            return dir
        }

        func globalBase() -> URL {
            home.appending(path: ".eggs")
        }

        func projectBase() -> URL {
            project.appending(path: ".eggs")
        }

        func finder(additionalSearchPaths: [URL] = []) -> TemplatesFinder {
            TemplatesFinder(
                fileManager: FileManager.default,
                projectDirectory: project,
                workingDirectory: project,
                homeDirectory: home,
                additionalSearchPaths: additionalSearchPaths,
            )
        }

        func service(additionalSearchPaths: [URL] = []) -> EggService {
            EggService(
                workingDirectory: project,
                projectDirectory: project,
                homeDirectory: home,
                additionalSearchPaths: additionalSearchPaths,
            )
        }

        var projectLocation: TemplateLocationType {
            .project(project, workingDirectory: project)
        }
    }

    private func macroNames(of template: Template) -> [String] {
        (template.config.macros ?? []).map(\.name)
    }

    // MARK: - Finder

    @Test("without a location the project template wins over a global template of the same name")
    func projectWinsWithoutLocation() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.globalBase(), dirName: "Feature", configName: "Feature", macro: "___GLOBAL_ONLY___")
        try fixture.addTemplate(in: fixture.projectBase(), dirName: "Feature", configName: "Feature", macro: "___PROJECT_ONLY___")

        let template = try await fixture.finder().fetchTemplate("Feature")

        #expect(macroNames(of: template) == ["___PROJECT_ONLY___"])
        #expect(template.path.isSamePath(to: fixture.projectBase().appending(path: "Feature")))
    }

    @Test("project wins when config names differ from the shared directory name")
    func projectWinsOnDirectoryNameFallback() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.globalBase(), dirName: "Feature", configName: "GlobalName", macro: "___GLOBAL_ONLY___")
        try fixture.addTemplate(in: fixture.projectBase(), dirName: "Feature", configName: "ProjectName", macro: "___PROJECT_ONLY___")

        let template = try await fixture.finder().fetchTemplate("Feature")

        #expect(macroNames(of: template) == ["___PROJECT_ONLY___"])
    }

    @Test("project wins when only the config name matches in both locations")
    func projectWinsOnConfigNameMatch() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.globalBase(), dirName: "global-dir", configName: "Feature", macro: "___GLOBAL_ONLY___")
        try fixture.addTemplate(in: fixture.projectBase(), dirName: "project-dir", configName: "Feature", macro: "___PROJECT_ONLY___")

        let template = try await fixture.finder().fetchTemplate("Feature")

        #expect(macroNames(of: template) == ["___PROJECT_ONLY___"])
    }

    @Test("a custom search path still wins over project and global")
    func customStillWins() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.globalBase(), dirName: "Feature", configName: "Feature", macro: "___GLOBAL_ONLY___")
        try fixture.addTemplate(in: fixture.projectBase(), dirName: "Feature", configName: "Feature", macro: "___PROJECT_ONLY___")
        try fixture.addTemplate(in: fixture.custom, dirName: "Feature", configName: "Feature", macro: "___CUSTOM_ONLY___")

        let template = try await fixture.finder(additionalSearchPaths: [fixture.custom]).fetchTemplate("Feature")

        #expect(macroNames(of: template) == ["___CUSTOM_ONLY___"])
    }

    @Test("an explicit global location resolves the global template even when a project one shadows it")
    func globalLocationPicksGlobal() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.globalBase(), dirName: "Feature", configName: "Feature", macro: "___GLOBAL_ONLY___")
        try fixture.addTemplate(in: fixture.projectBase(), dirName: "Feature", configName: "Feature", macro: "___PROJECT_ONLY___")

        let template = try await fixture.finder().fetchTemplate("Feature", location: .global)

        #expect(macroNames(of: template) == ["___GLOBAL_ONLY___"])
    }

    @Test("an explicit project location resolves the project template")
    func projectLocationPicksProject() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.globalBase(), dirName: "Feature", configName: "Feature", macro: "___GLOBAL_ONLY___")
        try fixture.addTemplate(in: fixture.projectBase(), dirName: "Feature", configName: "Feature", macro: "___PROJECT_ONLY___")

        let template = try await fixture.finder().fetchTemplate("Feature", location: fixture.projectLocation)

        #expect(macroNames(of: template) == ["___PROJECT_ONLY___"])
    }

    @Test("an explicit location ignores custom search paths")
    func locationExcludesCustomPaths() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.globalBase(), dirName: "Feature", configName: "Feature", macro: "___GLOBAL_ONLY___")
        try fixture.addTemplate(in: fixture.custom, dirName: "Feature", configName: "Feature", macro: "___CUSTOM_ONLY___")

        let template = try await fixture.finder(additionalSearchPaths: [fixture.custom])
            .fetchTemplate("Feature", location: .global)

        #expect(macroNames(of: template) == ["___GLOBAL_ONLY___"])
    }

    @Test("an explicit project location does not fall back to a global template")
    func projectLocationDoesNotFallBack() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.globalBase(), dirName: "Feature", configName: "Feature", macro: "___GLOBAL_ONLY___")

        await #expect(throws: TemplatesFinder.Error.self) {
            _ = try await fixture.finder().fetchTemplate("Feature", location: fixture.projectLocation)
        }
    }

    @Test("an explicit global location does not fall back to a project template")
    func globalLocationDoesNotFallBack() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.projectBase(), dirName: "Feature", configName: "Feature", macro: "___PROJECT_ONLY___")

        await #expect(throws: TemplatesFinder.Error.self) {
            _ = try await fixture.finder().fetchTemplate("Feature", location: .global)
        }
    }

    @Test("listing keeps both entries when a project template shadows a global one")
    func listShowsBothEntries() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.globalBase(), dirName: "Feature", configName: "Feature", macro: "___GLOBAL_ONLY___")
        try fixture.addTemplate(in: fixture.projectBase(), dirName: "Feature", configName: "Feature", macro: "___PROJECT_ONLY___")

        let result = try await fixture.service().listTemplates()

        #expect(result.templates.map(\.location).sorted() == ["global", "project"])
        #expect(result.templates.allSatisfy { $0.name == "Feature" })
    }

    // MARK: - Service (MCP and CLI --json entry point)

    @Test("templateDetail resolves the project template and reports the project location")
    func serviceDetailPrefersProject() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.globalBase(), dirName: "Feature", configName: "Feature", macro: "___GLOBAL_ONLY___")
        try fixture.addTemplate(in: fixture.projectBase(), dirName: "Feature", configName: "Feature", macro: "___PROJECT_ONLY___")

        let result = try await fixture.service().templateDetail(templateName: "Feature")

        #expect(result.basicInfo.locationName == "project")
        #expect(result.macros.map(\.name) == ["___PROJECT_ONLY___"])
    }

    @Test("templateDetail with location global resolves the global template")
    func serviceDetailGlobalLocation() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.globalBase(), dirName: "Feature", configName: "Feature", macro: "___GLOBAL_ONLY___")
        try fixture.addTemplate(in: fixture.projectBase(), dirName: "Feature", configName: "Feature", macro: "___PROJECT_ONLY___")

        let result = try await fixture.service().templateDetail(templateName: "Feature", location: "global")

        #expect(result.basicInfo.locationName == "global")
        #expect(result.macros.map(\.name) == ["___GLOBAL_ONLY___"])
    }

    @Test("templateDetail with location project fails when only a global template exists")
    func serviceDetailProjectLocationNoFallback() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.globalBase(), dirName: "Feature", configName: "Feature", macro: "___GLOBAL_ONLY___")

        await #expect(throws: TemplatesFinder.Error.self) {
            _ = try await fixture.service().templateDetail(templateName: "Feature", location: "project")
        }
    }

    @Test("templateDetail rejects an unknown location")
    func serviceDetailInvalidLocation() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.globalBase(), dirName: "Feature", configName: "Feature", macro: "___GLOBAL_ONLY___")

        await #expect(throws: EggServiceError.self) {
            _ = try await fixture.service().templateDetail(templateName: "Feature", location: "nowhere")
        }
    }

    // MARK: - CLI detail validator

    @Test("the detail validator honors --location in direct mode")
    func detailValidatorHonorsLocation() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addTemplate(in: fixture.globalBase(), dirName: "Feature", configName: "Feature", macro: "___GLOBAL_ONLY___")
        try fixture.addTemplate(in: fixture.projectBase(), dirName: "Feature", configName: "Feature", macro: "___PROJECT_ONLY___")

        func validate(location: TemplateLocationType?) async throws -> (names: [String], location: TemplateLocationType) {
            let mode = try await DetailArgumentsValidator(
                templateName: "Feature",
                location: location,
                projectDirectory: fixture.project,
                workingDirectory: fixture.project,
                homeDirectory: fixture.home,
                fileManager: FileManager.default,
            ).validate()
            guard case let .direct(template, resolvedLocation) = mode else {
                Issue.record("expected direct mode")
                return ([], .global)
            }
            return (macroNames(of: template), resolvedLocation)
        }

        let unrestricted = try await validate(location: nil)
        #expect(unrestricted.names == ["___PROJECT_ONLY___"])
        #expect(unrestricted.location == fixture.projectLocation)

        let global = try await validate(location: .global)
        #expect(global.names == ["___GLOBAL_ONLY___"])
        #expect(global.location == .global)

        let project = try await validate(location: fixture.projectLocation)
        #expect(project.names == ["___PROJECT_ONLY___"])
    }
}
