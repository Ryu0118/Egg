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

## Excluding Files

`hatch.exclude` entries are glob patterns matched against the output path.
Each entry is either a bare string, or an object that only excludes those
paths when a condition holds:

```yaml
hatch:
  output: "."
  exclude:
    - "*.tmp"
    - if: "___INCLUDE_TESTS___ === false"
      paths:
        - "Tests/**"
```

The conditional form uses the same `if` expression language as lifecycle
steps, described below under Conditions on step outputs, and can reference
macros and prior step outputs the same way.

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

Avoid macro names whose flag collides with a built-in flag of `egg hatch
preview` or `egg hatch direct` (for example `___OUTPUT___` → `--output`,
which `preview` claims for itself): the built-in flag always wins, so the
macro can never be provided on that command line. `egg template validate`
warns about every such collision, including the `--no-<flag>` false form of
boolean macros.

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

> Note: don't name an output key `count`, `first`, or `last` — Stencil's
> dictionary resolver treats those as built-in accessors and silently
> returns that instead of your value. This is Stencil's own behavior and
> only affects `.stencil` files.

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

### Conditions on step outputs

An `if` expression can reference a prior step's output. Write the reference
bare — egg substitutes it as a JavaScript literal inferred from the value's
spelling (`true`/`false`/`null` and numbers stay raw, everything else becomes
a quoted string), so string comparisons need no quoting around the reference:

```yaml
pre_hatch:
  - id: probe
    run: echo "kind=release"
  - if: '${{ pre_hatch.probe.outputs.kind }} === "release"'
    run: echo "release-only step"
```

Do not wrap the `${{ … }}` reference in quotes yourself — the substituted
literal is already quoted when the value is a string, and the doubled quotes
fail to parse.

## Validating a Config

`egg template validate <path>` (see <doc:ManagingTemplates>) runs the same
checks `hatch` runs before ever touching the template, so a broken config
fails fast instead of mid-expansion. It checks, among other things:

- Macro names are unique, match the `___UPPER_SNAKE_CASE___` pattern, and
  don't collide with a built-in macro name (<doc:BuiltInMacros>).
- `choices` is only set on `choice`/`choices` macros, and `validate` is
  only set on `string`/`array` macros.
- A macro's `default` matches its `validate` regex, and its `choices`
  when the type is `choice`/`choices`.
- Every `___MACRO___` reference inside `pre_hatch`/`post_hatch` `run`/`if`
  strings, `hatch.output`, and `hatch.exclude` conditions names either a
  declared macro or a built-in one — an undefined reference is an error,
  not a silent no-op.
- Every `if` expression (lifecycle steps and conditional `hatch.exclude`
  rules) evaluates to a boolean once macros and step outputs are expanded.
- No declared macro's kebab-case CLI flag collides with a built-in `hatch`
  flag such as `--output` (see Macro Types above).
