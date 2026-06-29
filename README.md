# egg

egg is a template scaffolding CLI. Templates define macros in `config.yml`, use
`___MACRO_NAME___` placeholders in files and directories, and egg expands them
with provided values.

## Template Locations

- Global templates: `~/.eggs/<TemplateName>/`
- Project templates: `./.egg/<TemplateName>/`

Each template directory contains `config.yml` and template files.

## Human CLI

```sh
egg template list
egg template detail MyTemplate
egg hatch MyTemplate --name MyApp --enabled
```

`egg hatch` may run lifecycle scripts from the template. By default it uses a
staging workflow for preview/apply behavior.

## Agent CLI

Agent commands never prompt and always print JSON.

Inspect exact macro names, CLI flags, MCP tool names, and examples:

```sh
egg agent template-usage MyTemplate
```

Create a hatch transaction without applying it:

```sh
egg agent hatch-preview MyTemplate --name MyApp --enabled
```

The preview response includes:

- `applyToken`
- `changes`
- `warnings`
- `nextCommands.apply`
- `nextCommands.discard`

Apply a previewed transaction:

```sh
egg agent hatch-apply <applyToken>
```

Rollback an applied transaction:

```sh
egg agent hatch-rollback <rollbackId>
```

Discard a previewed transaction:

```sh
egg agent hatch-discard <applyToken>
```

## MCP Flow

Agents should use the transaction tools instead of one-shot hatch:

1. `egg_template_detail`
2. `egg_hatch_preview`
3. inspect `changes` and `warnings`
4. `egg_hatch_apply`
5. optionally `egg_hatch_rollback`

Macro keys for MCP must use the exact config names:

```json
{
  "template_name": "MyTemplate",
  "macros": {
    "___NAME___": "MyApp",
    "___ENABLED___": true
  }
}
```

`egg_hatch` remains available for compatibility, but defaults to preview mode
unless `apply_changes: true` is passed.

## Rollback Scope

Rollback restores managed workspace file changes only. It does not undo network
calls, writes outside the project, package-manager global caches, or other
external side effects from lifecycle scripts.

Generated artifact/cache directories such as `node_modules`, `.build`,
`.swiftpm`, `.venv`, `.next`, and `.turbo` are excluded from transaction change
detection.

