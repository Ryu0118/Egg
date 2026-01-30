import FileManagerProtocol
import Foundation
import Yams

package struct ValidateArgumentsValidator {
    private let templatePath: String
    private let fileManager: any FileManagerProtocol
    private let decoder = YAMLDecoder()

    package init(
        templatePath: String,
        fileManager: some FileManagerProtocol
    ) {
        self.templatePath = templatePath
        self.fileManager = fileManager
    }

    package func validate() async throws -> ValidateRunnerMode {
        let templateURL = URL(filePath: templatePath)
        let configPath = templateURL.appendingPathComponent("config.yml")

        guard fileManager.exists(configPath) else {
            throw Error.configNotFound(path: configPath.path)
        }

        guard fileManager.isDirectory(at: templateURL) else {
            throw Error.notADirectory(path: templatePath)
        }

        let data = try fileManager.readFile(at: configPath)
        let config = try decoder.decode(Config.self, from: data)

        return .direct(
            config: config,
            templatePath: templateURL
        )
    }

    enum Error: LocalizedError {
        case configNotFound(path: String)
        case notADirectory(path: String)

        var errorDescription: String? {
            switch self {
            case let .configNotFound(path):
                return "config.yml not found at path: \(path)"
            case let .notADirectory(path):
                return "Path is not a directory: \(path)"
            }
        }
    }
}

package enum ValidateRunnerMode: Codable {
    case direct(
        config: Config,
        templatePath: URL
    )
    case mcp(
        config: Config,
        templatePath: URL
    )
}
