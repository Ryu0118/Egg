import FileManagerProtocol
import Foundation

/// Template CRUD: list, detail, create, delete, duplicate, move, validate,
/// install. Each method resolves a `Template`/location and hands off to the
/// `Runner` that owns the actual logic — see `EggService.swift`'s doc comment.
extension EggService {
    // MARK: - List Templates

    public func listTemplates(location: String? = nil) async throws -> ListResult {
        let locationType = try parseLocationType(location)

        let runner = ListRunner(
            mode: .mcp(location: locationType),
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
            fileManager: fileManager,
            // Skipped-template diagnostics must not interleave with the JSON
            // body this path exists to emit.
            interaction: SilentInteraction(),
        )

        return try await runner.runMcp(location: locationType)
    }

    // MARK: - Template Detail

    public func templateDetail(templateName: String) async throws -> DetailResult {
        let template = try await findTemplate(templateName)
        let location = determineLocation(for: template, templateName: templateName)

        let runner = DetailRunner(
            mode: .mcp(template: template, location: location),
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
            fileManager: fileManager,
        )

        return runner.runMcp(template: template, location: location)
    }

    // MARK: - Create Template

    public func createTemplate(
        name: String,
        description: String,
        location: String,
    ) async throws -> CreateResult {
        let locationKind = try parseLocationKind(location)

        let runner = CreateRunner(
            mode: .mcp(name: name, description: description, location: locationKind),
            skipConfig: false,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
        )

        return try await runner.runMcp(name: name, description: description, location: locationKind)
    }

    // MARK: - Delete Template

    public func deleteTemplate(templateName: String) async throws -> DeleteResult {
        let template = try await findTemplate(templateName)
        let location = determineLocation(for: template, templateName: templateName)

        let runner = DeleteRunner(
            mode: .mcp(name: templateName, path: template.path.path(percentEncoded: false), location: location),
            force: true,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
            fileManager: fileManager,
        )

        return try runner.runMcp(
            name: templateName,
            path: template.path.path(percentEncoded: false),
            location: location,
        )
    }

    // MARK: - Duplicate Template

    public func duplicateTemplate(
        sourceName: String,
        newName: String,
        newDescription: String? = nil,
    ) async throws -> DuplicateResult {
        let sourceTemplate = try await findTemplate(sourceName)
        let sourceLocation = determineLocation(for: sourceTemplate, templateName: sourceName)
        let finalDescription = newDescription ?? sourceTemplate.config.description

        let runner = DuplicateRunner(
            mode: .mcp(
                sourceName: sourceName,
                sourcePath: sourceTemplate.path.path(percentEncoded: false),
                sourceLocation: sourceLocation,
                newName: newName,
                newDescription: finalDescription,
            ),
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
            fileManager: fileManager,
        )

        return try await runner.runMcp(
            sourceName: sourceName,
            sourcePath: sourceTemplate.path.path(percentEncoded: false),
            sourceLocation: sourceLocation,
            newName: newName,
            newDescription: finalDescription,
        )
    }

    // MARK: - Move Template

    public func moveTemplate(
        templateName: String,
        targetLocation: String,
    ) async throws -> MoveResult {
        let target = try parseLocationType(targetLocation, required: true)!
        let sourceTemplate = try await findTemplate(templateName)
        let sourceLocation = determineLocation(for: sourceTemplate, templateName: templateName)

        let runner = MoveRunner(
            mode: .mcp(
                name: templateName,
                path: sourceTemplate.path.path(percentEncoded: false),
                sourceLocation: sourceLocation,
                targetLocation: target,
            ),
            force: true,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
            fileManager: fileManager,
        )

        return try await runner.runMcp(
            name: templateName,
            path: sourceTemplate.path.path(percentEncoded: false),
            sourceLocation: sourceLocation,
            targetLocation: target,
        )
    }

    // MARK: - Validate Template

