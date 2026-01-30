import FileManagerProtocol
import Foundation
import Yams

/// Loads and decodes config.yml files from template directories.
package struct ConfigLoader {
    private let fileManager: any FileManagerProtocol

    package init(fileManager: some FileManagerProtocol = FileManager.default) {
        self.fileManager = fileManager
    }

    /// Loads a Config from the specified template directory.
    ///
    /// - Parameter templatePath: The path to the template directory containing config.yml
    /// - Returns: The decoded Config
    /// - Throws: `ConfigLoaderError` if the config file is not found or cannot be decoded
    package func load(from templatePath: URL) throws -> Config {
        let configPath = templatePath.appendingPathComponent("config.yml")
        return try load(configPath: configPath)
    }

    /// Loads a Config from the specified config.yml path.
    ///
    /// - Parameter configPath: The path to the config.yml file
    /// - Returns: The decoded Config
    /// - Throws: `ConfigLoaderError` if the config file is not found or cannot be decoded
    package func load(configPath: URL) throws -> Config {
        guard fileManager.exists(configPath) else {
            throw ConfigLoaderError.configNotFound(path: configPath.path(percentEncoded: false))
        }

        let data = try fileManager.readFile(at: configPath)

        do {
            return try YAMLDecoder().decode(Config.self, from: data)
        } catch {
            throw ConfigLoaderError.decodingFailed(path: configPath.path(percentEncoded: false), underlying: error)
        }
    }
}

/// Errors that can occur when loading a config file.
package enum ConfigLoaderError: Error, LocalizedError, Sendable {
    case configNotFound(path: String)
    case decodingFailed(path: String, underlying: Error)

    package var errorDescription: String? {
        switch self {
        case .configNotFound(let path):
            "config.yml not found at path: \(path)"
        case .decodingFailed(let path, let underlying):
            "Failed to decode config.yml at \(path): \(underlying.localizedDescription)"
        }
    }
}
