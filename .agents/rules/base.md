# egg - A Template Scaffolding Tool

A CLI tool for generating projects from templates. Define macros in `config.yml`, use `___MACRO_NAME___` placeholders in files/directories, and egg expands them with user-provided values.

## Directory Structure

| Path | Purpose |
|------|---------|
| `Sources/egg/` | Entry point only - just calls EggCLI |
| `Sources/EggCLI/` | CLI command definitions (ArgumentParser). Thin layer, no business logic |
| `Sources/EggKit/` | **All implementation**. Runners, validators, config parsing, template expansion |
| `Sources/EggKit/Config/` | `config.yml` model and validation |
| `Sources/EggKit/WorkflowRunner/` | Lifecycle execution engine (pre_hatch → hatch → post_hatch) |
| `Sources/EggMCP/` | MCP server: tool handlers exposing egg to AI agents |
| `Tests/EggKitTests/` | Unit tests |
| `Tests/EggMCPTests/` | MCP module unit tests |
| `E2ETestsPackage/` | E2E tests (separate package). Run with `cd E2ETestsPackage && swift test` |

## Naming Conventions

| Pattern | Purpose |
|---------|---------|
| `*Runner.swift` | Command execution logic (e.g., `HatchRunner.swift`) |
| `*ArgumentsValidator.swift` | Input validation before running |
| `ConfigValidator+*.swift` | Partial validators for config.yml sections |

## Template Locations

- Global: `~/.eggs/<TemplateName>/`
- Project-local: `./.egg/<TemplateName>/`

Each template contains `config.yml` and template files with `___MACRO_NAME___` placeholders.

## Available Skills

When working on egg templates or CLI usage, read these skills for detailed reference:

| Skill | When to use |
|-------|-------------|
| `egg-config-spec` | Creating/editing `config.yml` (macro types, lifecycle hooks) |
| `egg-cli-guide` | CLI commands, argument ordering, interactive vs direct mode |

## Notes

- Swift 6.2 / macOS 26+
- Use `package` access modifier for cross-module types
