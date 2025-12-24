---
description: Reference for egg template config.yml structure. Use when creating or editing egg templates, understanding macro types, lifecycle hooks (pre_hatch/post_hatch), hatch configuration, or troubleshooting config validation errors.
---

# egg Template Configuration Reference

This skill provides the specification for `config.yml` files used in egg templates.

## config.yml Structure

```yaml
name: string (required)           # Template display name
description: string (required)    # Template description
version: string (optional)        # Template version

macros:                           # User input variables (optional)
  - name: "___MACRO_NAME___"      # Format: ___UPPERCASE_WITH_UNDERSCORES___
    description: string
    type: string|boolean|choice|choices|array|path
    default: string (optional)
    validate: regex (optional)    # Only for string/array types
    choices: [string] (optional)  # Required for choice/choices types

pre_hatch:                        # Steps before template expansion (optional)
  - id: step-id (optional)        # Alphanumeric, hyphens, underscores
    if: js-expression (optional)  # Must evaluate to boolean
    run: shell-command (required)

hatch:                            # Template expansion config (required)
  output: path-expression         # Supports macros and ${{ step.outputs }}
  exclude:                        # Files to exclude (optional)
    - "glob-pattern"              # Simple exclusion
    - if: js-expression           # Conditional exclusion
      paths: ["glob-patterns"]

post_hatch:                       # Steps after template expansion (optional)
  - id: step-id (optional)
    if: js-expression (optional)
    run: shell-command (required)
```

## Macro Types

| Type | Description | Required Fields | Optional Fields |
|------|-------------|-----------------|-----------------|
| `string` | Free-form text input | name, description | default, validate (regex) |
| `boolean` | true/false selection | name, description | default ("true"/"false") |
| `choice` | Single selection from list | name, description, choices | default (must be in choices) |
| `choices` | Multiple selection from list | name, description, choices | default (array format) |
| `array` | Free-form array input | name, description | default, validate |
| `path` | File/directory path | name, description | default |

### Macro Name Format

- Must start and end with `___` (three underscores)
- Inner content: uppercase letters, numbers, underscores only
- Examples: `___APP_NAME___`, `___BUNDLE_ID___`, `___SWIFT_VERSION___`

### Reserved Macro Names

These are built-in and cannot be redefined:
- `___TEMPLATE_DIR___` - Template source directory
- `___OUTPUT_DIR___` - Expansion output directory

## Template Engines

egg supports two template engines, selected by file extension:

| File Extension | Engine | Variable Syntax |
|----------------|--------|-----------------|
| `*.swift`, `*.txt`, etc. | Native | `___MACRO___`, `${{ outputs }}` |
| `*.stencil` | Stencil | `{{ ___MACRO___ }}`, `{% if %}`, `{% for %}` |

### Native Engine

The default engine for files without `.stencil` extension:
- `___MACRO___` - Replaced with macro value
- `${{ pre_hatch.step.outputs.key }}` - Replaced with step output value

```swift
// main.swift (Native)
// Project: ___PROJECT_NAME___
import Foundation
print("Hello from ___PROJECT_NAME___!")
```

### Stencil Engine

For files with `.stencil` extension (removed after rendering):

```swift
// App.swift.stencil → App.swift (after rendering)
// Project: {{ ___PROJECT_NAME___ }}
// Version: {{ pre_hatch.setup.outputs.version }}
{% for module in ___MODULES___ %}
import {{ module }}
{% endfor %}

{% if ___USE_ASYNC___ %}
@main
struct {{ ___PROJECT_NAME___ }}App {
    static func main() async {
        print("Hello (async)")
    }
}
{% else %}
@main
struct {{ ___PROJECT_NAME___ }}App {
    static func main() {
        print("Hello")
    }
}
{% endif %}
```

**Stencil Syntax:**
- `{{ variable }}` - Output variable value
- `{% if condition %}...{% endif %}` - Conditional
- `{% for item in array %}...{% endfor %}` - Loop
- Operators: `==`, `!=`, `<`, `<=`, `>`, `>=`, `and`, `or`, `not`

