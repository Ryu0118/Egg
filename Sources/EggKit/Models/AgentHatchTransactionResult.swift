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

public struct AgentHatchDiscardResult: Codable, Sendable, Equatable {
    public let status: String
    public let applyToken: String
    public let rollbackId: String?

    /// The changes the transaction had recorded, whatever its state at
    /// discard time — a rolledBack transaction's changes are not applied
    /// anywhere, so this must not be called "appliedChanges".
    public let discardedChanges: [AgentChangeEntry]

    public let warnings: [AgentTransactionWarning]

    public init(
        status: String,
        applyToken: String,
        rollbackId: String?,
        discardedChanges: [AgentChangeEntry],
        warnings: [AgentTransactionWarning] = [],
    ) {
        self.status = status
        self.applyToken = applyToken
        self.rollbackId = rollbackId
        self.discardedChanges = discardedChanges
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

public struct AgentHatchTransactionsResult: Codable, Sendable, Equatable {
    public let status: String
    public let workingDirectory: String
    public let transactions: [AgentHatchTransactionSummary]

    public init(
        status: String,
        workingDirectory: String,
        transactions: [AgentHatchTransactionSummary],
    ) {
        self.status = status
        self.workingDirectory = workingDirectory
        self.transactions = transactions
    }
}

/// Every state a listed transaction record can be in: the live state-machine
/// statuses, plus the two states only the listing can surface.
public enum AgentHatchTransactionStatus: String, Codable, Sendable, Equatable {
    case preview
    case applied
    case rolledBack
    /// metadata.json exists but cannot be decoded.
    case corrupt
    /// A rollback bundle whose transaction directory is gone — left by
    /// pre-unification egg versions.
    case orphanedRollback
}

public struct AgentHatchTransactionSummary: Codable, Sendable, Equatable {
    public let token: String
    public let status: AgentHatchTransactionStatus
    public let templateName: String?
    /// Disk footprint of the transaction directory plus its rollback bundle.
    /// Computed only when the listing was asked for sizes (CLI `--size`,
    /// MCP `include_sizes: true`) — it walks the full trees; nil otherwise.
    public let sizeBytes: Int?
    public let hasRollbackBundle: Bool

    public init(
        token: String,
        status: AgentHatchTransactionStatus,
        templateName: String?,
        sizeBytes: Int?,
        hasRollbackBundle: Bool,
    ) {
        self.token = token
        self.status = status
        self.templateName = templateName
        self.sizeBytes = sizeBytes
        self.hasRollbackBundle = hasRollbackBundle
    }
}

public struct AgentChangeEntry: Codable, Sendable, Equatable {
    public let path: String
    public let kind: String
    /// Unified diff for this change, present only when previewed with `--diff`.
    public let diff: String?

    public init(path: String, kind: String, diff: String? = nil) {
        self.path = path
        self.kind = kind
        self.diff = diff
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
