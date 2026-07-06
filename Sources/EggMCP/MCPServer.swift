import Foundation
import MCP

/// MCP Server for egg template operations.
/// Provides tools for listing, creating, hatching, and managing egg templates.
public struct EggMCPServer {
    /// All available tool definitions
    public static let tools: [Tool] = [
        Tool(
            name: "egg_template_list",
            description: "Lists all available egg templates from global, project, and custom search paths.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "location": .object([
                        "type": "string",
                        "description": "Filter by location: 'global' or 'project'. If not specified, lists all.",
                    ]),
                    "project_directory": .object([
                        "type": "string",
                        "description": "Project directory path. Defaults to current working directory.",
                    ]),
                    "template_search_paths": .object([
                        "type": "array",
                        "items": .object(["type": "string"]),
                        "description": "Additional paths to search for templates.",
                    ]),
                ]),
                "required": .array([]),
            ]),
        ),
        Tool(
            name: "egg_template_detail",
            description: "Returns detailed information about a specific template, including macro definitions and example usage.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "template_name": .object([
                        "type": "string",
                        "description": "Name of the template to get details for.",
                    ]),
                    "project_directory": .object([
                        "type": "string",
                        "description": "Project directory path.",
                    ]),
                    "template_search_paths": .object([
                        "type": "array",
                        "items": .object(["type": "string"]),
                        "description": "Additional paths to search for templates.",
                    ]),
                ]),
                "required": .array(["template_name"]),
            ]),
        ),
        Tool(
            name: "egg_hatch",
            description: """
            Legacy one-shot hatch tool. Prefer egg_hatch_preview followed by egg_hatch_apply for agent workflows.

            IMPORTANT: Before calling this tool, ALWAYS call egg_template_detail first to get the required macros.
            The detail response includes exampleMcpArguments showing the exact format to use for the macros parameter.
            """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "template_name": .object([
                        "type": "string",
                        "description": "Name of the template to hatch.",
                    ]),
                    "macros": .object([
                        "type": "object",
                        "description": """
                        Object containing macro name-value pairs.
                        IMPORTANT: Keys MUST use the ___UPPER_SNAKE_CASE___ format with triple underscores.
                        Example: {"___MODULE_NAME___": "MyModule", "___INCLUDE_TESTS___": "true"}
                        Get the exact macro names from egg_template_detail's exampleMcpArguments.
                        """,
                        "additionalProperties": .object(["type": "string"]),
                    ]),
                    "output_directory": .object([
                        "type": "string",
                        "description": "Directory where files will be created. Defaults to current working directory.",
                    ]),
                    "staging_root": .object([
                        "type": "string",
                        "description": "Directory the staging clones from and applies back into, instead of the working directory. Use this when template outputs target a different directory, or to scope staging to a subdirectory of a large repository. In the default preview mode the transaction records (.egg) are stored under this directory — pass the same path as working_directory to egg_hatch_apply.",
                    ]),
                    "project_directory": .object([
                        "type": "string",
                        "description": "Project directory path.",
                    ]),
                    "template_search_paths": .object([
                        "type": "array",
                        "items": .object(["type": "string"]),
                        "description": "Additional paths to search for templates.",
                    ]),
                    "use_staging": .object([
                        "type": "boolean",
                        "description": "Use staging area for atomic operations. Default: true.",
                    ]),
                    "apply_changes": .object([
                        "type": "boolean",
                        "description": "Apply changes immediately. Default: false; when false, egg_hatch returns the same transaction preview shape as egg_hatch_preview.",
                    ]),
                    "disable_sandbox": .object([
                        "type": "boolean",
                        "description": "Disable the sandbox-exec safety guard for lifecycle scripts. Before setting this, ask the user whether to run without sandbox protection; do not classify script contents yourself. Requires user_confirmed_no_sandbox: true.",
                    ]),
                    "user_confirmed_no_sandbox": .object([
                        "type": "boolean",
                        "description": "Set to true only after the user explicitly approves running lifecycle scripts without sandbox protection.",
                    ]),
                ]),
                "required": .array(["template_name"]),
            ]),
        ),
        Tool(
            name: "egg_hatch_preview",
            description: """
            Agent-safe hatch entrypoint. Runs the template in staging, returns a JSON change preview and an apply_token, and does not modify the target project except for storing the transaction under .egg/transactions.

            REQUIRED FLOW:
            1. Call egg_template_detail first.
            2. Copy exact macro keys from exampleMcpArguments.macros. Keys use ___UPPER_SNAKE_CASE___.
            3. Call egg_hatch_preview.
            4. Inspect changes/warnings.
            5. Call egg_hatch_apply with apply_token only when the caller approves.
            """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "template_name": .object([
                        "type": "string",
                        "description": "Name of the template to hatch.",
                    ]),
                    "macros": .object([
                        "type": "object",
                        "description": "Macro name-value pairs. Keys MUST exactly match template macro names such as ___MODULE_NAME___.",
                        "additionalProperties": .object(["type": "string"]),
                    ]),
                    "output_directory": .object([
                        "type": "string",
                        "description": "Project directory where the transaction should be prepared. Defaults to current working directory.",
                    ]),
                    "project_directory": .object([
                        "type": "string",
                        "description": "Directory used to resolve project-local templates.",
                    ]),
                    "template_search_paths": .object([
                        "type": "array",
                        "items": .object(["type": "string"]),
                        "description": "Additional paths to search for templates.",
                    ]),
                    "include": .object([
                        "type": "array",
                        "items": .object(["type": "string"]),
                        "description": "Git pathspecs to force into the change set even if .gitignore would exclude them (e.g. dist/bundle.js).",
                    ]),
                    "exclude": .object([
                        "type": "array",
                        "items": .object(["type": "string"]),
                        "description": "Git pathspecs to exclude from the change set (e.g. docs/**).",
                    ]),
                    "include_diff": .object([
                        "type": "boolean",
                        "description": "When true, each change carries its unified diff so you can review the exact content before applying. Default: false.",
                    ]),
                    "disable_sandbox": .object([
                        "type": "boolean",
                        "description": "Disable the sandbox-exec safety guard for preview lifecycle scripts. Before setting this, ask the user whether to run without sandbox protection; do not classify script contents yourself. Requires user_confirmed_no_sandbox: true.",
                    ]),
                    "user_confirmed_no_sandbox": .object([
                        "type": "boolean",
                        "description": "Set to true only after the user explicitly approves previewing lifecycle scripts without sandbox protection.",
                    ]),
                    "allowed_write_paths": .object([
                        "type": "array",
                        "items": .object(["type": "string"]),
                        "description": "External paths (absolute) the user approved for write access. Each must appear in the template's declared sandbox.allowed_paths. When the preview fails with SANDBOX EXTENDED WRITE ACCESS REQUIRED, show the listed paths to the user, ask for approval, and retry with only the approved paths. Do not approve paths yourself. Writes to these paths happen during preview and are not reverted by discard/rollback.",
                    ]),
                ]),
                "required": .array(["template_name"]),
            ]),
        ),
        Tool(
            name: "egg_hatch_apply",
            description: "Applies a transaction returned by egg_hatch_preview. Also re-applies a rolled-back transaction with the same apply_token (a fresh rollback bundle replaces the consumed one). This is the only MCP hatch tool that should write previewed changes to the project.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "apply_token": .object([
                        "type": "string",
                        "description": "Token returned by egg_hatch_preview.applyToken.",
                    ]),
                    "working_directory": .object([
                        "type": "string",
                        "description": "Project directory that contains the .egg/transactions entry. Defaults to current working directory.",
                    ]),
                    "force": .object([
                        "type": "boolean",
                        "description": "Apply even if files changed since preview. Default: false.",
                    ]),
                ]),
                "required": .array(["apply_token"]),
            ]),
        ),
        Tool(
            name: "egg_hatch_rollback",
            description: "Rolls back an applied hatch transaction using the rollback_id returned by egg_hatch_apply. After rollback the transaction can be re-applied with egg_hatch_apply using the same apply_token.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "rollback_id": .object([
                        "type": "string",
                        "description": "Rollback id returned by egg_hatch_apply.rollbackId.",
                    ]),
                    "working_directory": .object([
                        "type": "string",
                        "description": "Project directory that contains the .egg/rollback entry. Defaults to current working directory.",
                    ]),
                    "force": .object([
                        "type": "boolean",
                        "description": "Roll back even if files were hand-edited since the apply (overwrites those edits). Default: false.",
                    ]),
                ]),
                "required": .array(["rollback_id"]),
            ]),
        ),
        Tool(
            name: "egg_hatch_discard",
            description: "Deletes a hatch transaction and its rollback bundle from any state (preview, applied, rolledBack). Applied files in the working directory are never touched. For an 'applied' transaction, force: true is required because deleting removes the only way to undo the apply.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "apply_token": .object([
                        "type": "string",
                        "description": "Token returned by egg_hatch_preview.applyToken.",
                    ]),
                    "working_directory": .object([
                        "type": "string",
                        "description": "Project directory that contains the .egg/transactions entry. Defaults to current working directory.",
                    ]),
                    "force": .object([
                        "type": "boolean",
                        "description": "Required when discarding an 'applied' transaction: deleting it removes the rollback bundle, so the apply can no longer be undone. Ask the user before setting this. Default: false.",
                    ]),
                ]),
                "required": .array(["apply_token"]),
            ]),
        ),
        Tool(
            name: "egg_hatch_transactions",
            description: "Lists hatch transaction records under .egg/ with status (preview, applied, rolledBack, corrupt, orphanedRollback) and template name — including orphaned rollback bundles left by older egg versions. Use egg_hatch_discard to delete entries that are no longer needed.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "working_directory": .object([
                        "type": "string",
                        "description": "Project directory that contains the .egg directory. Defaults to current working directory.",
                    ]),
                    "include_sizes": .object([
                        "type": "boolean",
                        "description": "Also compute each record's disk footprint (sizeBytes). Walks the full staged trees, so it can be slow on large histories. Default: false.",
                    ]),
                ]),
                "required": .array([]),
            ]),
        ),
        Tool(
            name: "egg_template_create",
            description: "Creates a new empty template with the specified name and description.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "name": .object([
                        "type": "string",
                        "description": "Name for the new template.",
                    ]),
                    "description": .object([
                        "type": "string",
                        "description": "Description of what the template does.",
                    ]),
                    "location": .object([
                        "type": "string",
                        "description": "Where to create the template: 'global' or 'project'.",
                    ]),
                    "project_directory": .object([
                        "type": "string",
                        "description": "Project directory path.",
                    ]),
                ]),
                "required": .array(["name", "description", "location"]),
            ]),
        ),
        Tool(
            name: "egg_template_delete",
            description: "Deletes an existing template. This action cannot be undone.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "template_name": .object([
                        "type": "string",
                        "description": "Name of the template to delete.",
                    ]),
                    "project_directory": .object([
                        "type": "string",
                        "description": "Project directory path.",
                    ]),
                    "template_search_paths": .object([
                        "type": "array",
                        "items": .object(["type": "string"]),
                        "description": "Additional paths to search for templates.",
                    ]),
                ]),
                "required": .array(["template_name"]),
            ]),
        ),
        Tool(
            name: "egg_template_duplicate",
            description: "Creates a copy of an existing template with a new name.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "source_template_name": .object([
                        "type": "string",
                        "description": "Name of the template to duplicate.",
                    ]),
                    "new_name": .object([
                        "type": "string",
                        "description": "Name for the new template copy.",
                    ]),
                    "new_description": .object([
                        "type": "string",
                        "description": "Description for the new template. Uses source description if not provided.",
                    ]),
                    "project_directory": .object([
                        "type": "string",
                        "description": "Project directory path.",
                    ]),
                    "template_search_paths": .object([
                        "type": "array",
                        "items": .object(["type": "string"]),
                        "description": "Additional paths to search for templates.",
                    ]),
                ]),
                "required": .array(["source_template_name", "new_name"]),
            ]),
        ),
        Tool(
            name: "egg_template_move",
            description: "Moves a template between global and project locations.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "template_name": .object([
                        "type": "string",
                        "description": "Name of the template to move.",
                    ]),
                    "target_location": .object([
                        "type": "string",
                        "description": "Target location: 'global' or 'project'.",
                    ]),
                    "project_directory": .object([
                        "type": "string",
                        "description": "Project directory path.",
                    ]),
                    "template_search_paths": .object([
                        "type": "array",
                        "items": .object(["type": "string"]),
                        "description": "Additional paths to search for templates.",
                    ]),
                ]),
                "required": .array(["template_name", "target_location"]),
            ]),
        ),
        Tool(
            name: "egg_template_validate",
            description: "Validates a template's config.yml for errors.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "template_path": .object([
                        "type": "string",
                        "description": "Absolute path to the template directory containing config.yml.",
                    ]),
                ]),
                "required": .array(["template_path"]),
            ]),
        ),
        Tool(
            name: "egg_template_install",
            description: "Installs templates from a Git repository or local directory.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "source": .object([
                        "type": "string",
                        "description": "Git repository URL or local directory path.",
                    ]),
                    "location": .object([
                        "type": "string",
                        "description": "Where to install: 'global' or 'project'.",
                    ]),
                    "ref": .object([
                        "type": "string",
                        "description": "Git ref (branch, tag, or commit) for Git sources.",
                    ]),
                    "include": .object([
                        "type": "array",
                        "items": .object(["type": "string"]),
                        "description": "Template names to include (if not specified, includes all).",
                    ]),
                    "exclude": .object([
                        "type": "array",
                        "items": .object(["type": "string"]),
                        "description": "Template names to exclude.",
                    ]),
                    "project_directory": .object([
                        "type": "string",
                        "description": "Project directory path.",
                    ]),
                ]),
                "required": .array(["source", "location"]),
            ]),
        ),
    ]

    private let server: Server
    private let transport: StdioTransport

    /// Initialize the MCP server
    public init() {
        server = Server(
            name: "egg",
            version: "1.0.0",
            capabilities: .init(
                tools: .init(listChanged: false),
            ),
        )
        transport = StdioTransport()
    }

    /// Start the MCP server
    public func start() async throws {
        try await server.start(transport: transport)

        // Register ListTools handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: Self.tools)
        }

        // Register CallTool handler
        await server.withMethodHandler(CallTool.self) { params in
            do {
                let result = try await ToolHandlerRegistry.shared.execute(
                    toolName: params.name,
                    arguments: params.arguments ?? [:],
                )
                return CallTool.Result(content: [.text(text: result, annotations: nil, _meta: nil)])
            } catch {
                return CallTool.Result(
                    content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                    isError: true,
                )
            }
        }

        // Keep the server running
        await server.waitUntilCompleted()
    }
}
