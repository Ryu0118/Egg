# Managing Templates

Create, inspect, and organize templates with `egg template`.

## Overview

Every `egg template` subcommand accepts a template name as an optional
positional argument. Omit it and egg prompts interactively, listing
available templates to choose from — the same interactive fallback
`egg hatch` uses when no template is named.

```sh
egg template <subcommand> [<template-name>] [options]
```

## Creating and installing

`create` scaffolds a new template directory with a starter `config.yml` and
one placeholder file:

```sh
egg template create --name SwiftPackage --description "A minimal Swift package" --location project
```

| Flag | Purpose |
| --- | --- |
| `--name` | Template name (required with `--json`). |
| `--description` | One-line description shown in listings. |
| `--location` | `project` (`./.eggs/`) or `global` (`~/.eggs/`). |
| `--no-config` | Skip generating `config.yml` — bring your own. |
| `--directory` | Create the template in a specific directory instead of the default location. |

`install` fetches templates from a Git repository or a local directory
instead of authoring one from scratch:

```sh
egg template install https://github.com/example/templates --global
```

| Flag | Purpose |
| --- | --- |
| `-g`/`--global`, or omit for project-local | Install location. |
| `-f`/`--force` | Overwrite templates that already exist locally. |
| `-b`/`--branch`, `-t`/`--tag`, `-c`/`--commit` | Pin a Git ref (mutually relevant only for Git sources). |
| `--include`, `--exclude` | Install (or skip) specific template names from a source that ships several. |

## Inspecting

`list` shows every template egg can find — global, project-local, and any
`--template-search-paths` — with its location and description:

```sh
egg template list
```

`detail` prints a specific template's macros, each with its CLI flag, type,
and description, plus a ready-to-run example command:

```sh
egg template detail SwiftPackage
```

`open` reveals the template's directory in Finder, useful when you know the
name but not where it lives (global vs. project).

## Changing and removing

`duplicate` copies an existing template under a new name — handy for
forking a close variant without hand-copying files:

```sh
egg template duplicate SwiftPackage --name SwiftPackageTests
```

`move` relocates a template between `project` and `global`:

```sh
egg template move SwiftPackage --to global
```

`delete` removes a template directory permanently; pass `--force` to skip
the confirmation prompt.

## Validating

`validate` runs the same checks `hatch` runs before expanding a template —
macro name format and uniqueness, reserved built-in names (see
<doc:BuiltInMacros>), `choices`/`validate` field compatibility, macro flag
collisions with built-in `hatch` flags, undefined macro references in
lifecycle steps or `hatch.exclude` conditions, and `hatch.exclude`/
`sandbox.allowed_paths` structure — without hatching anything:

```sh
egg template validate ./.eggs/SwiftPackage
```

Run it after hand-editing a `config.yml`, or before sharing a template, to
catch mistakes before someone else's `hatch` fails on them.

## Structured output for agents

Every subcommand above accepts `--json`, which prints the same Codable
model its matching MCP tool (`egg_template_list`, `_detail`, `_create`,
`_delete`, `_duplicate`, `_move`, `_validate`, `_install`) returns — there is
no prose to parse. `--json` runs in direct mode, so every required value
must be supplied as a flag; it never falls back to an interactive prompt.
See <doc:AgentSkillsAndPlugins> for the MCP tool surface and the
recommended agent flow.
