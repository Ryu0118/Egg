# Template Config

Describe a reusable template with `config.yml`.

## Overview

A template directory contains `config.yml` plus the files and directories to
generate. Any file name, directory name, or file content can include
`___MACRO_NAME___` placeholders.

Templates can be global or project-local:

- Global: `~/.eggs/<TemplateName>/`
- Project: `./.eggs/<TemplateName>/`

## Minimal Example

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

## Keys

| Key | Required | Purpose |
| --- | --- | --- |
| `name` | Yes | Template display name. |
| `description` | Yes | One-line description shown in template listings. |
| `version` | No | Free-form version string. |
| `macros` | No | Macro definitions accepted by the template. |
| `sandbox.allowed_paths` | No | Absolute paths lifecycle scripts may write outside the sandbox. |
| `pre_hatch` | No | Lifecycle steps before template expansion. |
| `hatch.output` | Yes | Output directory. Supports macros and step output references. |
| `hatch.exclude` | No | Rules to skip files or folders, optionally conditional. |
| `post_hatch` | No | Lifecycle steps after template expansion. |

## Macro Types

| Type | CLI example | Purpose |
| --- | --- | --- |
| `string` | `--module-name NetworkClient` | Default text value. |
| `boolean` | `--include-tests` / `--no-include-tests` | Value-less true/false flag. |
| `choice` | `--platform ios` | One value from `choices`. |
| `choices` | `--platforms ios,macos` | Multiple values from `choices`. |
| `array` | `--tags foo,bar` | Free-form comma-separated values. |
| `path` | `--config-path ./foo.json` | Filesystem path value. |

Macro names automatically become kebab-case CLI flags. For example,
`___MODULE_NAME___` becomes `--module-name`.

## Template Files

egg supports two template engines.

| File | Engine | Use it for |
| --- | --- | --- |
| `*.swift`, `*.md`, and other normal files | Native | Simple `___MACRO___` replacement. |
| `*.stencil` | Stencil | Conditional blocks, loops, and complex generated content. |

Native templates can use macros in file contents, file names, and directory
names:

```text
Sources/___MODULE_NAME___/___MODULE_NAME___.swift
```

Stencil templates use the `.stencil` extension, which egg removes after
rendering:

```swift
// App.swift.stencil -> App.swift
{% if ___USE_ASYNC___ %}
@main struct App {
    static func main() async {}
}
{% else %}
@main struct App {
    static func main() {}
}
{% endif %}
```

Use `{{ ___MACRO___ }}` for values and `{% for item in ___ARRAY___ %}` for
arrays:

```swift
{% for module in ___MODULES___ %}
import {{ module }}
{% endfor %}
```

Step outputs are available in Stencil files with dot notation:

```swift
// Version: {{ pre_hatch.setup.outputs.version }}
```

## Lifecycle Hooks

`pre_hatch` and `post_hatch` run shell steps around template expansion:

```yaml
post_hatch:
  - id: install-deps
    run: npm install
  - if: "___INCLUDE_TESTS___"
    run: swift test
```

Use lifecycle hooks when generated files need package installation, code
generation, formatting, or validation.
