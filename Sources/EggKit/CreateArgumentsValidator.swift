import Foundation
import Path
import FileSystem

package struct CreateArgumentsValidator {
    private let name: String?
    private let description: String?
    private let location: TemplateLocationType?
    private let templatesFinder: TemplatesFinder

    package init(
        name: String?,
        description: String?,
        location: TemplateLocationType?,
        projectDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: sending some FileSysteming
    ) async {
        self.name = name
        self.description = description
        self.location = location
        self.templatesFinder = await TemplatesFinder(
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )
    }

    package func validate() async throws -> CreateRunnerMode {
        // All nil means interactive mode (Noora)
        if name == nil && description == nil && location == nil {
            return .noora
        }

        // Check which fields are provided
        let providedFields = Set([
            name != nil ? Field.name : nil,
            description != nil ? Field.description : nil,
            location != nil ? Field.location : nil
        ].compactMap { $0 })

        // Check if all required fields are provided
        let requiredFields: Set<Field> = [.name, .description, .location]
        let missingFields = requiredFields.subtracting(providedFields)

        if !missingFields.isEmpty {
            throw Error.missingFields(missing: missingFields, provided: providedFields)
        }

        // All three are provided at this point
        guard let name, let location, let description else {
            // This should never be reached due to checks above, but kept for safety
            throw Error.missingFields(missing: requiredFields, provided: [])
        }

        guard !(try await templatesFinder.exists(name)) else {
            throw Error.templateAlreadyExists
        }

        return .provided(name: name, description: description, location: location)
    }

    enum Field: String, CaseIterable {
        case name
        case description
        case location

        var displayName: String {
            switch self {
            case .name:
                "name"
            case .description:
                "description"
            case .location:
                "location"
            }
        }
    }

    enum Error: LocalizedError {
        case missingFields(missing: Set<Field>, provided: Set<Field>)
        case templateAlreadyExists

        var errorDescription: String? {
            switch self {
            case .missingFields(let missing, let provided):
                let missingText = missing.sorted(by: { $0.rawValue < $1.rawValue })
                    .map { $0.displayName }
                    .joined(separator: " and ")
                
                if provided.isEmpty {
                    return "Template \(missingText) must be provided together"
                }
                
                let providedText = provided.sorted(by: { $0.rawValue < $1.rawValue })
                    .map { $0.displayName }
                    .joined(separator: " and ")
                
                return "Template \(missingText) \(missing.count == 1 ? "is" : "are") required when \(providedText) \(provided.count == 1 ? "is" : "are") specified"
            case .templateAlreadyExists:
                return "A template with the same name already exists"
            }
        }
    }
}
