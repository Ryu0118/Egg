# egg

egg is a template scaffolding CLI built for AI agents. Templates define macros
in `config.yml`, use `___MACRO_NAME___` placeholders in files and directories,
and egg expands them with provided values.

The hatch flow is a transaction: an agent **previews** the changes a template
would make (in an isolated, git-backed staging clone), **applies** them only
after approval, and can **roll back** an applied scaffold. Every transaction
command emits JSON so an agent can parse the result directly.

## Installation

egg is a Swift Package Manager executable. It requires **macOS 26+** and the
**Swift 6.2** toolchain.

```sh
git clone https://github.com/Ryu0118/egg.git
cd egg
swift build -c release
# the binary is at .build/release/egg — copy it onto your PATH, e.g.:
cp .build/release/egg /usr/local/bin/egg
```

Or run it directly without installing:

```sh
swift run egg -- --help
```

Prebuilt universal binaries are also attached to each
[GitHub Release](https://github.com/Ryu0118/egg/releases).

## Template Locations

- Global templates: `~/.eggs/<TemplateName>/`
- Project templates: `./.eggs/<TemplateName>/`

Each template directory contains `config.yml` and template files.

## Requirements

The working directory **must be a git repository**. egg uses the project's own
`.gitignore` as the single source of truth for what counts as a change: the
staging clone carries your tracked `.gitignore`, so artifacts a lifecycle script
generates (e.g. `node_modules`, `.build`) are suppressed by the same rules git
already applies. There is no hardcoded list of excluded directories. If the
working directory is not a git repository, hatch fails and asks you to run
`git init` first.

## Agent transaction flow

Every command below emits JSON and never prompts.

Inspect exact macro names, flags, MCP tool names, and a recommended flow:

```sh
egg template detail MyTemplate
```

Preview a hatch without writing anything to the working directory:

```sh
egg hatch preview MyTemplate --name MyApp --enabled true
```

The preview response includes `applyToken`, `changes`, `warnings`, and
`nextCommands`. Useful options:

- `--include <pathspec>` — force a normally-ignored path into the change set
- `--exclude <pathspec>` — drop paths from the change set
- `--output <dir>` — directory the generated output targets
- `--diff` — include each change's unified diff in the output (off by default)

Apply a previewed transaction (records a rollback bundle):

```sh
egg hatch apply <applyToken>
```

Roll back an applied transaction:

```sh
egg hatch rollback <rollbackId>
```

Discard a preview without applying it:

```sh
egg hatch discard <applyToken>
```

## Human / inline flow

```sh
egg hatch                        # interactive: prompts for template and macros
egg hatch direct MyTemplate ...  # applies inline, no preview/token step
```

`egg hatch` with no subcommand drops into interactive mode.

## MCP flow

Agents should use the transaction tools instead of one-shot hatch:

1. `egg_template_detail` — read required macros and the recommended flow
2. `egg_hatch_preview` — create a transaction without applying
3. inspect `changes` and `warnings`
4. `egg_hatch_apply` — apply only after approval
5. `egg_hatch_rollback` — optionally undo

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

`egg_hatch` remains available for compatibility but defaults to preview mode
unless `apply_changes: true` is passed.

## Rollback scope

Rollback restores managed workspace file changes only. It does not undo network
calls, writes outside the project, package-manager global caches, or other
external side effects from lifecycle scripts. The preview/apply response carries
a `rollback_scope` warning to make this explicit.

## License

egg is available under the MIT License. See [LICENSE](LICENSE) for details.
