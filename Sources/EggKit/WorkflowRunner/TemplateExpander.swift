import FileManagerProtocol
import Foundation
import Glob
import Noora

/// Expands template files by substituting macros and copying to output directory.
///
/// Responsibilities:
/// - Recursively traverse template directory
/// - Substitute macros in filenames and directory names
/// - Substitute macros and step outputs in file contents
/// - Apply glob exclusion patterns (conditional and unconditional)
/// - Write transformed files to output directory
struct TemplateExpander {
    private let fileManager: any FileManagerProtocol
    private let templateDirectory: URL
    private let outputDirectory: URL
    private let builtInMacroContext: BuiltInMacroContext
    private let noora: any Noorable
    private let isInteractive: Bool
    private let override: Bool

    init(
        fileManager: some FileManagerProtocol,
        templateDirectory: URL,
        outputDirectory: URL,
        builtInMacroContext: BuiltInMacroContext,
        noora: some Noorable = Noora(),
        isInteractive: Bool = true,
        override: Bool = false
    ) {
        self.fileManager = fileManager
        self.templateDirectory = templateDirectory
        self.outputDirectory = outputDirectory
        self.builtInMacroContext = builtInMacroContext
        self.noora = noora
        self.isInteractive = isInteractive
        self.override = override
    }

    /// Expands the template by copying and transforming all non-excluded files.
    ///
    /// Files are first copied to a temporary directory, transformed in place,
    /// and then moved to the output directory atomically.
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
        let existingFiles = try findExistingFiles(filesToGenerate)

        if !existingFiles.isEmpty {
            let shouldOverwrite = try await confirmOverwrite(existingFiles)
            if !shouldOverwrite {
                throw Error.overwriteCancelled
            }
        }

        try await fileManager.withAtomicCopyAndWrite(
            from: templateDirectory,
            to: outputDirectory
        ) { workingDirectory in
            try removeConfigFile(in: workingDirectory)
            try removeExcludedFiles(in: workingDirectory, matching: excludePatterns)
            try await transformFilenames(in: workingDirectory, substituting: macros, with: outputs)
            try await transformFileContents(in: workingDirectory, substituting: macros, with: outputs)
        }
    }

    /// Collects the list of files that will be generated (with transformed names).
    /// Only includes files, not directories.
    private func collectFilesToGenerate(
        substituting macros: [ResolvedMacro],
        with outputs: StepOutputsStorage,
        excluding patterns: [Glob.Pattern]
    ) async throws -> [String] {
        let allPaths = try collectAllPaths(in: templateDirectory, relativeTo: templateDirectory)
        var result: [String] = []

        for (absolutePath, relativePath) in allPaths {
            // Skip directories - only include files
            let isDirectory = fileManager.isDirectory(at: absolutePath)
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
    private func findExistingFiles(_ filesToGenerate: [String]) throws -> [String] {
        var existingFiles: [String] = []

        for relativePath in filesToGenerate {
            let fullPath = outputDirectory.appending(path: relativePath)
            if fileManager.exists(fullPath) {
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
        // If override flag is set, always overwrite
        if override {
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

        // Non-interactive without override: error
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
                let evaluator = ConditionEvaluator(
                    macros: macros,
                    outputs: outputs,
                    builtInMacroContext: builtInMacroContext
                )
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
    private func removeConfigFile(in directory: URL) throws {
        let configPath = directory.appending(component: "config.yml")
        if fileManager.exists(configPath) {
            try fileManager.removeItem(at: configPath)
        }
    }

    /// Removes files matching exclusion patterns from the working directory.
    private func removeExcludedFiles(
        in directory: URL,
        matching patterns: [Glob.Pattern]
    ) throws {
        guard !patterns.isEmpty else { return }

        let allPaths = try collectAllPaths(in: directory, relativeTo: directory)

        // Sort by path length descending so we remove children before parents
        let sortedPaths = allPaths.sorted { $0.relativePath.count > $1.relativePath.count }

        for (absolutePath, relativePath) in sortedPaths {
            if isExcluded(relativePath, by: patterns) {
                try fileManager.removeItem(at: absolutePath)
            }
        }
    }

    /// Transforms filenames by substituting macros, processing depth-first.
    private func transformFilenames(
        in directory: URL,
        substituting macros: [ResolvedMacro],
        with outputs: StepOutputsStorage
    ) async throws {
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])

        for item in contents {
            let isDirectory = fileManager.isDirectory(at: item)

            // Process children first (depth-first)
            if isDirectory {
                try await transformFilenames(in: item, substituting: macros, with: outputs)
            }

            try await transformFilename(at: item, substituting: macros, with: outputs)
        }
    }

    /// Transforms a single file or directory name by substituting macros.
    private func transformFilename(
        at path: URL,
        substituting macros: [ResolvedMacro],
        with outputs: StepOutputsStorage
    ) async throws {
        let originalName = path.lastPathComponent
        let transformedName = try await resolvingMacros(in: originalName, substituting: macros, with: outputs)

        if transformedName != originalName {
            let newPath = path.deletingLastPathComponent().appending(component: transformedName)
            try fileManager.moveItem(at: path, to: newPath)
        }
    }

    /// Transforms file contents by substituting macros.
    private func transformFileContents(
        in directory: URL,
        substituting macros: [ResolvedMacro],
        with outputs: StepOutputsStorage
    ) async throws {
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])

        for item in contents {
            let isDirectory = fileManager.isDirectory(at: item)

            if isDirectory {
                try await transformFileContents(in: item, substituting: macros, with: outputs)
            } else {
                try await transformFile(at: item, substituting: macros, with: outputs)
            }
        }
    }

    /// Transforms a single file's contents in place.
    private func transformFile(
        at path: URL,
        substituting macros: [ResolvedMacro],
        with outputs: StepOutputsStorage
    ) async throws {
        let data = try fileManager.readFile(at: path)

        // Skip binary files
        guard let text = String(data: data, encoding: .utf8) else { return }

        let resolver = VariableResolver(
            macros: macros,
            outputs: outputs,
            builtInMacroContext: builtInMacroContext
        )
        let transformed = try await resolver.resolve(text)

        // Only write if changed
        if transformed != text {
            try fileManager.writeText(transformed, at: path, encoding: .utf8)
        }
    }

    /// Collects all paths in a directory recursively.
    private func collectAllPaths(
        in directory: URL,
        relativeTo root: URL
    ) throws -> [(absolutePath: URL, relativePath: String)] {
        var result: [(URL, String)] = []
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])

        for item in contents {
            let relativePath = item.relativePath(from: root)
            result.append((item, relativePath))

            let isDirectory = fileManager.isDirectory(at: item)
            if isDirectory {
                try result.append(contentsOf: collectAllPaths(in: item, relativeTo: root))
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
        let resolver = VariableResolver(
            macros: macros,
            outputs: outputs,
            builtInMacroContext: builtInMacroContext
        )
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
                message += "Use --override to overwrite existing files."
                return message
            }
        }
    }
}
