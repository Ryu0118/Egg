# Getting Started

Go from zero to your first generated file, one step at a time.

## Overview

This guide walks a first-time user through the full happy path: install egg,
create a template, add a macro, and hatch it into real files. No prior egg
knowledge is assumed. Each step builds on the previous one, and every command
here is meant to be copied and run as-is.

If you are wiring egg into an AI agent instead of using it by hand, read this
guide first to understand the concepts, then move on to <doc:TransactionFlow>.

## Step 1: Install egg

Install the CLI with the one-line script. Running it again later updates egg in
place and skips the download when you are already up to date.

```sh
curl -fsSL https://raw.githubusercontent.com/Ryu0118/Egg/main/install.sh | bash
```

Confirm the install:

```sh
egg --version
```

> Prefer a package manager? See <doc:AgentSkillsAndPlugins> and the project
> README for `mise`, `nest`, and build-from-source options. The rest of this
> guide only needs the `egg` command on your `PATH`.

## Step 2: Understand the mental model

egg has exactly three moving parts. Keep them straight and everything else
follows.

| Concept | What it is |
| --- | --- |
| Template | A folder of files plus a `config.yml`, stored under `.eggs/`. |
| Macro | A named placeholder such as `___FILE_NAME___` that you fill in later. |
| Hatch | The action that copies the template and replaces every macro with a value. |

A template is the mold. A macro is a blank you fill in. Hatching is pouring the
mold into your project.

Templates live in one of two places:

| Location | Path | Use it for |
| --- | --- | --- |
| Project | `./.eggs/<Template>/` | Templates specific to one repository. |
| Global | `~/.eggs/<Template>/` | Templates you reuse across every project. |

## Step 3: Create your first template

Create a project-local template called `SwiftPackage`.

```sh
egg template create --name SwiftPackage --description "A minimal Swift package" --location project
```

egg scaffolds a ready-to-edit template for you:

```text
.eggs/SwiftPackage/
├── config.yml
└── ___FILE_NAME___View.swift
```

The generated `config.yml` already defines two macros, `___FILE_NAME___` and
`___OUTPUT_DIR___`, with commented-out examples of hooks you can enable later:

```yaml
name: SwiftPackage
description: A minimal Swift package

macros:
  - name: ___FILE_NAME___
    description: The name of the file to be generated
    type: string
  - name: ___OUTPUT_DIR___
    description: Output directory for generated files, relative to the project root
    type: string

hatch:
  output: ___OUTPUT_DIR___
```

The scaffolded `___FILE_NAME___View.swift` uses that macro in both its file name
and its contents:

```swift
struct ___FILE_NAME___View: View {
    var body: some View {
        Text("___FILE_NAME___View")
    }
}
```

Anywhere `___FILE_NAME___` appears — the file name or the file body — egg will
substitute the value you provide.

## Step 4: Check what the template asks for

Before hatching, ask egg exactly which values a template expects. This works for
any template, including ones you did not write.

```sh
egg template detail SwiftPackage
```

The output lists every macro with its CLI flag and type, and ends with a
ready-to-run example command:

```text
Macros (2)
    1. --file-name   (type: string)  The name of the file to be generated
    2. --output-dir  (type: string)  Output directory for generated files ...

Example Command
    'egg hatch SwiftPackage --file-name "value" --output-dir "./path/to/file"'
```

Each macro name becomes a kebab-case flag: `___FILE_NAME___` turns into
`--file-name`. You never have to guess the flags — `detail` prints them.

## Step 5: Hatch the template

Hatch interactively. egg prompts you for each macro value and for confirmation
before writing anything.

```sh
egg hatch
```

You will be asked to pick `SwiftPackage`, then to supply `___FILE_NAME___` and
`___OUTPUT_DIR___`. Prefer to pass everything up front? Use `direct` and name
the macros as flags:

```sh
egg hatch direct SwiftPackage --file-name Profile --output-dir ./Sources
```

## Step 6: Inspect the result

With `--file-name Profile`, egg produces:

```text
Sources/
└── ProfileView.swift
```

```swift
struct ProfileView: View {
    var body: some View {
        Text("ProfileView")
    }
}
```

`___FILE_NAME___` became `Profile` in both the file name and the body. egg also
resolves a set of built-in macros automatically — for example `___DATE___`
expands to today's date and `___SYSTEM_USER___` to your username — so templates
can stamp generated files without asking you anything.

That is the whole loop: **create → detail → hatch → inspect**. Everything else
in egg is a refinement of these four moves.

## Choosing your flow

You just ran the simplest path. Before you go further it helps to see how egg's
flows actually differ, because the common "humans use interactive, agents use
transactions" shorthand hides the real picture. There are **two independent
axes**, and you pick a point on each.

**Axis 1 — how macro values are collected.**

| | What happens | When |
| --- | --- | --- |
| Interactive | egg prompts you for each macro | You run `egg hatch` with no template name |
| Resolved | egg reads values from flags you passed | You name the template: `egg hatch direct SwiftPackage --file-name Profile` |

A human running `egg hatch direct <Template> --file-name X` is **not**
interactive — the values are already resolved. Interactivity is just the UI egg
falls back to when values are missing, not a "human mode."

**Axis 2 — how changes reach disk.**

| | What happens | How to get it |
| --- | --- | --- |
| Staged (transactional) | Changes are built in an isolated git-backed clone first, then committed on a separate step | Default for `hatch`; the explicit `preview` → `apply` flow |
| Direct write | Changes are written to the working directory immediately, no undo | `egg hatch direct ... --no-staging` |

The `preview` / `apply` / `rollback` / `discard` commands are just axis 2's
staging split into named, JSON-emitting steps so a caller can inspect the change
set before committing. They are not a different engine — same staging, different
UI. See <doc:TransactionFlow>.

**What this means for the two callers:**

| Caller | Values | Changes | Notes |
| --- | --- | --- | --- |
| Human, quickest | Resolved via flags | Direct write (`--no-staging`) | What you did above; permanent, no rollback |
| Human, careful | Interactive or resolved | Staged (default) | egg confirms before writing |
| AI agent | Resolved (macro map) | Staged transaction | `preview` → inspect → `apply` → optional `rollback` |

For agents the safe path is enforced, not just recommended: the MCP `egg_hatch`
tool runs a **preview** unless the caller explicitly sets `apply_changes: true`.
So an agent that forgets to preview still gets a no-write dry run, never a
surprise edit to the working directory.

## Where to go next

| You want to... | Read |
| --- | --- |
| Add typed macros, Stencil logic, or lifecycle hooks | <doc:TemplateConfig> |
| Drive egg from an AI agent with preview/apply/rollback | <doc:TransactionFlow> |
| Install egg into Claude Code or Codex | <doc:AgentSkillsAndPlugins> |
