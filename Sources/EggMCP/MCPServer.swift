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
            Hatches (instantiates) a template with the provided macro values. Creates files and directories based on the template.

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
                        "description": "Directory to use as staging root. Use this when template outputs target a different directory than the working directory.",
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
                        "description": "Apply changes after staging. Default: true.",
                    ]),
                ]),
                "required": .array(["template_name"]),
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
                return CallTool.Result(content: [.text(result)])
            } catch {
                return CallTool.Result(
                    content: [.text("Error: \(error.localizedDescription)")],
                    isError: true,
                )
            }
        }

        // Keep the server running
        await server.waitUntilCompleted()
    }
}
