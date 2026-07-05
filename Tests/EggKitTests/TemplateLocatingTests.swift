@testable import EggKit
import Foundation
import Testing

/// `determineLocation` classifies a resolved template path as custom, global,
/// or project. It must compare paths, not URL values: the resolved path can
/// carry a trailing slash, and URL `==` treated that as a different location —
/// so a template deleted from ~/.eggs was reported as location "project".
@Suite("TemplateLocation.determineLocation")
struct TemplateLocatingTests {
    private let home = URL(filePath: "/Users/tester")
    private let project = URL(filePath: "/Users/tester/Work/App")

    private func determine(path: URL, additionalSearchPaths: [URL] = []) -> TemplateLocationType {
        TemplateLocation(homeDirectory: home).determineLocation(
            templateName: "MyPkg",
            templatePath: path,
            additionalSearchPaths: additionalSearchPaths,
            projectDirectory: project,
            workingDirectory: project,
        )
    }

    @Test("a global template path with a trailing slash is still global")
    func trailingSlashGlobalPathIsGlobal() {
        #expect(determine(path: URL(filePath: "/Users/tester/.eggs/MyPkg/")) == .global)
    }

    @Test("an exact global template path is global")
    func exactGlobalPathIsGlobal() {
        #expect(determine(path: URL(filePath: "/Users/tester/.eggs/MyPkg")) == .global)
    }

    @Test("a custom search path match with a trailing slash is still custom")
    func trailingSlashCustomPathIsCustom() {
        let custom = URL(filePath: "/opt/shared-templates")
        #expect(
            determine(path: URL(filePath: "/opt/shared-templates/MyPkg/"), additionalSearchPaths: [custom])
                == .custom(custom),
        )
    }

    @Test("a path under the project's .eggs falls through to project")
    func projectPathIsProject() {
        #expect(
            determine(path: URL(filePath: "/Users/tester/Work/App/.eggs/MyPkg"))
                == .project(project, workingDirectory: project),
        )
    }
}
