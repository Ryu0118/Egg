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

## Shell Quoting in `run:` (critical)

Inside `run:` commands, every `___MACRO___` and `${{ ... }}` reference is
substituted **before** the shell runs, and egg wraps each value in single
quotes (shell-injection safety — a value containing spaces, globs, or
`$(...)` must never be interpreted by the shell). The substitution is
already a safe, standalone shell token.

**Never wrap a macro or step-output reference in your own quotes.** Inside
double quotes, the injected single quotes stop being quoting and become
literal characters — the value silently corrupts to e.g. `'MyApp'` and you
get files or directories with `'` in their names.

```yaml
# BAD — every one of these embeds literal quote characters in the value
- run: |
    NAME="___APP_NAME___"                 # NAME becomes 'MyApp' (with quotes)
    FULL="${{ pre_hatch.names.outputs.full }}"   # same trap for step outputs
    echo "dir=___OUTPUT_PATH___/sub"      # output key gets a corrupted path
    mkdir -p "___OUTPUT_PATH___/sub"      # creates a directory named '...'

# GOOD — reference bare, assign to a variable, then use the variable
- run: |
    NAME=___APP_NAME___
    OUT=___OUTPUT_PATH___
    FULL=${{ pre_hatch.names.outputs.full }}
    echo "dir=$OUT/sub"
    mkdir -p "$OUT/sub"
```

Bare references work everywhere a shell word is expected: as a standalone
command argument (`add-target ___NAME___Feature`), in an assignment
(`P=___PATH___`), or concatenated with a suffix (`FULL=___NAME___Client`) —
the shell strips the injected quotes and joins adjacent parts. The rule only
bites when the reference sits **inside** a `"..."` string; hoist it into a
variable first and interpolate the variable instead.

This applies only to `run:` commands. In `if:` expressions, `hatch.output:`,
and `hatch.exclude` the value expands for JavaScript or as raw text, not for
a shell — see each section's own quoting notes.

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

> **Stencil reserved names:** don't name an output key `count`, `first`, or `last` — Stencil's dictionary resolver treats those as built-in accessors (`.count`/`.first`/`.last`) and returns that instead of your value, silently. This is Stencil's own behavior, not egg's; it only affects `.stencil` files (`${{ }}` in config.yml/native files is unaffected).

> **One line per output:** `echo "key=value"` is parsed line by line — each output line is its own independent `key=value` pair, so a `value` containing an embedded newline silently truncates to just its first line; every subsequent line is either dropped (no `=`) or misread as an unrelated key. If a value is naturally multi-line (e.g. built up across loop iterations), join it with a single-line separator (space, comma, `;`) before echoing it, and split it back apart wherever it's consumed.

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

## Where Script Output Goes

Anything a step prints on stdout reaches whoever is hatching, so `echo` is the
way to leave them instructions ("now run `pnpm install`", "a config was written
to X"). How it reaches them depends on who is hatching:

| Hatching as | Where the output appears |
|---|---|
| A human (`egg hatch`, `egg hatch <name> ...`) | Streamed to the terminal, line by line, under the step's label |
| An agent (`egg hatch preview`, MCP `egg_hatch_preview`) | The `scriptOutput` array in the JSON result — stdout itself is reserved for that JSON |

Both are always on; there is no flag to enable either.

Each `scriptOutput` entry carries the step's `phase` (`pre_hatch` or
`post_hatch`), its `index`, its `id` when declared, and:

- `stdout` — everything the step printed, verbatim. This is separate from
  Step Outputs above: the `key=value` parsing still happens, and those lines
  also appear here as plain text.
- `truncated` — `true` when output passed the 64 KB per-step cap. The
  **leading** bytes are what survive, so put a message you want read at the
  top of a step rather than after a noisy build.
- `skipped` — `true` when the step's `if:` condition was false, so a reader
  can tell "this step printed nothing" from "this step never ran".

`scriptOutput` is produced by `preview`, not `apply`: lifecycle scripts run
while the template is staged, and `apply` only copies the resulting files.
The `hatch` phase is pure file expansion with no script steps, so it never
appears there.

If a step exits non-zero the hatch fails and there is no result to carry
`scriptOutput` at all — that step's stdout is reported in the error message
instead, so a script can still explain itself as it dies. That copy keeps the
**trailing** bytes, the inverse of the cap above, because a failure's cause is
at the end of its output rather than the start.

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
