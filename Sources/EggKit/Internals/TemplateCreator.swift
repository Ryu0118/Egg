import FileManagerProtocol
import Foundation
import Noora
import Yams

struct TemplateCreator {
    let fileManager: any FileManagerProtocol
    let skipConfig: Bool
    let validator = ConfigValidator()
    let templateLocating: any TemplateLocating

    init(
        skipConfig: Bool,
        templateLocating: some TemplateLocating,
        fileManager: some FileManagerProtocol
    ) {
        self.fileManager = fileManager
        self.skipConfig = skipConfig
        self.templateLocating = templateLocating
    }

    func create(_ name: String, description: String, in locationType: TemplateLocationType) async throws {
        let templateDir = templateLocating.template(name, type: locationType)

        var createdPaths: [URL] = []
        var directoryCreated = false

        do {
            try fileManager.createDirectory(at: templateDir, withIntermediateDirectories: true)
            directoryCreated = true

            let filePath = try createDefaultFile(templateDir)
            createdPaths.append(filePath)

            let configPath = try await createDefaultConfig(templateDir, name: name, description: description)
            createdPaths.append(configPath)
        } catch {
            // Rollback: delete all created files and directory on failure
            for path in createdPaths.reversed() {
                try? fileManager.removeItem(at: path)
            }
            if directoryCreated {
                try? fileManager.removeItem(at: templateDir)
            }
            throw error
        }
    }

    private func createDefaultConfig(
        _ templateDir: URL,
        name: String,
        description: String
    ) async throws -> URL {
        let defaultConfigPath = templateDir.appendingPathComponent("config.yml")
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

        #  - name: ___ITEM_NAME___
        #    description: Name of the item to generate
        #    type: string

        # pre_hatch:
        #  - id: compute-path
        #    run: |
        #      ITEM_PATH="___OUTPUT___/items/___ITEM_NAME___"
        #      echo "item-path=$ITEM_PATH"
        hatch:
          output: ___OUTPUT___
          exclude:
        #    - README.md

        # post_hatch:
        #  - run: echo "You can use step outputs like: ${{ pre_hatch.compute-path.outputs.item-path }}"
        """
        do {
            let decoded = try YAMLDecoder().decode(Config.self, from: yamlContent)
            try await validator.validate(decoded)
        } catch {
            throw Error.invalidNameOrDescription
        }
        try fileManager.writeText(yamlContent, at: defaultConfigPath)
        return defaultConfigPath
    }

    private func createDefaultFile(_ templateDir: URL) throws -> URL {
        let defaultFilePath = templateDir.appendingPathComponent("___FILE_NAME___View.swift")
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
        try fileManager.writeText(defaultFileContent, at: defaultFilePath)
        return defaultFilePath
    }

    enum Error: LocalizedError {
        case invalidNameOrDescription

        var errorDescription: String? {
            switch self {
            case .invalidNameOrDescription:
                "Invalid name or description detected. \nPlease change a name or description and try again. "
            }
        }
    }
}
