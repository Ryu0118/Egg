# Agent Skills and Plugins

Use egg from Claude Code, Codex, or any agent that can read Agent Skills or call
MCP tools.

## Overview

egg is most useful when an agent can understand the template before it runs the
scaffold. This repository provides three integration layers:

- Agent Skills teach assistants how egg commands and templates work.
- Plugins package those skills and MCP configuration for specific clients.
- The MCP server exposes structured tools for template detail, preview, apply,
  rollback, discard, and transaction listing.

## Agent Skills

The shared skills live under `.claude/plugins/egg/skills`.

| Skill | Purpose |
| --- | --- |
| `egg-cli-guide` | CLI usage, argument ordering, and transaction flow. |
| `egg-template` | Creating and updating templates, macros, lifecycle hooks, and file layout. |

Codex can also discover the same skills through `.agents/skills` when working
inside this repository.

## Claude Code

Install the plugin from the marketplace:

```sh
/plugin marketplace add Ryu0118/Egg
/plugin install egg@egg
```

The plugin includes the egg skills and MCP configuration.

## Codex

Add the marketplace, then install the plugin:

```sh
codex plugin marketplace add Ryu0118/Egg
codex plugin add egg@egg
```

To develop against a local clone, point the marketplace at the checkout:

```sh
git clone https://github.com/Ryu0118/Egg
codex plugin marketplace add ./Egg
codex plugin add egg@egg
```

Codex reads the manifest at `plugins/egg/.codex-plugin/plugin.json`. The shared
skills and MCP configuration come from the same plugin bundle through symlinks,
so Codex and Claude Code install the identical `egg` skills and tools.

## MCP

Start the server with:

```sh
egg mcp
```

Recommended agent flow:

1. Read template details.
2. Preview the hatch request.
3. Inspect changes and warnings.
4. Apply only after approval.
5. Roll back when the generated result should be undone.

Macro keys over MCP use the exact names from `config.yml`, such as
`___MODULE_NAME___`, not kebab-case CLI flags.

## Structured CLI output

An agent that drives the CLI rather than MCP gets the same structured results
by passing `--json` to any `egg template` subcommand (`list`, `detail`,
`create`, `delete`, `duplicate`, `move`, `validate`, `install`) — the flag
prints the same Codable model the matching MCP tool returns, so there is no
prose to parse. The hatch transaction commands (`preview`, `apply`, `rollback`,
`discard`, `transactions`) already emit JSON by default.

`--json` runs in direct mode, so every value must be supplied as a flag.
Interactive prompts require a TTY: when stdin is piped or closed and a command
would otherwise prompt, egg fails fast with the prompt's question and the flags
to pass instead of hanging.

