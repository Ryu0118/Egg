# 🥚 egg

**Hatch your templates — scaffolding built for AI agents, and humans too.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)](https://developer.apple.com/macos/)

egg is a template scaffolding CLI. Define macros and lifecycle scripts once in
a `config.yml`, use `___MACRO_NAME___` placeholders anywhere in your template's
files and directories, and egg expands them into a real project — safely,
repeatably, and with a full paper trail.

What makes egg different from a plain "copy files and find-and-replace" tool:

- **Transactional hatching.** Every scaffold goes through `preview → apply →
  rollback`. Nothing touches your working directory until you say so, and
  every apply can be undone.
- **Git-native change detection.** egg clones your working tree into an
  isolated staging area and lets `git` decide what actually changed —
  including anything a lifecycle script generates. Your own `.gitignore` is
  the single source of truth; there's no hardcoded exclude list to fight with.
- **Agent-first, JSON everywhere.** The transaction flow never prompts and
  always emits structured JSON, so an LLM agent (via the CLI or the built-in
  MCP server) can drive it directly. Humans get a first-class interactive mode
  too.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Why egg?](#why-egg)
- [Installation](#installation)
- [Writing a Template](#writing-a-template)
  - [config.yml Reference](#configyml-reference)
  - [Macro Types](#macro-types)
  - [Lifecycle Hooks](#lifecycle-hooks)
- [CLI Reference](#cli-reference)
  - [`egg hatch` — Agent Transaction Flow](#egg-hatch--agent-transaction-flow)
  - [`egg hatch` — Human / Inline Flow](#egg-hatch--human--inline-flow)
  - [`egg template` — Managing Templates](#egg-template--managing-templates)
- [Using egg with AI Agents (MCP)](#using-egg-with-ai-agents-mcp)
- [How Rollback Works](#how-rollback-works)
- [Requirements](#requirements)
- [Development](#development)
- [License](#license)

---

## Quick Start

```sh
# 1. Install egg (see Installation below), then create a template
egg template create --name SwiftPackage --description "A minimal Swift package" --location project

# 2. Edit .eggs/SwiftPackage/config.yml to declare a macro, and drop in your
#    template files using ___MACRO_NAME___ placeholders — see "Writing a
#    Template" below for a full example.

# 3. Preview what hatching it would generate (writes nothing yet)
egg hatch preview SwiftPackage --module-name NetworkClient

# {
#   "applyToken": "2026-07-02T...-swiftpackage-...",
#   "changes": [{ "kind": "add", "path": "Sources/NetworkClient/NetworkClient.swift" }],
#   "nextCommands": { "apply": "egg hatch apply <token>", "discard": "..." },
#   ...
# }

# 4. Happy with the plan? Apply it.
egg hatch apply 2026-07-02T...-swiftpackage-...

# 5. Changed your mind? Roll it back.
egg hatch rollback 2026-07-02T...-swiftpackage-...
```

Prefer a human, no-JSON workflow? `egg hatch` alone drops into an interactive
prompt; see [Human / Inline Flow](#egg-hatch--human--inline-flow).

## Why egg?

Most scaffolding tools are "copy a directory and replace some strings." That's
fine until:

- A lifecycle script (`npm install`, `swift package resolve`, `pod install`,
  a codegen step...) writes files you didn't explicitly template — now what
  actually changed in your project?
- You want to *see* the diff before it lands, especially when an AI agent is
  the one running the scaffold.
- The scaffold turns out to be wrong and you want your working directory back
  exactly as it was.

egg treats hatching a template as a **transaction**, not a one-shot copy:

1. **`preview`** clones your working directory into an isolated staging area,
   runs the template's lifecycle scripts and macro expansion there, and asks
   `git` — not a bespoke diff algorithm — what actually changed. Anything your
   project's `.gitignore` already excludes (build artifacts, `node_modules`,
   caches) is excluded here too, automatically, with zero configuration.
2. **`apply`** copies exactly those changes into your real working directory,
   and records a rollback bundle before touching anything.
3. **`rollback`** restores the pre-apply state from that bundle — even
   detecting if you've since hand-edited one of the generated files, so it
   won't silently clobber your work.

Every step in the agent flow is non-interactive and JSON-in/JSON-out, so it's
as natural to drive from an LLM tool call as from a terminal.

## Installation

egg is a Swift Package Manager executable. It requires **macOS 26+** and the
**Swift 6.2** toolchain.

```sh
git clone https://github.com/Ryu0118/egg.git
cd egg
swift build -c release
# the binary is at .build/release/egg — copy it onto your PATH, e.g.:
cp .build/release/egg /usr/local/bin/egg
```

Or run it directly without installing:

```sh
swift run egg -- --help
```

Prebuilt universal binaries are also attached to each
[GitHub Release](https://github.com/Ryu0118/egg/releases).

## Writing a Template

A template is a directory containing a `config.yml` plus any files and
folders you want to generate. Anywhere in a file's name, a folder's name, or
a file's contents, `___MACRO_NAME___` is replaced with the value supplied at
hatch time.

Templates live in one of two places:

- **Global** — `~/.eggs/<TemplateName>/` — available from any project.
- **Project** — `./.eggs/<TemplateName>/` — scoped to the current repo.

### Example

```
.eggs/SwiftPackage/
├── config.yml
└── Sources/
    └── ___MODULE_NAME___/
        └── ___MODULE_NAME___.swift
```

```yaml
# .eggs/SwiftPackage/config.yml
name: SwiftPackage
description: A minimal Swift package

macros:
  - name: ___MODULE_NAME___
    description: The name of the Swift module
    type: string
    validate: "^[A-Z][A-Za-z0-9]*$"

  - name: ___INCLUDE_TESTS___
    description: Whether to generate a test target
    type: boolean
    default: true

hatch:
  output: "."
  exclude:
    - if: "!___INCLUDE_TESTS___"
      paths:
        - "Tests/**"

post_hatch:
  - run: echo "Generated ___MODULE_NAME___"
```

```swift
// Sources/___MODULE_NAME___/___MODULE_NAME___.swift
public struct ___MODULE_NAME___ {
    public init() {}
}
```

Running `egg hatch preview SwiftPackage --module-name NetworkClient` expands
the folder name, the file name, and the file contents in one pass, producing
`Sources/NetworkClient/NetworkClient.swift`.

### config.yml Reference

| Key | Required | Description |
| --- | --- | --- |
| `name` | ✅ | Template display name. |
| `description` | ✅ | One-line description shown in `template list`/`template detail`. |
| `version` | | Free-form version string. |
| `macros` | | List of macro definitions the template accepts. |
| `sandbox.allowed_paths` | | Absolute paths (macro-expandable) lifecycle scripts may write outside the sandbox. |
| `pre_hatch` | | Lifecycle steps run *before* template expansion. |
| `hatch.output` | ✅ | Output directory. Supports macros and `${{ step.outputs.key }}` references. |
| `hatch.exclude` | | Rules to skip files/folders, optionally conditional. |
| `post_hatch` | | Lifecycle steps run *after* template expansion. |

### Macro Types

| Type | CLI flag example | Notes |
| --- | --- | --- |
| `string` | `--module-name NetworkClient` | Default type if omitted. |
| `boolean` | `--include-tests` / `--no-include-tests` | Value-less flags; `default` applies if neither is passed. |
| `choice` | `--platform ios` | Single selection; requires `choices:`. |
| `choices` | `--platforms ios,macos` | Multiple selection; requires `choices:`. |
| `array` | `--tags foo,bar` | Free-form comma-separated values. |
| `path` | `--config-path ./foo.json` | Same as `string`, resolved/validated as a filesystem path. |

Every macro name (`___MODULE_NAME___`) maps to a kebab-case CLI flag
(`--module-name`) automatically. `egg template detail <name>` prints the exact
flags, types, and a ready-to-run example command for any template — this is
the fastest way to discover what a template needs, for a human or an agent.

### Lifecycle Hooks

`pre_hatch` and `post_hatch` are lists of shell steps:

```yaml
post_hatch:
  - id: install-deps
    run: npm install
  - if: "___INCLUDE_TESTS___"
    run: swift test
```

- `run` — a shell command (macros and prior step outputs are substituted).
- `if` — a JavaScript-style boolean expression gating the step.
- `id` — lets later steps reference this step's stdout via
  `${{ pre_hatch.<id>.outputs.<key> }}` (parsed from `key=value` lines).

## CLI Reference

```
egg <subcommand>
  template   Manage templates.
  hatch      Use a template to generate files with macro substitution.
  mcp        Start the MCP server for AI assistant integration.
```

### `egg hatch` — Agent Transaction Flow

Every command below is non-interactive and emits JSON on stdout.

```sh
egg hatch preview <template> [--macro-name value ...] [--include <pathspec>] [--exclude <pathspec>] [--output <dir>] [--diff]
egg hatch apply <applyToken> [--force]
egg hatch rollback <rollbackId> [--force]
egg hatch discard <applyToken>
```

- **`preview`** stages the template in an isolated clone and reports the
  proposed `changes`, any `warnings`, and an `applyToken` — nothing is written
  to your working directory yet.
  - `--include <pathspec>` — force a normally git-ignored path into the change set.
  - `--exclude <pathspec>` — drop matching paths from the change set.
  - `--output <dir>` — directory the generated output targets.
  - `--diff` — include each change's unified diff in the response (off by default).
- **`apply <applyToken>`** writes the previewed changes to your real working
  directory and returns a `rollbackId`. Fails if the working directory
  drifted since the preview, unless `--force` is passed.
- **`rollback <rollbackId>`** restores the pre-apply state. Fails if a file
  was hand-edited since the apply, unless `--force` is passed.
- **`discard <applyToken>`** throws away a preview without applying it.

`egg template detail <name>` tells you exactly which flags a given template
needs before you preview it.

### `egg hatch` — Human / Inline Flow

```sh
egg hatch                        # interactive: prompts for template and macros
egg hatch direct MyTemplate ...  # applies inline, no preview/apply/token step
```

`egg hatch` with no subcommand drops straight into an interactive prompt
(pick a template, answer for each macro). `egg hatch direct` accepts the same
flags as `preview`/`apply` combined, plus:

| Flag | Description |
| --- | --- |
| `--no-staging` | Apply directly, skipping the preview/rollback staging step. |
| `--override-conflicts` | Overwrite existing files without prompting. |
| `--no-sandbox` | Disable the `sandbox-exec` guard around lifecycle scripts. |
| `--apply-changes` | Skip the confirmation prompt and apply immediately. |
| `--staging-root <dir>` | Use a different staging root (when output targets another directory). |
| `--picker <list\|text>` | Interactive template picker style. |

### `egg template` — Managing Templates

| Command | What it does |
| --- | --- |
| `egg template create --name <n> --description <d> --location <global\|project>` | Scaffold a new template's `config.yml`. |
| `egg template install <git-url\|path> [--branch/--tag/--revision] [--template ...] [--global] [--force]` | Install templates from a Git repo or a local directory. |
| `egg template list [--location <global\|project>] [--hide-description]` | List available templates. |
| `egg template detail <name>` | Show macros, types, defaults, and an example command. |
| `egg template validate <path>` | Validate a template's `config.yml`. |
| `egg template duplicate <name> --name <new> --description <d>` | Copy a template under a new name. |
| `egg template move <name> --to <global\|project> [--force]` | Move a template between locations. |
| `egg template delete <name> [--force]` | Delete a template. |
| `egg template open <name>` | Reveal a template's directory in Finder. |

All `template` subcommands support an interactive mode when arguments are
omitted, and accept `--project-directory`/`--template-search-paths` to look
beyond the current directory.

## Using egg with AI Agents (MCP)

egg ships a built-in [Model Context Protocol](https://modelcontextprotocol.io)
server:

```sh
egg mcp
```

Point any MCP-capable client (Claude Code, Claude Desktop, etc.) at this
command. The recommended flow for an agent mirrors the CLI transaction flow:

1. **`egg_template_detail`** — read required macros and the recommended flow.
2. **`egg_hatch_preview`** — create a transaction without applying anything.
3. Inspect `changes` and `warnings` in the response.
4. **`egg_hatch_apply`** — apply, only after approval.
5. **`egg_hatch_rollback`** — undo, if needed.

Macro keys over MCP must use the *exact* config names (not the kebab-case CLI
flags):

```json
{
  "template_name": "SwiftPackage",
  "macros": {
    "___MODULE_NAME___": "NetworkClient",
    "___INCLUDE_TESTS___": true
  }
}
```

A legacy `egg_hatch` tool is also available for compatibility. It defaults to
preview mode and only applies changes if `apply_changes: true` is explicitly
passed.

## How Rollback Works

- `apply` snapshots the pre-apply content of every file it's about to touch
  into a rollback bundle *before* writing anything, so a failed or
  interrupted apply never leaves a half-written project.
- `rollback` compares the current file content against what `apply` actually
  wrote — if you've edited a generated file since, rollback refuses (rather
  than silently discarding your edits) unless you pass `--force`.
- Rollback restores **managed workspace file changes only**. It does not undo
  network calls, writes outside the project, package-manager global caches,
  or other external side effects a lifecycle script performed — the
  preview/apply response always carries a `rollback_scope` warning to make
  this explicit.

## Requirements

The working directory **must be a git repository**. egg uses your project's
own `.gitignore` as the single source of truth for what counts as a change:
the staging clone carries your tracked `.gitignore`, so artifacts a lifecycle
script generates (`node_modules`, `.build`, ...) are suppressed by the same
rules git already applies — there's no separate, hardcoded exclude list to
keep in sync. If the working directory isn't a git repository, `hatch` fails
and tells you to run `git init` first.

## Development

```sh
make install-commands  # bootstrap dev tools (SwiftFormat, SwiftLint, etc.)
make format            # swiftformat
make lint              # swiftlint --strict
make my-lint           # project-specific AST lint rules
make test              # swift test
make e2e-test          # end-to-end CLI tests (separate package)
make check             # format + lint + test + e2e-test
```

See [`.agents/rules/base.md`](.agents/rules/base.md) for the project's
directory layout and naming conventions.

## License

egg is available under the MIT License. See [LICENSE](LICENSE) for details.
