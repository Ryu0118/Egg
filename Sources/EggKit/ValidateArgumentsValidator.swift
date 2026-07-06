import FileManagerProtocol
import Foundation

package struct ValidateArgumentsValidator {
    private let templatePath: String
    private let fileManager: any FileManagerProtocol

    package init(
        templatePath: String,
        fileManager: some FileManagerProtocol,
    ) {
        self.templatePath = templatePath
        self.fileManager = fileManager
    }

    package func validate() async throws -> ValidateRunnerMode {
        let templateURL = URL(filePath: templatePath)

        if fileManager.exists(templateURL), !fileManager.isDirectory(at: templateURL) {
            throw Error.notADirectory(path: templatePath)
        }

        // ConfigLoader owns the exists/read/decode sequence and formats
        // decode failures with the exact key path, so validate reports
        // "missing required key 'hatch.output'" instead of Foundation's
        // bare "The data couldn't be read because it is missing."
        let config = try ConfigLoader(fileManager: fileManager).load(from: templateURL)

        return .direct(
            config: config,
            templatePath: templateURL,
        )
    }

    enum Error: LocalizedError {
        case notADirectory(path: String)

        var errorDescription: String? {
            switch self {
            case let .notADirectory(path):
                "Path is not a directory: \(path)"
            }
        }
    }
}

package enum ValidateRunnerMode: Codable {
    case direct(
        config: Config,
        templatePath: URL,
    )
    case mcp(
        config: Config,
        templatePath: URL,
    )
}