    public func validateTemplate(templatePath: String) async throws -> ValidateResult {
        let path = URL(filePath: templatePath)
        let configLoader = ConfigLoader(fileManager: fileManager)
        let config: Config
        do {
            config = try configLoader.load(from: path)
        } catch let error as ConfigLoaderError {
            // An undecodable config is a validation *result*, not a tool
            // failure: report it as invalid with the formatted decode
            // message. A missing config.yml stays a thrown error — that's a
            // wrong path, not a broken template.
            guard case .decodingFailed = error else { throw error }
            return ValidateResult(
                templateName: path.lastPathComponent,
                templatePath: path.path(percentEncoded: false),
                isValid: false,
                errors: [error.localizedDescription],
            )
        }

        let runner = ValidateRunner(
            mode: .mcp(config: config, templatePath: path),
            fileManager: fileManager,
        )

        return await runner.runMcp(config: config, templatePath: path)
    }

    // MARK: - Install Templates

    public func installTemplates(
        source: String,
        location: String,
        ref: String? = nil,
        include: [String]? = nil,
        exclude: [String]? = nil,
    ) async throws -> InstallResult {
        let locationKind = try parseLocationKind(location)
        let templateSource = try parseTemplateSource(source, ref: ref)
        let filter = parseTemplateFilter(include: include, exclude: exclude)

        let runner = InstallRunner(
            mode: .direct(source: templateSource, location: locationKind, filter: filter),
            force: true,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            // Direct mode logs progress lines; the service's callers put the
            // encoded result on stdout, which must not be interleaved.
            interaction: SilentInteraction(),
        )

        return try await runner.run()
    }

    // MARK: - Shared Helpers

    /// Creates a TemplatesFinder with the service's configuration.
    func makeTemplatesFinder(workingDirectory: URL? = nil) -> TemplatesFinder {
        TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory ?? self.workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
        )
    }

    /// Finds a template by name.
    func findTemplate(_ name: String, workingDirectory: URL? = nil) async throws -> Template {
        try await makeTemplatesFinder(workingDirectory: workingDirectory).fetchTemplate(name)
    }

    /// Determines the location type for a template.
    func determineLocation(for template: Template, templateName: String) -> TemplateLocationType {
        TemplateLocation(homeDirectory: homeDirectory)
            .determineLocation(
                templateName: templateName,
                templatePath: template.path,
                additionalSearchPaths: additionalSearchPaths,
                projectDirectory: projectDirectory,
                workingDirectory: workingDirectory,
            )
    }

    /// Parses a location string to TemplateLocationType.
    func parseLocationType(_ location: String?, required: Bool = false) throws -> TemplateLocationType? {
        guard let location else { return nil }

        switch location {
        case "global":
            return .global
        case "project":
            return .project(projectDirectory, workingDirectory: workingDirectory)
        default:
            if required {
                throw EggServiceError.invalidLocation(location)
            }
            return nil
        }
    }

    /// Parses a location string to TemplateLocationType.Kind.
    func parseLocationKind(_ location: String) throws -> TemplateLocationType.Kind {
        switch location {
        case "global":
            return .global
        case "project":
            return .project
        default:
            throw EggServiceError.invalidLocation(location)
        }
    }

    /// Parses source string to TemplateSource.
    func parseTemplateSource(_ source: String, ref: String?) throws -> TemplateSource {
        // GitURLParser knows every supported scheme (https, ssh, git, file,
        // credentialed); anything it can't parse is a local filesystem path.
        if let gitURL = GitURLParser().parse(source) {
            return .git(url: gitURL, ref: ref.map(Self.gitRef(from:)))
        }
        // Local sources copy the working tree as-is, so a ref cannot be
        // honored — reject it loudly (matching the CLI validator) instead of
        // silently installing HEAD when the caller believes they pinned one.
        guard ref == nil else {
            throw EggServiceError.refNotAllowedForLocalPath(source)
        }
        return .local(path: URL(filePath: source))
    }

    /// Maps the service's single `ref` string onto a GitRef: a 40-hex string
    /// is a commit SHA; anything else works as `--branch`, which git accepts
    /// for both branches and tags.
    static func gitRef(from ref: String) -> GitRef {
        let isCommitSHA = ref.count == 40 && ref.allSatisfy(\.isHexDigit)
        return isCommitSHA ? .revision(ref) : .branch(ref)
    }

    /// Parses include/exclude filters to TemplateFilter.
    func parseTemplateFilter(include: [String]?, exclude: [String]?) -> TemplateFilter {
        if let include, !include.isEmpty {
            .include(include)
        } else if let exclude, !exclude.isEmpty {
            .exclude(exclude)
        } else {
            .none
        }
    }
}
