# 🥚 egg

**A project scaffolding tool for AI agents and humans.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)](https://developer.apple.com/macos/)

**[Full API documentation →](https://ryu0118.github.io/Egg/documentation/eggkit/)**

egg turns reusable templates into reviewed project changes. Define macros in
`config.yml`, put `___MACRO_NAME___` placeholders in files or directories, then
let a person or an agent preview, apply, and roll back the generated result.

## Features

- 🧩 **Typed template engine** — native placeholders and Stencil files support
  simple replacements, conditionals, and loops.
- ⚙️ **Programmable lifecycle** — `pre_hatch`/`post_hatch` shell steps run
  around generation, and later steps can reference earlier outputs.
- 🔁 **Reversible transactions** — every scaffold can be previewed, applied,
  and rolled back or discarded, so nothing you generate is one-way.
- 🤖 **Agent integration surface** — Agent Skills, Claude Code/Codex plugins,
  an MCP server, and `--json` output give assistants a structured way in.

## Quick Start for Agents

Install the plugin for your agent, then ask it to create or hatch templates.

### Claude Code

```sh
/plugin marketplace add Ryu0118/Egg
/plugin install egg@egg
```

### Codex

Add the marketplace, then install the plugin:

```sh
codex plugin marketplace add Ryu0118/Egg
codex plugin add egg@egg
```

To develop against a local clone instead, point the marketplace at the checkout:

```sh
git clone https://github.com/Ryu0118/Egg
codex plugin marketplace add ./Egg
codex plugin add egg@egg
```

### APM (Agent Package Manager)

With [APM](https://github.com/microsoft/apm), one command installs both skills
into any supported harness (Claude Code, Copilot, Cursor, Codex, and more) and
pins them in `apm.lock.yaml`:

```sh
apm install Ryu0118/Egg
```

### GitHub CLI (`gh skill`)

[GitHub CLI v2.90.0+](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/)
ships a `gh skill` command (alias: `gh skills`). It pins to the latest release
tag and records provenance (repo, ref, tree SHA) in the installed SKILL.md:

```sh
gh skill install Ryu0118/Egg egg-template --agent claude-code
gh skill install Ryu0118/Egg egg-cli-guide --agent claude-code
```

Run `gh skill install Ryu0118/Egg` without a skill name for interactive
selection, and use `--agent` / `--scope` to control where skills land.

### skills CLI (`npx skills`)

The [skills CLI](https://github.com/vercel-labs/skills) installs into the
shared `.agents/skills/` directory used by many agents:

```sh
npx skills add Ryu0118/Egg --all
```

Use `--list` to inspect available skills first, or `-a claude-code` to target
a specific agent.

The plugin provides:

- `egg-cli-guide` for CLI commands and the preview/apply/rollback flow.
- `egg-template` for creating and updating `config.yml` templates.
- MCP server configuration for structured tool calls.

## Quick Start for Humans

```sh
egg template create --name SwiftPackage --description "A minimal Swift package" --location project
```

Add macros to `.eggs/SwiftPackage/config.yml` and use them in file names,
directory names, or file contents.

```yaml
name: SwiftPackage
description: A minimal Swift package

macros:
  - name: ___MODULE_NAME___
    description: The Swift module name
    type: string
    validate: "^[A-Z][A-Za-z0-9]*$"

hatch:
  output: "."
```

```text
.eggs/SwiftPackage/
├── config.yml
└── Sources/
    └── ___MODULE_NAME___/
        └── ___MODULE_NAME___.swift
```

For conditional or repeated content, use Stencil files. The `.stencil`
extension is removed after rendering:

```swift
// Sources/App.swift.stencil -> Sources/App.swift
{% for module in ___MODULES___ %}
import {{ module }}
{% endfor %}
```

Hatch the template interactively:

```sh
egg hatch
```

Or pass macro values inline:

```sh
egg hatch direct SwiftPackage --module-name NetworkClient
```

## Agent Transaction Flow

Agents should use the non-interactive flow:

```sh
egg hatch preview SwiftPackage --module-name NetworkClient --diff
egg hatch apply <applyToken>
egg hatch rollback <rollbackId>
egg hatch discard <applyToken> [--force]
egg hatch transactions
```

`preview` returns JSON with the proposed changes and an `applyToken`. `apply`
writes the approved changes and returns a `rollbackId`. `rollback` restores the
pre-apply state when the generated result should be undone; a rolled-back
transaction can be re-applied with the same token. `discard` deletes a
transaction and its rollback bundle from any state (`--force` required for an
applied transaction, since that removes the only way to undo it), and
`transactions` lists all records so leftovers can be found and cleaned up.

The same flow is available through the built-in MCP server:

```sh
egg mcp
```

Every `egg template` subcommand also accepts `--json` to emit the same
machine-readable result the MCP tools return, instead of the human-readable
tables and status lines:

```sh
egg template list --json
egg template detail SwiftPackage --json
egg template create --name Widget --description "A widget" --location project --json
```

`--json` implies direct mode, so every value the command needs must be passed
as a flag. And because agents pipe or close stdin, any command that would fall
back to an interactive prompt without a TTY fails fast with the prompt's
question and the flags to pass instead — it never hangs waiting for input.

## Template Basics

Templates live in one of two places:

- Global templates: `~/.eggs/<TemplateName>/`
- Project templates: `./.eggs/<TemplateName>/`

Every template has a `config.yml` file. The important keys are:

| Key | Purpose |
| --- | --- |
| `name` | Template display name. |
| `description` | Short description shown in template listings. |
| `macros` | Values collected from a human or supplied by an agent. |
| `pre_hatch` | Shell steps before file expansion. |
| `hatch.output` | Output directory for generated files. |
| `hatch.exclude` | Conditional file or directory exclusions. |
| `post_hatch` | Shell steps after file expansion. |

Here is a minimal `config.yml` that exercises every key in the table above:

```yaml
name: SwiftPackage
description: A minimal Swift package

macros:
  - name: ___MODULE_NAME___
    description: The Swift module name
    type: string
    validate: "^[A-Z][A-Za-z0-9]*$"
  - name: ___INIT_GIT___
    description: Run git init after generating the project
    type: boolean
    default: false

pre_hatch:
  - id: setup
    run: |
      echo "root=./___MODULE_NAME___"

hatch:
  output: ${{ pre_hatch.setup.outputs.root }}
  exclude:
    - ".DS_Store"
    - if: ___INIT_GIT___ === false
      paths: [".gitignore"]

post_hatch:
  - if: ___INIT_GIT___
    run: |
      git init
      git add .
      git commit -m "Initial commit"
```

Run this to see the exact flags a template accepts:

```sh
egg template detail SwiftPackage
```

## Installation

```sh
curl -fsSL https://raw.githubusercontent.com/Ryu0118/Egg/main/install.sh | bash
```

To update, run the same command. It skips the download if already up-to-date.

```sh
# Install a specific version
curl -fsSL https://raw.githubusercontent.com/Ryu0118/Egg/main/install.sh | VERSION=0.1.0 bash

# Force reinstall
curl -fsSL https://raw.githubusercontent.com/Ryu0118/Egg/main/install.sh | FORCE=1 bash
```

### Other methods

#### Nest ([mtj0928/nest](https://github.com/mtj0928/nest))

```sh
nest install Ryu0118/Egg
```

#### Mise ([jdx/mise](https://github.com/jdx/mise))

```sh
mise use -g ubi:Ryu0118/Egg
```

#### Build from source

Requires **macOS 26+** and **Swift 6.2**.

```sh
git clone https://github.com/Ryu0118/Egg.git
cd Egg
swift build -c release
cp .build/release/egg /usr/local/bin/egg
```

Or run it directly:

```sh
swift run egg -- --help
```

## Documentation

Full API documentation is published at
[ryu0118.github.io/Egg/documentation/eggkit](https://ryu0118.github.io/Egg/documentation/eggkit/).

The DocC catalog lives in `Sources/EggKit/EggKit.docc`.

- `Agent Skills and Plugins` explains the Claude Code, Codex, skills, plugin,
  and MCP story.
- `Template Config` documents `config.yml`, macro types, and Stencil files.
- `Transaction Flow` documents preview/apply/rollback/discard/transactions and
  the transaction state machine.

Generate the archive locally with SwiftPM:

```sh
make docs
```

## Development

```sh
make install-commands
make format
make lint
make test
make e2e-test
make check
```

## License

egg is available under the MIT License. See [LICENSE](LICENSE) for details.
