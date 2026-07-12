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

A `--global` install from a Git source also registers itself into the
global manifest, so future `sync`/`update` runs manage it too — see
<doc:TemplateManifests>'s "Registering from install" section for exactly
what gets written.

## Declarative manifests: sync and update

`sync` installs everything declared in an `eggs.yml` manifest instead of
taking a source on the command line. Two scopes are processed
independently: the global manifest at `$XDG_CONFIG_HOME/egg/eggs.yml`
(default `~/.config/egg/eggs.yml`) installs into `~/.eggs/`, and the
project manifest at `./eggs.yml` installs into `./.eggs/`.

```yaml
templates:
  - url: owner/repo                # GitHub shorthand
    from: "1.0.0"                  # upToNextMajor: highest tag in [1.0.0, 2.0.0)
    only: [SwiftCLI]               # optional name filter (or `exclude:`)
  - url: git@github.com:owner/private-templates.git
    branch: main
  - url: ./local-templates         # installed as-is, never locked
```

Every Git entry takes exactly one of `from:`, `exact:`, `branch:`, or
`revision:`. Resolution enumerates the remote's tags without cloning,
ignores non-semver tags and prereleases (unless the `from:` bound itself
is a prerelease), tolerates a `v` prefix, and installs from the exact
resolved commit.

```sh
egg template sync     # resolve, install, and write eggs-lock.yml
egg template update   # re-resolve from:/branch: entries to the latest eligible
```

`sync` records each resolution (tag and commit SHA) in an `eggs-lock.yml`
next to the manifest and reuses those pins while they still satisfy the
manifest — `Package.resolved` semantics. `update` is the explicit way to
move forward; editing the manifest constraint also invalidates the pin.
Manifest-managed template names are overwritten on every sync; templates
not declared in a manifest are never touched. Both commands accept
`--global`/`--project`, `--dry-run`, and `--json`, and exit nonzero when
any entry fails (healthy entries still install, and a failing entry keeps
its previous lock pin).

See <doc:TemplateManifests> for the full manifest reference: field
tables, `from:` range semantics, lockfile format, reuse rules, and the
dotfiles workflow.

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
