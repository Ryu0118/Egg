# config.yml Spec

## Structure

```yaml
name: string (required)
description: string (required)
version: string (optional)

macros:
  - name: "___MACRO_NAME___"      # ___UPPERCASE___ format
    description: string
    type: string|boolean|choice|choices|array|path
    default: value (optional)
    validate: regex (optional)    # string/array only
    choices: [values] (optional)  # choice/choices only

sandbox:
  allowed_paths:
    - ~/path                      # Supports ~, $HOME, macros
    - $HOME/path
    - /absolute/___MACRO___

pre_hatch:
  - id: step-id (optional)
    if: js-expression (optional)
    run: shell-command

hatch:
  output: path                    # Supports macros, ${{ outputs }}
  exclude:
    - "glob-pattern"
    - if: js-expression
      paths: ["patterns"]

post_hatch:
  - id: step-id (optional)
    if: js-expression (optional)
    run: shell-command
```

## Sandbox

`sandbox.allowed_paths` lists paths lifecycle scripts may write to outside the staging clone.
Writes to any other path outside the template's own output are denied.

**Designing the list:** for every external command a `pre_hatch`/`post_hatch` step invokes (a
package manager, a linter, a code generator, anything not shipped inside the template itself),
find out where that command writes outside the project directory (caches, config/state
directories, lock files) *before* writing this list. Discovering it reactively, one `preview`
failure and one retry at a time, is slow — a single sandbox-denied-write failure only reports
the path the *first* blocked write hit, not every path the command will eventually need, so
expect to iterate even after finding one.

**A hard limit this list cannot work around:** if an invoked command creates its own OS-level
sandbox internally (common in toolchains that compile or evaluate untrusted manifests/config
before running), that nested sandbox call fails outright inside egg's own sandbox — the OS
does not allow a sandboxed process to sandbox its children, regardless of what paths are
allowed. No `allowed_paths` entry fixes this. The fix is to not run that command from inside a
sandboxed lifecycle step at all: move it out of `pre_hatch`/`post_hatch` and document it as a
manual step for the user to run after hatch completes.

## Macro Types

| Type | Required | Optional |
|------|----------|----------|
| string | name, description | default, validate (regex) |
| boolean | name, description | default (true/false) |
| choice | name, description, choices | default |
| choices | name, description, choices | default (array) |
| array | name, description | default, validate |
| path | name, description | default |

**Reserved macros:** `___TEMPLATE_DIR___`, `___OUTPUT_DIR___`

## Macro Definition Examples

```yaml
macros:
  - name: ___APP_NAME___
    description: Application name
    type: string
    validate: "^[A-Z][A-Za-z0-9]+$"

  - name: ___INCLUDE_TESTS___
    description: Include test files
    type: boolean
    default: true

  - name: ___PLATFORM___
    description: Target platform
    type: choice
    choices: [iOS, macOS, watchOS, tvOS]
    default: iOS

  - name: ___FEATURES___
    description: Features to include
    type: choices
    choices: [Auth, Analytics, Push, CloudKit]
    default: [Auth]
```

## Example config.yml

```yaml
name: iOS App
description: SwiftUI app template

macros:
  - name: ___APP_NAME___
    type: string
    validate: "^[A-Z][A-Za-z0-9]+$"
  - name: ___INIT_GIT___
    type: boolean
    default: false

pre_hatch:
  - id: setup
    run: echo "root=./___APP_NAME___"

hatch:
  output: ${{ pre_hatch.setup.outputs.root }}
  exclude: [".DS_Store", "config.yml"]

post_hatch:
  - if: ___INIT_GIT___
    run: git init
```
