import Foundation

public struct AgentHatchPreviewResult: Codable, Sendable, Equatable {
    public let status: String
    public let applyToken: String
    public let templateName: String
    public let workingDirectory: String
    public let outputDirectory: String
    public let strategy: String
    public let rollbackGuarantee: String
    public let changes: [AgentChangeEntry]
    public let warnings: [AgentTransactionWarning]
    public let nextCommands: AgentTransactionCommands

    public init(
        status: String = "preview",
        applyToken: String,
        templateName: String,
        workingDirectory: String,
        outputDirectory: String,
        strategy: String,
        rollbackGuarantee: String,
        changes: [AgentChangeEntry],
        warnings: [AgentTransactionWarning],
        nextCommands: AgentTransactionCommands,
    ) {
        self.status = status
        self.applyToken = applyToken
        self.templateName = templateName
        self.workingDirectory = workingDirectory
        self.outputDirectory = outputDirectory
        self.strategy = strategy
        self.rollbackGuarantee = rollbackGuarantee
        self.changes = changes
        self.warnings = warnings
        self.nextCommands = nextCommands
    }
}

public struct AgentHatchApplyResult: Codable, Sendable, Equatable {
    public let status: String
    public let applyToken: String
    public let rollbackId: String?
    public let appliedChanges: [AgentChangeEntry]
    public let warnings: [AgentTransactionWarning]

    public init(
        status: String,
        applyToken: String,
        rollbackId: String?,
        appliedChanges: [AgentChangeEntry],
        warnings: [AgentTransactionWarning] = [],
    ) {
        self.status = status
        self.applyToken = applyToken
        self.rollbackId = rollbackId
        self.appliedChanges = appliedChanges
        self.warnings = warnings
    }
}

public struct AgentHatchRollbackResult: Codable, Sendable, Equatable {
    public let status: String
    public let rollbackId: String
    public let restoredChanges: [AgentChangeEntry]

    public init(
        status: String,
        rollbackId: String,
        restoredChanges: [AgentChangeEntry],
    ) {
        self.status = status
        self.rollbackId = rollbackId
        self.restoredChanges = restoredChanges
    }
}

public struct AgentChangeEntry: Codable, Sendable, Equatable {
    public let path: String
    public let kind: String

    public init(path: String, kind: String) {
        self.path = path
        self.kind = kind
    }
}

public struct AgentTransactionWarning: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public let paths: [String]?

    public init(code: String, message: String, paths: [String]? = nil) {
        self.code = code
        self.message = message
        self.paths = paths
    }
}

public struct AgentTransactionCommands: Codable, Sendable, Equatable {
    public let apply: String
    public let discard: String

    public init(apply: String, discard: String) {
        self.apply = apply
        self.discard = discard
    }
}
