# 🥚 egg

**Hatch your templates! A transactional scaffolding CLI tool for AI agents
and humans.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)](https://developer.apple.com/macos/)

egg is a template scaffolding CLI. Define macros and lifecycle scripts once in
a `config.yml`, use `___MACRO_NAME___` placeholders anywhere in your template's
files and directories, and egg expands them into a real project, safely and
repeatably, with a full paper trail.

Here's what makes egg different from a plain "copy files and find-and-replace"
tool.

- **Transactional hatching.** Every scaffold goes through `preview → apply →
  rollback`. Nothing touches your working directory until you say so, and
  every apply can be undone.
- **Git-native change detection.** egg clones your working tree into an
  isolated staging area and lets `git` decide what actually changed,
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
  - [Human and Inline Flow (egg hatch)](#human-and-inline-flow-egg-hatch)
  - [Agent Transaction Flow (egg hatch)](#agent-transaction-flow-egg-hatch)
  - [Managing Templates (egg template)](#managing-templates-egg-template)
- [Using egg with AI Agents](#using-egg-with-ai-agents)
  - [Claude Code Plugin](#claude-code-plugin)
  - [Model Context Protocol (MCP)](#model-context-protocol-mcp)
  - [Skills for Codex and Other Agents](#skills-for-codex-and-other-agents)
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
#    template files using ___MACRO_NAME___ placeholders. See "Writing a
#    Template" below for a full example.

# 3. Hatch it. With no template name, egg prompts you interactively for
#    which template to use and a value for each macro.
egg hatch

# Prefer to skip the picker and pass everything on one line instead?
egg hatch direct SwiftPackage --module-name NetworkClient
```

Either form stages the change first and shows you a summary before writing
anything, so you get a chance to bail out. See
[Human and Inline Flow](#human-and-inline-flow-egg-hatch) for the full
walkthrough and every flag.

Driving egg from an AI agent instead? It also has a non-interactive,
JSON-in/JSON-out transaction flow (`preview` → `apply` → `rollback`); see the
[Agent Transaction Flow](#agent-transaction-flow-egg-hatch).

## Why egg?

Most scaffolding tools are "copy a directory and replace some strings." That's
fine until:

- A lifecycle script (`npm install`, `swift package resolve`, `pod install`,
  a codegen step...) writes files you didn't explicitly template. Now what
  actually changed in your project?
- You want to *see* the diff before it lands, especially when an AI agent is
  the one running the scaffold.
- The scaffold turns out to be wrong and you want your working directory back
  exactly as it was.

egg treats hatching a template as a **transaction**, not a one-shot copy.

1. **`preview`** clones your working directory into an isolated staging area,
   runs the template's lifecycle scripts and macro expansion there, and asks
   `git` (not a bespoke diff algorithm) what actually changed. Anything your
   project's `.gitignore` already excludes (build artifacts, `node_modules`,
   caches) is excluded here too, automatically, with zero configuration.
2. **`apply`** copies exactly those changes into your real working directory,
   and records a rollback bundle before touching anything.
3. **`rollback`** restores the pre-apply state from that bundle, even
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
# the binary is at .build/release/egg. Copy it onto your PATH, e.g.:
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

Templates live in one of two places.

- **Global** templates live at `~/.eggs/<TemplateName>/` and are available
  from any project.
- **Project** templates live at `./.eggs/<TemplateName>/` and are scoped to
  the current repo.

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
| `choice` | `--platform ios` | Single selection; requires `choices`. |
| `choices` | `--platforms ios,macos` | Multiple selection; requires `choices`. |
| `array` | `--tags foo,bar` | Free-form comma-separated values. |
| `path` | `--config-path ./foo.json` | Same as `string`, resolved/validated as a filesystem path. |

Every macro name (`___MODULE_NAME___`) maps to a kebab-case CLI flag
(`--module-name`) automatically. `egg template detail <name>` prints the exact
flags, types, and a ready-to-run example command for any template. This is
the fastest way to discover what a template needs, for a human or an agent.

### Lifecycle Hooks

`pre_hatch` and `post_hatch` are lists of shell steps.

```yaml
post_hatch:
  - id: install-deps
    run: npm install
  - if: "___INCLUDE_TESTS___"
    run: swift test
```

- `run` runs a shell command (macros and prior step outputs are substituted).
- `if` gates the step behind a JavaScript-style boolean expression.
- `id` lets later steps reference this step's stdout via
  `${{ pre_hatch.<id>.outputs.<key> }}` (parsed from `key=value` lines).

## CLI Reference

```
egg <subcommand>
  template   Manage templates.
  hatch      Use a template to generate files with macro substitution.
  mcp        Start the MCP server for AI assistant integration.
```

### Human and Inline Flow (egg hatch)

This is the everyday, terminal-first way to run egg. Both forms stage the
template in an isolated clone, show you a summary of what would change, and
wait for a yes/no before touching your real working directory, unless you
opt out with a flag below.

```sh
egg hatch                        # interactive: prompts for template and macros
egg hatch direct MyTemplate ...  # applies inline, macros passed as flags
```

#### Interactive mode

Run `egg hatch` with nothing else and it walks you through the whole thing.

```
$ egg hatch
? Which template would you like to use? › SwiftPackage
? ___MODULE_NAME___ (The name of the Swift module) › NetworkClient
? ___INCLUDE_TESTS___ (Whether to generate a test target) › Yes

Staged changes:
  + Sources/NetworkClient/NetworkClient.swift
  + Tests/NetworkClientTests/NetworkClientTests.swift

? Apply these changes? › Yes
✔ Hatched SwiftPackage
```

Each macro's own `description` from `config.yml` becomes the prompt text, so
a well-documented template doubles as a self-explanatory wizard. Pass
`--picker text` if you'd rather type the template name than pick from a list.

#### Inline mode

`egg hatch direct <template> --macro-name value ...` skips the picker and
per-macro prompts, so it is the form to reach for once you already know what
you're generating (in a script, a Makefile target, or just muscle memory).
Macro flags are kebab-case versions of the macro's name in `config.yml`, so a
macro named `___MODULE_NAME___` becomes `--module-name`.

```sh
egg hatch direct SwiftPackage --module-name NetworkClient --include-tests true
```

This still shows the staged change summary and asks for confirmation unless
you pass `--apply-changes` (skip the prompt) or `--no-staging` (skip staging
entirely and write files immediately, forgoing rollback).

| Flag | Description |
| --- | --- |
| `--no-staging` | Apply directly, skipping the preview/rollback staging step. |
| `--override-conflicts` | Overwrite existing files without prompting. |
| `--no-sandbox` | Disable the `sandbox-exec` guard around lifecycle scripts. |
| `--apply-changes` | Skip the confirmation prompt and apply immediately. |
| `--staging-root <dir>` | Use a different staging root (when output targets another directory). |
| `--picker <list\|text>` | Interactive template picker style. |

Run `egg template detail <name>` first if you want to see every macro a
template needs (and its type/default) before hatching it.

### Agent Transaction Flow (egg hatch)

Driving egg from an LLM tool call instead of a terminal? Every command below
is non-interactive and emits JSON on stdout, so there is nothing to prompt
and nothing to parse from human-readable text.

```sh
egg hatch preview <template> [--macro-name value ...] [--include <pathspec>] [--exclude <pathspec>] [--output <dir>] [--diff] [--no-sandbox]
egg hatch apply <applyToken> [--force]
egg hatch rollback <rollbackId> [--force]
egg hatch discard <applyToken>
```

- **`preview`** stages the template in an isolated clone and reports the
  proposed `changes`, any `warnings`, and an `applyToken`. Nothing is written
  to your working directory yet.
  - `--include <pathspec>` forces a normally git-ignored path into the change set.
  - `--exclude <pathspec>` drops matching paths from the change set.
  - `--output <dir>` sets the directory the generated output targets.
  - `--diff` includes each change's unified diff in the response (off by default).
  - `--no-sandbox` disables the `sandbox-exec` guard around preview lifecycle scripts.
- **`apply <applyToken>`** writes the previewed changes to your real working
  directory and returns a `rollbackId`. Fails if the working directory
  drifted since the preview, unless `--force` is passed.
- **`rollback <rollbackId>`** restores the pre-apply state. Fails if a file
  was hand-edited since the apply, unless `--force` is passed.
- **`discard <applyToken>`** throws away a preview without applying it.

`egg template detail <name>` tells you exactly which flags a given template
needs before you preview it.

### Managing Templates (egg template)

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

## Using egg with AI Agents

egg is built for agent-driven scaffolding from the ground up, and there are a
few ways to wire it into your agent depending on which tool you use.

### Claude Code Plugin

The fastest path for Claude Code. This installs both skills below
(`egg-cli-guide`, `egg-template`) and configures the bundled MCP server in one
step, no manual client config needed. It requires `egg` to already be on your
`PATH` (see [Installation](#installation)).

```
/plugin marketplace add Ryu0118/Egg
/plugin install egg@egg
```

The same install also works from the command line.

```sh
claude plugin marketplace add Ryu0118/Egg
claude plugin install egg@egg
```

Verify what a plugin bundle contains before installing it with
`claude plugin validate`.

### Model Context Protocol (MCP)

Prefer to wire the MCP server up yourself, or use a client that isn't Claude
Code (Claude Desktop, another MCP-capable client)? egg ships a built-in
[Model Context Protocol](https://modelcontextprotocol.io) server directly.

```sh
egg mcp
```

Point your client's stdio MCP config at this command. The recommended flow
for an agent mirrors the CLI transaction flow.

1. Call `egg_template_detail` to read required macros and the recommended flow.
2. Call `egg_hatch_preview` to create a transaction without applying anything.
3. Inspect `changes` and `warnings` in the response.
4. Call `egg_hatch_apply` to apply, only after approval.
5. Call `egg_hatch_rollback` to undo, if needed.

Macro keys over MCP must use the *exact* config names, not the kebab-case CLI
flags.

```json
{
  "template_name": "SwiftPackage",
  "macros": {
    "___MODULE_NAME___": "NetworkClient",
    "___INCLUDE_TESTS___": true
  }
}
```

To disable sandboxing for MCP preview or legacy hatch calls, pass both
`"disable_sandbox": true` and `"user_confirmed_no_sandbox": true` after the
user explicitly approves running lifecycle scripts without the sandbox guard.

A legacy `egg_hatch` tool is also available for compatibility. It defaults to
preview mode and only applies changes if `apply_changes: true` is explicitly
passed.

### Skills for Codex and Other Agents

egg's skills (`egg-cli-guide` for CLI usage, `egg-template` for authoring and
updating templates) are plain `SKILL.md` files following the open
[Agent Skills standard](https://agentskills.io), so they work with any
compatible agent, not just Claude Code.

- **Working directly in a clone of this repo**, Codex discovers skills at
  `.agents/skills/`, already populated here (`egg-cli-guide`,
  `egg-template`), so no setup is required.
- **From anywhere, using `gh` for cross-agent installs**, pull a single skill
  into whichever agent you use with [`gh skill`](https://cli.github.com)
  (`gh` v2.90.0+).

  ```sh
  gh skill install Ryu0118/Egg egg-cli-guide --agent codex
  gh skill install Ryu0118/Egg egg-template --agent claude-code
  ```

  `--agent` also accepts `cursor`, `gemini`, and `antigravity`.
- **Manually, in any tool**, copy or symlink
  `.claude/plugins/egg/skills/<skill-name>` into wherever your agent reads
  skills from since both skills are self-contained directories.

## How Rollback Works

- `apply` snapshots the pre-apply content of every file it's about to touch
  into a rollback bundle *before* writing anything, so a failed or
  interrupted apply never leaves a half-written project.
- `rollback` compares the current file content against what `apply` actually
  wrote. If you've edited a generated file since, rollback refuses (rather
  than silently discarding your edits) unless you pass `--force`.
- Rollback restores **managed workspace file changes only**. It does not undo
  network calls, writes outside the project, package-manager global caches,
  or other external side effects a lifecycle script performed. The
  preview/apply response always carries a `rollback_scope` warning to make
  this explicit.

## Requirements

The working directory **must be a git repository**. egg uses your project's
own `.gitignore` as the single source of truth for what counts as a change.
The staging clone carries your tracked `.gitignore`, so artifacts a lifecycle
script generates (`node_modules`, `.build`, ...) are suppressed by the same
rules git already applies. There's no separate, hardcoded exclude list to
keep in sync. If the working directory isn't a git repository, `hatch` fails
and tells you to run `git init` first.

## Development

```sh
make install-commands  # bootstrap dev tools (SwiftFormat, SwiftLint, etc.)
make format            # swiftformat
make swiftlint         # swiftlint --strict
make my-lint           # project-specific AST lint rules
make lint              # swiftlint + my-swift-linter
make hooks             # install repo git hooks
make test              # swift test
make e2e-test          # end-to-end CLI tests (separate package)
make check             # format + lint + test + e2e-test
```

See [`.agents/rules/base.md`](.agents/rules/base.md) for the project's
directory layout and naming conventions.

## License

egg is available under the MIT License. See [LICENSE](LICENSE) for details.
