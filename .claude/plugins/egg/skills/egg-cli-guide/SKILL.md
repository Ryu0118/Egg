---
name: egg-cli-guide
description: CLI usage guide for the egg scaffolding tool. Use when an agent or user wants to hatch a template, needs the preview/apply/rollback/discard transaction flow, or wants to manage templates (create/list/detail/install/validate/duplicate/move/delete/open).
---

# egg CLI Guide

egg is a template scaffolding tool with macro substitution and lifecycle hooks. It is agent-first: `egg hatch` defaults to a non-interactive transaction flow that emits JSON on stdout, so an agent can preview a change, inspect it, and only commit after approval.

```
egg <subcommand>
  template   Manage templates.
  hatch      Use a template to generate files with macro substitution.
  mcp        Start the MCP server for AI assistant integration.
```

## Template Locations

- **Global**: `~/.eggs/<TemplateName>/`
- **Project-local**: `./.eggs/<TemplateName>/`

Project-local templates take precedence over global ones.

## Agent Transaction Flow (egg hatch)

This is the flow to use by default. Every command below is non-interactive and emits JSON on stdout.

```sh
egg hatch preview <template> [--macro-name value ...] [--include <pathspec>] [--exclude <pathspec>] [--output <dir>] [--diff] [--no-sandbox --user-confirmed-no-sandbox]
egg hatch apply <applyToken> [--force]
egg hatch rollback <rollbackId> [--force]
egg hatch discard <applyToken>
```

- **`preview`** stages the template in an isolated clone and reports the proposed `changes`, any `warnings`, and an `applyToken`. Nothing is written to the working directory yet.
  - `--include <pathspec>` forces a normally git-ignored path into the change set.
  - `--exclude <pathspec>` drops matching paths from the change set.
  - `--output <dir>` sets the directory the generated output targets.
  - `--diff` includes each change's unified diff in the response (off by default).
  - `--no-sandbox` disables the `sandbox-exec` guard around lifecycle scripts during preview only when paired with `--user-confirmed-no-sandbox` after explicit user approval. The command stays non-interactive and does not classify script contents.
- **`apply <applyToken>`** writes the previewed changes to the real working directory and returns a `rollbackId`. Fails if the working directory drifted since the preview, unless `--force` is passed.
- **`rollback <rollbackId>`** restores the pre-apply state. Fails if a file was hand-edited since the apply, unless `--force` is passed.
- **`discard <applyToken>`** throws away a preview without applying it.

Run `egg template detail <name>` before `preview` to learn exactly which macro flags a template needs.

### Recommended agent sequence

1. `egg template detail <name>` to read required macros.
2. `egg hatch preview <name> --macro-name value ...` to produce an `applyToken` and a change list.
3. Inspect `changes` and `warnings` in the JSON response.
4. `egg hatch apply <applyToken>` once the plan looks correct.
5. `egg hatch rollback <rollbackId>` if something needs to be undone.

Macro flags follow kebab-case derived from the macro's config name (for example a macro named `ProjectName` becomes `--project-name`).

## Human and Inline Flow (egg hatch)

```sh
egg hatch                        # interactive: prompts for template and macros
egg hatch direct MyTemplate ...  # applies inline, no preview/apply/token step
```

`egg hatch` with no subcommand drops straight into an interactive prompt (pick a template, answer for each macro). `egg hatch direct` accepts the same macro flags as `preview`/`apply` combined, plus:

| Flag | Description |
| --- | --- |
| `--no-staging` | Apply directly, skipping the preview/rollback staging step. |
| `--override-conflicts` | Overwrite existing files without prompting. |
| `--no-sandbox` | Disable the `sandbox-exec` guard around lifecycle scripts. |
| `--apply-changes` | Skip the confirmation prompt and apply immediately. |
| `--staging-root <dir>` | Use a different staging root (when output targets another directory). |
| `--picker <list\|text>` | Interactive template picker style. |

Prefer `egg hatch direct` only for one-shot human use where a preview/rollback pair isn't needed. Agents should default to the transaction flow above.

## Managing Templates (egg template)

| Command | What it does |
| --- | --- |
| `egg template create --name <n> --description <d> --location <global\|project>` | Scaffold a new template's `config.yml`. |
| `egg template install <git-url\|path> [--branch/--tag/--revision] [--template ...] [--global] [--force]` | Install templates from a Git repo or a local directory. |
| `egg template list [--location <global\|project>] [--hide-description]` | List available templates. |
| `egg template detail <name>` | Show macros, types, defaults, and an example command. |
| `egg template validate <path>` | Validate a template's `config.yml`. |
| `egg template duplicate <name> --name <new> --description <d>` | Copy a template under a new name. |
| `egg template move <name> --to <global\|project> [--force]` | Move a template between locations. |
| `egg template delete <name> [--force]` | Delete a template. |
| `egg template open <name>` | Reveal a template's directory in Finder. |

All `template` subcommands support an interactive mode when arguments are omitted, and accept `--project-directory`/`--template-search-paths` to look beyond the current directory.

## MCP Integration

`egg mcp` starts a Model Context Protocol server that mirrors the CLI transaction flow (`egg_template_detail`, `egg_hatch_preview`, `egg_hatch_apply`, `egg_hatch_rollback`, `egg_hatch_discard`). Macro keys over MCP must use the exact config names (e.g. `___MODULE_NAME___`), not the kebab-case CLI flags. To disable sandboxing for `egg_hatch_preview` or legacy `egg_hatch`, first ask the user whether to run lifecycle scripts without sandbox protection. Do not classify script contents yourself; after explicit user approval, pass both `disable_sandbox: true` and `user_confirmed_no_sandbox: true`. A legacy `egg_hatch` tool defaults to preview mode and only applies changes when `apply_changes: true` is explicitly passed.

## Troubleshooting

### "Template not found"
1. Check the template exists: `egg template list`.
2. Verify the location: `~/.eggs/` (global) or `./.eggs/` (project-local).
3. Use `--template-search-paths` for custom locations.

### "Macro X is required"
Run `egg template detail <name>` to see every required macro, then pass each as `--macro-name value` on `preview` or `direct`.

### `apply` fails with a drift error
The working directory changed since `preview` was run. Re-run `preview` to get a fresh `applyToken`, or pass `--force` to `apply` if the drift is expected.

### Lifecycle script errors
- Check script permissions.
- Use `--no-sandbox` if the sandbox blocks a legitimate operation.
- Review the script's stdout/stderr in the response for details.
