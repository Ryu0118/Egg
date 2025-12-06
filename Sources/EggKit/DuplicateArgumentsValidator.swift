import Foundation
import Path
import FileSystem
import Yams

package struct DuplicateArgumentsValidator {
    private let templateName: String?
    private let newName: String?
    private let newDescription: String?
    private let templatesFinder: TemplatesFinder
    private let homeDirectory: AbsolutePath
    private let projectDirectory: AbsolutePath
    private let workingDirectory: AbsolutePath
    private let fileSystem: any FileSysteming
    private let decoder = YAMLDecoder()

    package init(
        templateName: String?,
        newName: String?,
        newDescription: String?,
        projectDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: some FileSysteming
    ) {
        self.templateName = templateName
        self.newName = newName
        self.newDescription = newDescription
        self.homeDirectory = homeDirectory
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.fileSystem = fileSystem
        self.templatesFinder = TemplatesFinder(
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )
    }

    package func validate() async throws -> DuplicateRunnerMode {
        guard let templateName else {
            return .noora
        }

        let (sourcePath, sourceLocation) = try await findSourceTemplate(name: templateName)
        let sourceConfig = try await readSourceConfig(at: sourcePath)
        let (finalNewName, finalNewDescription) = try await determineNewTemplateInfo(
            sourceConfig: sourceConfig,
            sourceLocation: sourceLocation
        )

        return .provided(
            sourceName: templateName,
            sourcePath: sourcePath.pathString,
            sourceLocation: sourceLocation,
            newName: finalNewName,
            newDescription: finalNewDescription
        )
    }

    private func findSourceTemplate(name: String) async throws -> (path: AbsolutePath, location: TemplateLocationType) {
        guard let sourcePath = try await templatesFinder.validTemplateDirectory(name) else {
            throw Error.templateNotFound(name: name)
        }

        let sourceLocation = try await determineSourceLocation(
            templateName: name,
            sourcePath: sourcePath
        )

        return (sourcePath, sourceLocation)
    }

    private func determineSourceLocation(
        templateName: String,
        sourcePath: AbsolutePath
    ) async throws -> TemplateLocationType {
        let templateLocationInstance = TemplateLocation(
            homeDirectory: homeDirectory
        )
        let globalPath = templateLocationInstance.template(templateName, type: .global)
        
        return if try await fileSystem.exists(globalPath) && sourcePath == globalPath {
            TemplateLocationType.global
        } else {
            TemplateLocationType.project(
                projectDirectory,
                workingDirectory: workingDirectory
            )
        }
    }

    private func readSourceConfig(at sourcePath: AbsolutePath) async throws -> Config {
        let configPath = sourcePath.appending(component: "config.yml")
        let configData = try await fileSystem.readFile(at: configPath)
        return try decoder.decode(Config.self, from: configData)
    }

    private func determineNewTemplateInfo(
        sourceConfig: Config,
        sourceLocation: TemplateLocationType
    ) async throws -> (name: String, description: String) {
        let finalNewName = if let newName {
            newName
        } else {
            await generateDefaultName(
                baseName: sourceConfig.name,
                sourceLocation: sourceLocation
            )
        }

        let finalNewDescription = newDescription ?? sourceConfig.description

        try await validateNewTemplateName(finalNewName)

        return (finalNewName, finalNewDescription)
    }

    private func validateNewTemplateName(_ name: String) async throws {
        guard !(try await templatesFinder.exists(name)) else {
            throw Error.templateAlreadyExists(name: name)
        }

        let templateNameErrors = Config.templateNameValidationRules.validate(input: name)
        if !templateNameErrors.isEmpty {
            throw CombinedError(errors: templateNameErrors) { "⛔️ \($0)" }
        }
    }

    private func generateDefaultName(
        baseName: String,
        sourceLocation: TemplateLocationType
    ) async -> String {
        await DuplicateTemplateNameGenerator.generateDefaultName(
            baseName: baseName,
            sourceLocation: sourceLocation,
            templatesFinder: templatesFinder,
            emitValidationErrorLog: true
        )
    }

    enum Error: LocalizedError {
        case templateNotFound(name: String)
        case templateAlreadyExists(name: String)

        var errorDescription: String? {
            switch self {
            case .templateNotFound(let name):
                return "Template '\(name)' not found"
            case .templateAlreadyExists(let name):
                return "A template with the name '\(name)' already exists"
            }
        }
    }
}
