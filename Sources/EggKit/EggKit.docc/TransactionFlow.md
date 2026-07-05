# Transaction Flow

Preview, apply, roll back, discard, or list generated changes.

## Overview

The agent flow is non-interactive and JSON-oriented. It lets an assistant show
the generated change set before writing to the real working directory.

```sh
egg hatch preview <template> [--macro-name value ...] [--diff]
egg hatch apply <applyToken>
egg hatch rollback <rollbackId>
egg hatch discard <applyToken> [--force]
egg hatch transactions
```

Every transaction moves through one state machine, recorded in
`.egg/transactions/<token>/metadata.json` — the single source of truth for
status:

```
preview ──apply──▶ applied ──rollback──▶ rolledBack ──apply──▶ applied (fresh bundle)
preview ──discard──▶ deleted
rolledBack ──discard──▶ deleted
applied ──discard --force──▶ deleted (records only; applied files stay)
```

The `applyToken` and `rollbackId` of a transaction are always the same value,
so one identifier names the whole lifecycle.

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

Apply also accepts a `rolledBack` transaction: the staged output is retained
after rollback and lifecycle steps ran at preview time, so re-apply is a pure
file copy. A fresh rollback bundle replaces the consumed one under the same id,
and the result carries a `reapplied_after_rollback` warning.

## Rollback

`rollback <rollbackId>` restores the pre-apply state for files managed by the
transaction and marks the transaction `rolledBack`, re-enabling `apply` for the
same token.

Rollback refuses to overwrite hand-edited generated files unless `--force` is
passed.

## Discard

`discard <applyToken>` deletes a transaction's records — the staged transaction
and its rollback bundle — as a pair, from any state. Files already applied to
the working directory are never touched.

What is lost depends on the status: a `preview` loses only its staged proposal,
a `rolledBack` transaction loses the option to re-apply, and an `applied`
transaction loses its rollback bundle — the only way to undo the apply — which
is why that state requires `--force`.

Use discard when the user rejects a previewed change, and as cleanup once an
applied result is accepted and no longer needs to be undoable.

## Transactions

`transactions` lists every record under `.egg/transactions` and `.egg/rollback`
as JSON: token, status, template name, and whether a rollback bundle exists.
Pass `--size` to also compute each record's disk footprint (`sizeBytes`) —
that walks the full staged trees, so it can be slow on large histories.

Beyond the state-machine statuses, two extra values can appear: `corrupt` for
an unreadable `metadata.json`, and `orphanedRollback` for a bundle whose
transaction directory is gone (left by older egg versions). Both can be removed
with `discard`.
