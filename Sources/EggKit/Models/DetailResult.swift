import Foundation

/// Result of getting template details for MCP mode.
public struct DetailResult: Codable, Sendable {
    /// Basic template information
    public let basicInfo: BasicInfo

    /// Macro definitions
    public let macros: [MacroInfo]

    /// Example CLI command to hatch this template
    public let exampleCliCommand: String

    /// Example MCP arguments for hatching
    public let exampleMcpArguments: ExampleMcpArguments

    public init(
        basicInfo: BasicInfo,
        macros: [MacroInfo],
        exampleCliCommand: String,
        exampleMcpArguments: ExampleMcpArguments
    ) {
        self.basicInfo = basicInfo
        self.macros = macros
        self.exampleCliCommand = exampleCliCommand
        self.exampleMcpArguments = exampleMcpArguments
    }

    /// Basic template information
    public struct BasicInfo: Codable, Sendable {
        public let name: String
        public let description: String
        public let version: String?
        public let locationName: String
        public let locationDir: String
        public let path: String

        public init(
            name: String,
            description: String,
            version: String?,
            locationName: String,
            locationDir: String,
            path: String
        ) {
            self.name = name
            self.description = description
            self.version = version
            self.locationName = locationName
            self.locationDir = locationDir
            self.path = path
        }
    }

    /// Macro information
    public struct MacroInfo: Codable, Sendable {
        public let name: String
        public let flag: String
        public let type: String
        public let description: String
        public let defaultValue: String?
        public let choices: [String]?
        public let validation: String?

        public init(
            name: String,
            flag: String,
            type: String,
            description: String,
            defaultValue: String?,
            choices: [String]?,
            validation: String?
        ) {
            self.name = name
            self.flag = flag
            self.type = type
            self.description = description
            self.defaultValue = defaultValue
            self.choices = choices
            self.validation = validation
        }
    }

    /// Example MCP arguments for the hatch tool
    public struct ExampleMcpArguments: Codable, Sendable {
        public let templateName: String
        public let macros: [String: String]

        public init(templateName: String, macros: [String: String]) {
            self.templateName = templateName
            self.macros = macros
        }
    }
}
