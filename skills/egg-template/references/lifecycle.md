# Lifecycle Hooks

## Overview

| Hook | When | Use Cases |
|------|------|-----------|
| `pre_hatch` | Before template expansion | Create directories, validate environment, compute values |
| `post_hatch` | After template expansion | git init, install dependencies, open in editor |

## Step Structure

```yaml
pre_hatch:  # or post_hatch
  - id: step-id          # Optional, required for output references
    if: js-expression    # Optional condition
    run: |
      shell command here
```

## Step Outputs

Shell scripts can output key-value pairs for use in config.yml or template files.

**Output format:**
```bash
echo "key=value"
```

**Reference syntax:**

| Context | Syntax |
|---------|--------|
| config.yml / Native files | `${{ pre_hatch.step-id.outputs.key }}` |
| Stencil files | `{{ pre_hatch.step_id.outputs.key }}` |

**Example:**
```yaml
pre_hatch:
  - id: setup
    run: |
      echo "root=./___APP_NAME___"
      echo "timestamp=$(date +%Y%m%d)"

hatch:
  output: ${{ pre_hatch.setup.outputs.root }}
```

## Conditional Execution

Use `if` with JavaScript expressions. Macros are available as variables.

```yaml
post_hatch:
  - if: ___INIT_GIT___
    run: git init

  - if: ___PLATFORM___ === 'iOS'
    run: pod install

  - if: ___FEATURES___.includes('Analytics')
    run: echo "Setting up analytics..."
```

## Common Patterns

### Git initialization
```yaml
macros:
  - name: ___INIT_GIT___
    type: boolean
    default: false

post_hatch:
  - if: ___INIT_GIT___
    run: |
      git init
      git add .
      git commit -m "Initial commit"
```

### Dependency installation
```yaml
post_hatch:
  - id: deps
    run: |
      if [ -f "Package.swift" ]; then
        swift package resolve
      fi
```

### Dynamic output directory
```yaml
pre_hatch:
  - id: output
    run: |
      echo "dir=./$(echo ___APP_NAME___ | tr '[:upper:]' '[:lower:]')"

hatch:
  output: ${{ pre_hatch.output.outputs.dir }}
```