**Variable Access in Stencil:**
- Macros: `{{ ___MACRO_NAME___ }}`
- Step outputs: `{{ pre_hatch.step_id.outputs.key }}` (no `$` prefix, unlike Native)
- In conditions (no braces): `{% if ___USE_ASYNC___ %}`

**Step Outputs Format Comparison:**

| Engine | Syntax | Example |
|--------|--------|---------|
| Native (incl. config.yml) | `${{ phase.step.outputs.key }}` | `${{ pre_hatch.setup.outputs.version }}` |
| Stencil | `{{ phase.step.outputs.key }}` | `{{ pre_hatch.setup.outputs.version }}` |

**When to Use Stencil:**
- Conditional code blocks (`{% if %}`)
- Repeated code from arrays (`{% for %}`)
- Complex template logic

### Array Formatting with Stencil

To format arrays (e.g., generate import statements), use Stencil instead of inline formatting:

```swift
// imports.swift.stencil
{% for module in ___MODULES___ %}
import {{ module }}
{% endfor %}
```

This replaces the deprecated `format` field approach.

## Lifecycle Hooks

### Step ID Rules

- Optional but required for referencing outputs
- Allowed characters: letters, numbers, hyphens, underscores
- Must be unique within pre_hatch or post_hatch

### Referencing Step Outputs

Use `${{ section.step-id.outputs.key }}` syntax:

```yaml
pre_hatch:
  - id: prepare
    run: |
      echo "project-root=/path/to/output"

hatch:
  output: ${{ pre_hatch.prepare.outputs.project-root }}
```

Output format in shell: `echo "key=value"`

### Conditional Expressions

The `if` field accepts JavaScript expressions that must evaluate to boolean:

```yaml
post_hatch:
  - if: ___INIT_GIT___
    run: git init "${{ pre_hatch.prepare.outputs.project-root }}"
```

Macro expansion in conditions:
- `boolean` macros: `true`/`false` literals
- `string`/`path`/`choice` macros: string literals
- `array`/`choices` macros: array literals

## Hatch Configuration

### Output Directory

Supports:
- Direct paths: `./output`
- Macros: `./___PROJECT_NAME___`
- Step outputs: `${{ pre_hatch.step-id.outputs.path }}`

### Exclude Rules

Simple glob patterns:
```yaml
exclude:
  - ".DS_Store"
  - "**/.git"
  - "config.yml"
```

Conditional exclusion:
```yaml
exclude:
  - if: "!___INCLUDE_TESTS___"
    paths:
      - "Tests/**"
      - "**/*Tests.swift"
```

## Template File Placeholders

In template files (including filenames and directory names):
- Use macro names directly: `___APP_NAME___App.swift`
- Macros are replaced with user-provided values during expansion

## Validation Errors Reference

| Error | Cause | Solution |
|-------|-------|----------|
| Invalid macro name format | Name not in `___UPPER___` format | Use three underscores and uppercase |
| Macro referenced but not defined | Using undefined macro | Define macro in `macros` section |
| Condition must evaluate to boolean | `if` expression returns non-boolean | Ensure expression returns true/false |
| 'choices' required for choice type | Missing choices list | Add `choices: [...]` field |

## Example: iOS App Template

```yaml
name: iOS App Template
description: Creates a SwiftUI iOS application with SwiftPM backend

macros:
  - name: ___APP_NAME___
    description: Application name (used for targets and packages)
    type: string
    validate: "^[A-Z][A-Za-z0-9_]+$"
    default: "MyApp"

  - name: ___BUNDLE_ID___
    description: Bundle identifier
    type: string
    validate: "^[A-Za-z0-9.-]+$"
    default: "com.example.app"

  - name: ___INIT_GIT___
    description: Initialize git repository
    type: boolean
    default: false

pre_hatch:
  - id: setup
    run: |
      mkdir -p "___PROJECT_PATH___"
      echo "root=___PROJECT_PATH___"

hatch:
  output: ${{ pre_hatch.setup.outputs.root }}
  exclude:
    - ".DS_Store"
    - "config.yml"

post_hatch:
  - if: ___INIT_GIT___
    run: git init "${{ pre_hatch.setup.outputs.root }}"
```
