import FileSystem
import Foundation
import Glob
import Noora
import Path

/// Expands template files by substituting macros and copying to output directory.
///
/// Responsibilities:
/// - Recursively traverse template directory
/// - Substitute macros in filenames and directory names
/// - Substitute macros and step outputs in file contents
/// - Apply glob exclusion patterns (conditional and unconditional)
/// - Write transformed files to output directory
struct TemplateExpander {
    private let fileSystem: any FileSysteming
    private let templateDirectory: AbsolutePath
    private let outputDirectory: AbsolutePath
    private let noora: any Noorable
    private let isInteractive: Bool
    private let force: Bool
    private let useAtomicWrite: Bool

    init(
        fileSystem: any FileSysteming,
        templateDirectory: AbsolutePath,
        outputDirectory: AbsolutePath,
        noora: some Noorable = Noora(),
        isInteractive: Bool = true,
        force: Bool = false,
        useAtomicWrite: Bool = true
    ) {
        self.fileSystem = fileSystem
        self.templateDirectory = templateDirectory
        self.outputDirectory = outputDirectory
        self.noora = noora
        self.isInteractive = isInteractive
        self.force = force
        self.useAtomicWrite = useAtomicWrite
    }

    /// Expands the template by copying and transforming all non-excluded files.
    ///
    /// When `useAtomicWrite` is true (default), files are first copied to a temporary directory,
    /// transformed in place, and then moved to the output directory atomically.
    ///
    /// When `useAtomicWrite` is false (transactional workspace mode), files are copied and
    /// transformed directly in the output directory since atomicity is already guaranteed
    /// by the transactional workspace.
    ///
    /// - Parameters:
    ///   - macros: Resolved macro values to substitute in filenames and contents
    ///   - outputs: Step outputs for evaluating exclude conditions (macros only are used for substitution)
    ///   - rules: Exclusion rules to skip certain files (nil means no exclusions)
    func expand(
        substituting macros: [ResolvedMacro],
        with outputs: StepOutputsStorage,
        excluding rules: [Config.ExcludeRule]? = nil
    ) async throws {
        let excludePatterns = try await makeExcludePatterns(
            from: rules,
            evaluatingWith: macros,
            and: outputs
        )

        // Collect files that will be generated (with transformed names)
        let filesToGenerate = try await collectFilesToGenerate(
            substituting: macros,
            with: outputs,
            excluding: excludePatterns
        )

        // Check for existing files in output directory
        let existingFiles = try await findExistingFiles(filesToGenerate)

        if !existingFiles.isEmpty {
            let shouldOverwrite = try await confirmOverwrite(existingFiles)
            if !shouldOverwrite {
                throw Error.overwriteCancelled
            }
        }

        if useAtomicWrite {
            // Atomic mode: copy to temp directory, transform, then move to output
            try await fileSystem.withAtomicCopyAndWrite(
                from: templateDirectory,
                to: outputDirectory
            ) { workingDirectory in
                try await removeConfigFile(in: workingDirectory)
                try await removeExcludedFiles(in: workingDirectory, matching: excludePatterns)
                try await transformFilenames(in: workingDirectory, substituting: macros, with: outputs)
                try await transformFileContents(in: workingDirectory, substituting: macros, with: outputs)
            }
        } else {
            // Direct mode (transactional workspace): copy and transform directly
            // Atomicity is guaranteed by the transactional workspace layer
            try await fileSystem.copy(templateDirectory, to: outputDirectory)
            try await removeConfigFile(in: outputDirectory)
            try await removeExcludedFiles(in: outputDirectory, matching: excludePatterns)
            try await transformFilenames(in: outputDirectory, substituting: macros, with: outputs)
            try await transformFileContents(in: outputDirectory, substituting: macros, with: outputs)
        }
    }

