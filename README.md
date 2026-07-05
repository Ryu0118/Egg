# 🥚 egg

**Agent-ready project scaffolding for humans, Claude Code, Codex, and other
AI agents.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)](https://developer.apple.com/macos/)

egg turns reusable templates into reviewed project changes. Define macros in
`config.yml`, put `___MACRO_NAME___` placeholders in files or directories, then
let a person or an agent preview, apply, and roll back the generated result.

## Features

- 🤖 **Agent-native workflows** — Agent Skills, Claude Code/Codex plugins,
  and MCP tools give assistants the context they need.
- 🔍 **Preview before apply** — every scaffold can be staged and inspected
  before it touches your working tree.
- 🧩 **Typed templates** — native placeholders and Stencil files support simple
  replacements, conditionals, and loops.

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
egg hatch discard <applyToken>
```

`preview` returns JSON with the proposed changes and an `applyToken`. `apply`
writes the approved changes and returns a `rollbackId`. `rollback` restores the
pre-apply state when the generated result should be undone.

The same flow is available through the built-in MCP server:

```sh
egg mcp
```

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

Run this to see the exact flags a template accepts:

```sh
egg template detail SwiftPackage
```

## Installation

egg requires **macOS 26+** and **Swift 6.2**.

```sh
git clone https://github.com/Ryu0118/egg.git
cd egg
swift build -c release
cp .build/release/egg /usr/local/bin/egg
```

Or run it directly:

```sh
swift run egg -- --help
```

Prebuilt universal binaries are attached to
[GitHub Releases](https://github.com/Ryu0118/egg/releases).

## Documentation

DocC documentation lives in `Sources/EggKit/EggKit.docc`.

- `Agent Skills and Plugins` explains the Claude Code, Codex, skills, plugin,
  and MCP story.
- `Template Config` documents `config.yml`, macro types, and Stencil files.
- `Transaction Flow` documents preview/apply/rollback/discard.

Generate the DocC archive with SwiftPM:

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
