import Foundation
import Yams
import FileSystem
import Path
// import Config

struct TemplateCreator {
    let fileSystem: any FileSysteming
    let encoder: YAMLEncoder = .defaultEncoder()
    let skipConfig: Bool
    let templateLocating: any TemplateLocating

    init(
        skipConfig: Bool,
        templateLocating: some TemplateLocating,
        fileSystem: some FileSysteming
    ) {
        self.fileSystem = fileSystem
        self.skipConfig = skipConfig
        self.templateLocating = templateLocating
    }

    func create(_ name: String, description: String, in locationType: TemplateLocationType) async throws {
        let templateDir = templateLocating.template(name, type: locationType)

        var createdPaths: [AbsolutePath] = []
        var directoryCreated = false

        do {
            try await fileSystem.makeDirectory(at: templateDir, options: [.createTargetParentDirectories])
            directoryCreated = true

            let filePath = try await createDefaultFile(templateDir)
            createdPaths.append(filePath)

            let configPath = try await createDefaultConfig(templateDir, name: name, description: description)
            createdPaths.append(configPath)
        } catch {
            // Rollback: delete all created files and directory on failure
            for path in createdPaths.reversed() {
                try? await fileSystem.remove(path)
            }
            if directoryCreated {
                try? await fileSystem.remove(templateDir)
            }
            throw error
        }
    }

    private func createDefaultConfig(_ templateDir: AbsolutePath, name: String, description: String) async throws -> AbsolutePath {
        let defaultConfigPath = templateDir.appending(component: "config.yml")
        let yamlContent = """
name: \(name)
description: \(description)

# Define custom macros that can be used throughout your template files and in this config file.
# Macros defined here can be referenced in file names, folder names, file contents, and
# within this config.yaml (e.g., in pre_hatch, hatch, post_hatch sections) using the format
# ___MACRO_NAME___. When you run 'egg hatch', you'll be prompted to provide values for these
# macros, which will then replace all occurrences in your template and configuration.
macros:
  - name: ___FILE_NAME___
    description: The name of the file to be generated
    type: string
  - name: ___OUTPUT___
    description: Template output directory where generated files will be placed
    type: path

#  - name: ___CREATE_TESTS___
#    description: Whether to create test files
#    type: boolean
#    default: false

# pre_hatch:
#  - id: setup-dirs
#    run: |
#      echo "test-dir=___OUTPUT___/Tests"
#  - if: ___CREATE_TESTS___
#    run: mkdir -p ${{ pre_hatch.setup-dirs.outputs.test-dir }}
hatch:
  output: ___OUTPUT___

# post_hatch:
#  - if: ___CREATE_TESTS___
#    run: swift package resolve
"""
        try await fileSystem.writeText(yamlContent, at: defaultConfigPath)
        return defaultConfigPath
    }

    private func createDefaultFile(_ templateDir: AbsolutePath) async throws -> AbsolutePath {
        let defaultFilePath = templateDir.appending(component: "___FILE_NAME___View.swift")
        let defaultFileContent = """
// Available default macros:
//   - ___DATE___: Current date in default format
//   - ___DATE(yyyyMMdd)___: Current date in custom format
//   - ___SYSTEM_USER___: System username
//
// You can also define custom macros (e.g., ___USER_DEFINED___, ___FILE_NAME___) and provide values via:
//   - Command line: egg use <template-name> --user-defined foo --file-name bar
//   - Interactive prompt: will be asked during 'egg use' command

struct ___FILE_NAME___View: View {
    var body: some View {
        Text("___FILE_NAME___View")
    }
}
"""
        try await fileSystem.writeText(defaultFileContent, at: defaultFilePath)
        return defaultFilePath
    }
}


