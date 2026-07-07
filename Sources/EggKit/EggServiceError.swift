import Foundation

public enum EggServiceError: Error, LocalizedError, Sendable {
    case invalidLocation(String)
    case invalidGitURL(String)
    case refNotAllowedForLocalPath(String)
    case sandboxPermissionRequired(paths: [String], templateName: String)
    case sandboxDisableRequiresConfirmation(templateName: String)
    case stagedHatchRequiresGitRepository(path: String, fileCount: Int, isExact: Bool)
    case stagedHatchTooLarge(path: String, fileCount: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidLocation(location):
            "Invalid location '\(location)'. Must be 'global' or 'project'."
        case let .stagedHatchRequiresGitRepository(path, fileCount, isExact):
            "'\(path)' is not a git repository. A staged hatch would copy all \(fileCount)\(isExact ? "" : "+") files in that directory — no .gitignore filtering, so build artifacts and caches are included — twice. Recommended: run 'git init' in '\(path)' so staging follows .gitignore. To proceed anyway, pass allow_non_git_staging: true (a count above the size guard additionally needs allow_large_staging: true), or pass use_staging: false to write directly (no preview or rollback)."
        case let .stagedHatchTooLarge(path, fileCount, limit):
            "Staging '\(path)' would clone \(fileCount) files (guard limit: \(limit)) — twice. Scope it down with staging_root pointing at a smaller directory, pass allow_large_staging: true to proceed anyway, or pass use_staging: false to write directly."
        case let .invalidGitURL(url):
            "Invalid Git URL: \(url)"
        case let .refNotAllowedForLocalPath(source):
            "A git ref cannot be used with the local path '\(source)': local sources copy the directory as-is. Use a git URL (e.g. file://\(source)) to install from a specific branch, tag, or commit."
        case let .sandboxPermissionRequired(paths, templateName):
            """
            ⚠️ SANDBOX EXTENDED WRITE ACCESS REQUIRED

            This template requires write access to paths outside the sandbox:
            \(paths.map { "  - \($0)" }.joined(separator: "\n"))

            To proceed:
            1. Run in interactive mode: egg hatch \(templateName)
            2. Or use --no-sandbox flag with explicit user permission

            MCP/direct mode cannot grant extended sandbox permissions automatically.
            """
        case let .sandboxDisableRequiresConfirmation(templateName):
            """
            SANDBOX DISABLED CONFIRMATION REQUIRED

            Ask the user whether to run 'egg hatch' without sandbox protection for template: \(templateName)
            Do not classify the script contents yourself; require explicit user approval.

            If user approves, call this tool again with 'user_confirmed_no_sandbox: true'
            """
        }
    }
}

extension Config.MacroDefaultValue {
    var asStringArray: [String] {
        switch self {
        case let .string(value):
            [value]
        case let .array(values):
            values
        }
    }
}

@available(*, deprecated, renamed: "EggServiceError")
public typealias MCPServiceError = EggServiceError