    /// Collects the list of files that will be generated (with transformed names).
    /// Only includes files, not directories.
    private func collectFilesToGenerate(
        substituting macros: [ResolvedMacro],
        with outputs: StepOutputsStorage,
        excluding patterns: [Glob.Pattern]
    ) async throws -> [String] {
        let allPaths = try await collectAllPaths(in: templateDirectory, relativeTo: templateDirectory)
        var result: [String] = []

        for (absolutePath, relativePath) in allPaths {
            // Skip directories - only include files
            let isDirectory = (try? await fileSystem.exists(absolutePath, isDirectory: true)) ?? false
            if isDirectory {
                continue
            }

            // Skip excluded files
            if isExcluded(relativePath, by: patterns) {
                continue
            }

            // Skip config.yml
            if relativePath == "config.yml" {
                continue
            }

            // Transform the filename
            let transformedPath = try await resolvingMacros(in: relativePath, substituting: macros, with: outputs)
            result.append(transformedPath)
        }

        return result
    }

    /// Finds files that already exist in the output directory.
    /// Only returns leaf paths (not parent directories of other generated files).
    private func findExistingFiles(_ filesToGenerate: [String]) async throws -> [String] {
        var existingFiles: [String] = []

        for relativePath in filesToGenerate {
            let fullPath = outputDirectory.appending(components: relativePath.split(separator: "/").map(String.init))
            if try await fileSystem.exists(fullPath) {
                existingFiles.append(relativePath)
            }
        }

        // Filter out parent directories (paths that are prefixes of other paths)
        return filterLeafPaths(existingFiles)
    }

    /// Filters out parent directories, keeping only leaf paths.
    /// For example, given ["Sources", "Sources/Module", "Sources/Module/File.swift"],
    /// returns only ["Sources/Module/File.swift"].
    private func filterLeafPaths(_ paths: [String]) -> [String] {
        paths.filter { path in
            let pathWithSlash = path + "/"
            // Keep this path only if no other path starts with it as a directory prefix
            return !paths.contains { other in
                other != path && other.hasPrefix(pathWithSlash)
            }
        }
    }

    /// Confirms whether to overwrite existing files.
    /// - Returns: `true` if should overwrite, `false` otherwise
    private func confirmOverwrite(_ existingFiles: [String]) async throws -> Bool {
        // If force flag is set, always overwrite
        if force {
            return true
        }

        // If interactive, prompt user
        if isInteractive {
            noora.passthrough("⚠️ The following files already exist and will be overwritten:\n", tab: 1)
            for file in existingFiles {
                noora.passthrough("  - \(file)\n", tab: 2)
            }
            return noora.yesOrNoChoicePrompt(
                title: "Overwrite",
                question: "Do you want to overwrite these files?"
            )
        }

        // Non-interactive without force: error
        throw Error.existingFilesWouldBeOverwritten(files: existingFiles)
    }

    /// Creates glob patterns from exclude rules, evaluating any conditional expressions.
    private func makeExcludePatterns(
        from rules: [Config.ExcludeRule]?,
        evaluatingWith macros: [ResolvedMacro],
        and outputs: StepOutputsStorage
    ) async throws -> [Glob.Pattern] {
        guard let rules else { return [] }

        var patterns: [Glob.Pattern] = []

        for rule in rules {
            switch rule {
            case let .path(pattern):
                try patterns.append(Glob.Pattern(pattern))

            case let .conditional(conditional):
                let evaluator = ConditionEvaluator(macros: macros, outputs: outputs)
                let shouldExclude = try await evaluator.evaluate(conditional.if)

                if shouldExclude {
                    for pattern in conditional.paths {
                        try patterns.append(Glob.Pattern(pattern))
                    }
                }
            }
        }

        return patterns
    }

    /// Removes the config.yml file from the working directory.
    private func removeConfigFile(in directory: AbsolutePath) async throws {
        let configPath = directory.appending(component: "config.yml")
        if try await fileSystem.exists(configPath) {
            try await fileSystem.remove(configPath)
        }
    }

    /// Removes files matching exclusion patterns from the working directory.
    private func removeExcludedFiles(
        in directory: AbsolutePath,
        matching patterns: [Glob.Pattern]
    ) async throws {
        guard !patterns.isEmpty else { return }

        let allPaths = try await collectAllPaths(in: directory, relativeTo: directory)

        // Sort by path length descending so we remove children before parents
        let sortedPaths = allPaths.sorted { $0.relativePath.count > $1.relativePath.count }

        for (absolutePath, relativePath) in sortedPaths {
            if isExcluded(relativePath, by: patterns) {
                try await fileSystem.remove(absolutePath)
            }
        }
    }

