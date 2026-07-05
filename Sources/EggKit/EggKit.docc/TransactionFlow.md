# Transaction Flow

Preview, apply, roll back, or discard generated changes.

## Overview

The agent flow is non-interactive and JSON-oriented. It lets an assistant show
the generated change set before writing to the real working directory.

```sh
egg hatch preview <template> [--macro-name value ...] [--diff]
egg hatch apply <applyToken>
egg hatch rollback <rollbackId>
egg hatch discard <applyToken>
```

## Preview

`preview` creates an isolated staging area, expands the template, runs lifecycle
steps, and reports the proposed changes.

Useful flags:

| Flag | Purpose |
| --- | --- |
| `--diff` | Include unified diffs in the JSON response. |
| `--include <pathspec>` | Force a normally ignored path into the change set. |
| `--exclude <pathspec>` | Remove matching paths from the change set. |
| `--output <dir>` | Override the template output directory. |

## Apply

`apply <applyToken>` writes the previewed changes to the real working directory
and returns a `rollbackId`.

Apply fails if the working directory changed since preview. Use `--force` only
when the caller has intentionally accepted that drift.

## Rollback

`rollback <rollbackId>` restores the pre-apply state for files managed by the
transaction.

Rollback refuses to overwrite hand-edited generated files unless `--force` is
passed.

## Discard

`discard <applyToken>` removes a preview without applying it.

Use discard when an agent previews a template and the user rejects the proposed
change.

