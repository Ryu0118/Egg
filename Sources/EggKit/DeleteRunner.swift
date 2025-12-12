import FileManagerProtocol
import Foundation
import Noora

package struct DeleteRunner {
    private let mode: DeleteRunnerMode
    private let templateLocation: TemplateLocation
    private let templatesFinder: TemplatesFinder
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let force: Bool
    private let fileManager: any FileManagerProtocol
    private let noora: any Noorable

    package init(
        mode: DeleteRunnerMode,
        force: Bool,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol,
        noora: some Noorable = Noora()
    ) {
        let templateLocation = TemplateLocation(
            homeDirectory: homeDirectory
        )
        self.mode = mode
        self.templateLocation = templateLocation
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.force = force
        self.fileManager = fileManager
        self.noora = noora
        templatesFinder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )
    }

    package func run() async throws {
        switch mode {
        case .interactive:
            let options = try await templatesFinder.listWithLocations()

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

            try confirmAndDelete(
                templateName: templateName,
                path: templatePath,
                location: templateLocationType
            )

        case let .direct(name, pathString, location):
            try confirmAndDelete(
                templateName: name,
                path: URL(fileURLWithPath: pathString),
                location: location
            )
        }
    }

    private func confirmAndDelete(
        templateName: String,
        path: URL,
        location: TemplateLocationType
    ) throws {
        // Confirmation (skip if force is true)
        if !force {
            let confirm = noora.yesOrNoChoicePrompt(
                title: "Confirm Deletion",
                question: "Are you sure you want to delete template '\(templateName)'?"
            )

            guard confirm else {
                noora.info("Deletion cancelled.")
                return
            }
        }

        try deleteTemplate(at: path, name: templateName, location: location)
    }

    private func deleteTemplate(at path: URL, name: String, location: TemplateLocationType) throws {
        do {
            try fileManager.removeItem(at: path)
            noora.success("Successfully deleted template '\(name)' from \(location.dir)")
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
            case let .deletionFailed(name, underlying):
                "Failed to delete template '\(name)': \(underlying.localizedDescription)"
            }
        }
    }
}

package enum DeleteRunnerMode: Codable {
    case interactive
    case direct(name: String, path: String, location: TemplateLocationType)
}
