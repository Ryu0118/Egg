import Foundation
import FileSystem
import Path
import Noora

package struct DeleteRunner {
    private let mode: DeleteRunnerMode
    private let templateLocation: TemplateLocation
    private let templatesFinder: TemplatesFinder
    private let projectDirectory: AbsolutePath
    private let workingDirectory: AbsolutePath
    private let force: Bool

    package init(
        mode: DeleteRunnerMode,
        force: Bool,
        projectDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: some FileSysteming
    ) async {
        let templateLocation = TemplateLocation(
            homeDirectory: homeDirectory
        )
        self.mode = mode
        self.templateLocation = templateLocation
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.force = force
        self.templatesFinder = TemplatesFinder(
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )
    }

    package func run() async throws {
        let noora = Noora()

        switch mode {
        case .noora:
            // Get templates from both locations separately
            let globalTemplates = try await templatesFinder.list(for: .global)
            let projectTemplates = try await templatesFinder.list(
                for: .project(
                    projectDirectory,
                    workingDirectory: workingDirectory
                )
            )

            let globalOptions = globalTemplates.map { TemplateOption(template: $0, location: .global) }
            let projectOptions = projectTemplates.map {
                TemplateOption(
                    template: $0,
                    location: .project(
                        projectDirectory,
                        workingDirectory: workingDirectory
                    )
                )
            }

            let options = globalOptions + projectOptions

            guard !options.isEmpty else {
                throw Error.noTemplatesFound
            }

            let selectedOption = noora.singleChoicePrompt(
                title: "Select Template to Delete",
                question: "Which template would you like to delete?",
                options: options,
                description: "Select a template to delete."
            )

            let templateName = selectedOption.template.config.name
            let templatePath = selectedOption.template.path
            let templateLocationType = selectedOption.location

            try await confirmAndDelete(
                templateName: templateName,
                path: templatePath,
                location: templateLocationType,
                noora: noora
            )

        case .provided(let name, let pathString, let location):
            try await confirmAndDelete(
                templateName: name,
                path: try AbsolutePath(validating: pathString),
                location: location,
                noora: noora
            )
        }
    }

    private func confirmAndDelete(
        templateName: String,
        path: AbsolutePath,
        location: TemplateLocationType,
        noora: Noora
    ) async throws {
        // Confirmation (skip if force is true)
        if !force {
            let confirm = noora.yesOrNoChoicePrompt(
                title: "Confirm Deletion",
                question: "Are you sure you want to delete template '\(templateName)'?",
            )

            guard confirm else {
                noora.info("Deletion cancelled.")
                return
            }
        }

        try await deleteTemplate(at: path, name: templateName, location: location)
    }

    private func deleteTemplate(at path: AbsolutePath, name: String, location: TemplateLocationType) async throws {
        do {
            try await templatesFinder.fileSystem.remove(path)
            Noora().success("Successfully deleted template '\(name)' from \(location.dir)")
        } catch {
            throw Error.deletionFailed(name: name, underlying: error)
        }
    }

    enum Error: LocalizedError {
        case noTemplatesFound
        case deletionFailed(name: String, underlying: Swift.Error)

        var errorDescription: String? {
            switch self {
            case .noTemplatesFound:
                "No templates found to delete"
            case .deletionFailed(let name, let underlying):
                "Failed to delete template '\(name)': \(underlying.localizedDescription)"
            }
        }
    }
}

package enum DeleteRunnerMode: Codable {
    case noora
    case provided(name: String, path: String, location: TemplateLocationType)
}

// Create options with location info
private struct TemplateOption: CustomStringConvertible, Equatable {
    let template: Template
    let location: TemplateLocationType

    var description: String {
        "\(template.config.name) (\(location.name))"
    }
}