    /// Transforms filenames by substituting macros, processing depth-first.
    private func transformFilenames(
        in directory: AbsolutePath,
        substituting macros: [ResolvedMacro],
        with outputs: StepOutputsStorage
    ) async throws {
        let contents = try await fileSystem.contentsOfDirectory(directory)

        for item in contents {
            let isDirectory = (try? await fileSystem.exists(item, isDirectory: true)) ?? false

            // Process children first (depth-first)
            if isDirectory {
                try await transformFilenames(in: item, substituting: macros, with: outputs)
            }

            try await transformFilename(at: item, substituting: macros, with: outputs)
        }
    }

    /// Transforms a single file or directory name by substituting macros.
    private func transformFilename(
        at path: AbsolutePath,
        substituting macros: [ResolvedMacro],
        with outputs: StepOutputsStorage
    ) async throws {
        let originalName = path.basename
        let transformedName = try await resolvingMacros(in: originalName, substituting: macros, with: outputs)

        if transformedName != originalName {
            let newPath = path.parentDirectory.appending(component: transformedName)
            try await fileSystem.move(from: path, to: newPath)
        }
    }

    /// Transforms file contents by substituting macros.
    private func transformFileContents(
        in directory: AbsolutePath,
        substituting macros: [ResolvedMacro],
        with outputs: StepOutputsStorage
    ) async throws {
        let contents = try await fileSystem.contentsOfDirectory(directory)

        for item in contents {
            let isDirectory = (try? await fileSystem.exists(item, isDirectory: true)) ?? false

            if isDirectory {
                try await transformFileContents(in: item, substituting: macros, with: outputs)
            } else {
                try await transformFile(at: item, substituting: macros, with: outputs)
            }
        }
    }

    /// Transforms a single file's contents in place.
    private func transformFile(
        at path: AbsolutePath,
        substituting macros: [ResolvedMacro],
        with outputs: StepOutputsStorage
    ) async throws {
        let data = try await fileSystem.readFile(at: path)

        // Skip binary files
        guard let text = String(data: data, encoding: .utf8) else { return }

        let resolver = VariableResolver(macros: macros, outputs: outputs)
        let transformed = try await resolver.resolve(text)

        // Only write if changed
        if transformed != text {
            try await fileSystem.writeText(transformed, at: path, encoding: .utf8, options: [.overwrite])
        }
    }

    /// Collects all paths in a directory recursively.
    private func collectAllPaths(
        in directory: AbsolutePath,
        relativeTo root: AbsolutePath
    ) async throws -> [(absolutePath: AbsolutePath, relativePath: String)] {
        var result: [(AbsolutePath, String)] = []
        let contents = try await fileSystem.contentsOfDirectory(directory)

        for item in contents {
            let relativePath = item.pathString.replacingOccurrences(
                of: root.pathString + "/",
                with: ""
            )
            result.append((item, relativePath))

            let isDirectory = (try? await fileSystem.exists(item, isDirectory: true)) ?? false
            if isDirectory {
                try result.append(contentsOf: await collectAllPaths(in: item, relativeTo: root))
            }
        }

        return result
    }

    /// Resolves macros in the given text (step outputs are not supported in templates).
    private func resolvingMacros(
        in text: String,
        substituting macros: [ResolvedMacro],
        with outputs: StepOutputsStorage
    ) async throws -> String {
        let resolver = VariableResolver(macros: macros, outputs: outputs)
        return try await resolver.resolve(text)
    }

    /// Returns whether the given path matches any exclusion pattern.
    private func isExcluded(_ relativePath: String, by patterns: [Glob.Pattern]) -> Bool {
        patterns.contains { $0.match(relativePath) }
    }
}

extension TemplateExpander {
    enum Error: LocalizedError, Equatable {
        case overwriteCancelled
        case existingFilesWouldBeOverwritten(files: [String])

        var errorDescription: String? {
            switch self {
            case .overwriteCancelled:
                return "Operation cancelled by user."
            case let .existingFilesWouldBeOverwritten(files):
                var message = "The following files already exist and would be overwritten:\n"
                for file in files {
                    message += "  - \(file)\n"
                }
                message += "Use --force to overwrite existing files."
                return message
            }
        }
    }
}
