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
