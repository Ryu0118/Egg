import FileManagerProtocol
import Foundation

package struct CreateArgumentsValidator {
    private let name: String?
    private let description: String?
    private let location: TemplateLocationType.Kind?
    private let templatesFinder: TemplatesFinder

    package init(
        name: String?,
        description: String?,
        location: TemplateLocationType.Kind?,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol,
    ) {
        self.name = name
        self.description = description
        self.location = location
        templatesFinder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
        )
    }

    package func validate() async throws -> CreateRunnerMode {
        // All nil means interactive mode
        if name == nil, description == nil, location == nil {
            return .interactive
        }

        // Check which fields are provided
        let providedFields = Set([
            name != nil ? Field.name : nil,
            description != nil ? Field.description : nil,
            location != nil ? Field.location : nil,
        ].compactMap(\.self))

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

        guard await !templatesFinder.exists(name) else {
            throw Error.templateAlreadyExists
        }

        let templateNameErrors = await Config.templateNameValidationRules.validate(name)
        let templateDescriptionErrors = await Config.templateNameValidationRules.validate(description)

        let argumentValidationErrors = templateNameErrors + templateDescriptionErrors
        if !argumentValidationErrors.isEmpty {
            throw CombinedError(errors: argumentValidationErrors) { "⛔️ \($0)" }
        }

        return .direct(name: name, description: description, location: location)
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
            case let .missingFields(missing, provided):
                let missingText = missing.sorted(by: { $0.rawValue < $1.rawValue })
                    .map(\.displayName)
                    .joined(separator: " and ")

                if provided.isEmpty {
                    return "Template \(missingText) must be provided together"
                }

                let providedText = provided.sorted(by: { $0.rawValue < $1.rawValue })
                    .map(\.displayName)
                    .joined(separator: " and ")

                return "Template \(missingText) \(missing.count == 1 ? "is" : "are") required when \(providedText) \(provided.count == 1 ? "is" : "are") specified"
            case .templateAlreadyExists:
                return "A template with the same name already exists"
            }
        }
    }
}
