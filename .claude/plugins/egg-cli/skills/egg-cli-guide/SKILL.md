---
description: |
  Use PROACTIVELY when running any egg CLI command (egg hatch, egg template list/detail/install/create/validate/open/duplicate/delete). CRITICAL for correct argument ordering and macro syntax. Invoke this skill BEFORE executing egg commands.
---

# egg CLI Usage Guide

Before using any egg command, run `<command> -h` first to see available options.

```bash
egg -h                    # Main commands
egg hatch -h              # Hatch options
egg template -h           # Template subcommands
egg template install -h   # Install options
```

Before running `egg hatch`, run `egg template detail <name>` first.

```bash
egg template detail MyTemplate
```

This shows:
- Required macros with types and default values
- Example `egg hatch` command with all macro arguments
- Template description and version

Use this output to construct the correct `egg hatch` command.

## Command Overview

| Command | Purpose | When to use |
|---------|---------|-------------|
| `egg hatch` | Generate files from template | Creating new projects/files from templates |
| `egg template list` | List available templates | Finding what templates exist |
| `egg template detail` | Show template info | Understanding required macros before hatch |
| `egg template create` | Create new template | Starting a new template from scratch |
| `egg template install` | Install templates | Adding templates from Git repos or local paths |
| `egg template validate` | Validate config.yml | Checking template configuration errors |
| `egg template open` | Open template in Finder | Editing template files directly |
| `egg template duplicate` | Duplicate a template | Creating a copy with new name/description |
| `egg template delete` | Delete a template | Removing templates (use `--force` to skip confirmation) |

## Critical: Argument Ordering in `egg hatch`

The `egg hatch` command uses `.allUnrecognized` argument parsing to capture macro arguments. This has an important implication:

**Standard options MUST come BEFORE macro arguments.**

```bash
# CORRECT - options before macros
egg hatch MyTemplate --no-staging --app-name MyApp --bundle-id com.example

# WRONG - --no-staging will be treated as a macro value!
egg hatch MyTemplate --app-name MyApp --no-staging
```

Why? After the template name, egg treats all remaining arguments as potential macros. If `--no-staging` appears after a macro, it becomes part of the macro parsing, not a standard option.

## Macro Name Conversion

Template macros use `___MACRO_NAME___` format. When passing via CLI:

| In config.yml | CLI argument |
|---------------|--------------|
| `___APP_NAME___` | `--app-name` |
| `___BUNDLE_ID___` | `--bundle-id` |
| `___SWIFT_VERSION___` | `--swift-version` |

**Rule**: Remove `___`, convert SCREAMING_SNAKE_CASE to kebab-case.

## Macro Type CLI Syntax

Different macro types require different CLI input formats:

| Type | CLI syntax | Example |
|------|------------|---------|
| `string` | Plain value | `--app-name MyApp` |
| `boolean` | Flag only (no value) | `--init-git` |
| `choice` | One of allowed values | `--platform iOS` |
| `choices` | Space-separated values | `--platforms iOS macOS` |
| `array` | Space-separated values | `--features auth analytics` |
| `path` | Relative or absolute path | `--output-path ./generated` |

**Boolean macros**:
- Include the flag to set `true`: `--init-git`
- Use `--no-` prefix to explicitly set `false`: `--no-init-git`
- Omit the flag entirely to use the default value
- Do NOT pass `true`/`false` as values

## Interactive vs Direct Mode

| Mode | When triggered | Use case |
|------|----------------|----------|
| Interactive | `egg hatch` (no args) | Exploring templates, first-time use |
| Partial | `egg hatch TemplateName` | Know template, want prompts for macros |
| Direct | `egg hatch TemplateName --macro value` | Automation, scripts, CI/CD |

## Staging Workflow

By default, `egg hatch` expands templates to a temporary staging directory. User reviews changes before applying.

| Option | Behavior |
|--------|----------|
| (default) | Expand to staging → prompt for approval → apply |
| `--apply-changes` | Expand to staging → auto-apply without prompt |
| `--no-staging` | Apply directly without staging preview |

```bash
egg hatch MyTemplate --feature-name Foo              # Staging + prompt
egg hatch MyTemplate --apply-changes --feature-name Foo  # Staging + auto-apply
egg hatch MyTemplate --no-staging --feature-name Foo     # Direct apply
```

## Sandbox Execution

Lifecycle scripts (`pre_hatch`, `post_hatch`) run in a sandboxed environment by default using macOS `sandbox-exec`. The sandbox:

- Allows read access to all files
- Restricts write access to only the staging directory
- Allows network access

Use `--no-sandbox` to disable sandboxing when scripts need to write outside staging:

```bash
egg hatch MyTemplate --no-sandbox --feature-name Foo
```

## Template Location Priority

When both global and project templates exist with the same name:

```
Project (./.eggs/MyTemplate/)  ← Takes precedence
Global  (~/.eggs/MyTemplate/)  ← Fallback
```

Use `--location global` or `--location project` to explicitly specify.

## Common Mistakes

### 1. Putting macros before options
```bash
# Wrong - --apply-changes becomes macro
egg hatch MyTemplate --app-name Test --apply-changes

# Correct
egg hatch MyTemplate --apply-changes --app-name Test
```

### 2. Using underscore instead of hyphen
```bash
# Wrong
egg hatch MyTemplate --app_name Test

# Correct (kebab-case)
egg hatch MyTemplate --app-name Test
```

### 3. Array values syntax
```bash
# Correct - space-separated values
egg hatch MyTemplate --platforms iOS macOS

# Wrong - JSON array format
egg hatch MyTemplate --platforms '["iOS", "macOS"]'
```

### 4. Using interactive mode in scripts
```bash
# Wrong - will hang waiting for input
egg hatch

# Correct - provide all required values
egg hatch MyTemplate --app-name Test --bundle-id com.test
```

## Template Creation Workflow

After creating or modifying a template, always validate it:

```bash
egg template create --name MyTemplate --location project
egg template open MyTemplate        # Edit config.yml and template files
egg template validate ./.eggs/MyTemplate  # Validate before use
```

Validation catches config.yml errors before `egg hatch` fails.

## Template Installation

`egg template install` supports Git repositories and local directories:

```bash
# From Git repository
egg template install https://github.com/user/templates.git --global

# From local directory
egg template install ./my-templates --global
egg template install /path/to/templates --global
```

**Note**: `--branch`, `--tag`, `--revision` options are only valid for Git sources, not local paths.

## Debugging Tips

1. **Validation errors**: Run `egg template validate <path>` to check config.yml
2. **See what macros are required**: Run `egg template detail <name>`
3. **Preview changes**: Omit `--no-staging` to see staged changes before applying
4. **Check option parsing**: If options aren't working, check argument order
5. **Edit template files**: Run `egg template open <name>` to open in Finder
