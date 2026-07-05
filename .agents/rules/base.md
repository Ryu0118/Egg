# egg - A Template Scaffolding Tool

A CLI tool for generating projects from templates. Define macros in `config.yml`, use `___MACRO_NAME___` placeholders in files/directories, and egg expands them with user-provided values.

## Directory Structure

| Path | Purpose |
|------|---------|
| `Sources/egg/` | Entry point only - just calls EggCLI |
| `Sources/EggCLI/` | CLI command definitions (ArgumentParser). Thin layer, no business logic |
| `Sources/EggKit/` | **All implementation**. Runners, validators, config parsing, template expansion |
| `Sources/EggKit/Config/` | `config.yml` model and validation |
| `Sources/EggKit/Validation/` | Egg domain validation rules built on Interaction validation primitives |
| `Sources/EggKit/WorkflowRunner/` | Lifecycle execution engine (pre_hatch → hatch → post_hatch) |
| `Sources/EggMCP/` | MCP server: tool handlers exposing egg to AI agents |
| `Sources/EggKit/EggKit.docc/` | DocC guides for agent integrations, template config, and transaction flow |
| `Tests/EggKitTests/` | Unit tests |
| `Tests/EggMCPTests/` | MCP module unit tests |
| `E2ETestsPackage/` | E2E tests (separate package). Run with `cd E2ETestsPackage && swift test` |

## Naming Conventions

| Pattern | Purpose |
|---------|---------|
| `*Runner.swift` | Command execution logic (e.g., `HatchRunner.swift`) |
| `*ArgumentsValidator.swift` | Input validation before running |
| `ConfigValidator+*.swift` | Partial validators for config.yml sections |

## Template Locations

- Global: `~/.eggs/<TemplateName>/`
- Project-local: `./.eggs/<TemplateName>/`

Each template contains `config.yml` and template files with `___MACRO_NAME___` placeholders.

## Available Skills

When working on egg templates or CLI usage, read these skills for detailed reference:

| Skill | When to use |
|-------|-------------|
| `egg-template` | Creating/updating templates (`config.yml`, macro types, lifecycle hooks) |
| `egg-cli-guide` | CLI commands, agent transaction flow (preview/apply/rollback/discard), argument ordering |

## Notes

- Swift 6.2 / macOS 26+
- Use `package` access modifier for cross-module types
- `make lint` runs both SwiftLint and my-swift-linter. Install hooks with `make hooks`; pre-push runs `make my-lint`.
- `make docs` builds the EggKit DocC archive.

## Code Review Checklist

Apply these when reviewing or refactoring code in this repo:

- **Directory splits stay behavior-neutral.** Prefer pure `git mv` in its own commit before any content edit — git records clean renames, and a bisect/revert stays possible. Verify SPM still builds with no `Package.swift` change (it auto-discovers sources recursively).
- **No lone-file directories, no all-directory root.** Group ≥2-3 related files per subdirectory; keep the public entry point and single-file concerns at the module root rather than forcing them into a directory of one.
- **Comment the "why", not the "what".** Add comments only where logic has a non-obvious invariant or encodes an external spec (e.g. sandbox path resolution, transaction status transitions, Stencil/macro expansion edge cases). Skip comments on self-explanatory code.
- **Don't extract abstractions from superficially similar code.** Before factoring out a shared helper, check what's actually identical across call sites vs. what only looks similar — if the guard condition, the non-shared branch, and the return shape all differ, the "dedup" adds an awkward helper for near-zero line savings. Leave near-duplicates alone unless the shared part is substantial.
- **Widening access (`private` → `internal`/`package`) to enable a file split is fine** as long as no `public` signature changes.
- **Re-run `swift build`, `swift test`, and `make lint` after every content-changing commit**, not just at the end — the pre-commit hook (`swiftlint --strict` + my-swift-linter) will hard-block a bad commit, and it's cheaper to catch drift immediately.
- **Check `docsync.yml` after moving or editing any file it tracks** (`docsync check` / `docsync update-checksum`) — moved source paths and edited files both invalidate its checksums, and the pre-commit hook fails the commit until resynced.
- **Clean up untracked cruft found along the way** (e.g. stray `.DS_Store`) as part of the same pass, even if unrelated to the main task.
- **Skill/plugin docs must work from the consumer's environment, not this repo's.** `skills/*/SKILL.md` and their `references/*.md` are installed into other projects via the plugin — they must not point at this repo's own source tree, `Makefile` targets (e.g. `make docs`), or other paths that don't ship with the skill.
- **DocC's published site is a JavaScript-rendered SPA, not a fetchable doc.** A plain HTTP fetch (`curl`, `WebFetch`) of a `documentation/...` page returns only a `<noscript>` shell with no content — verified on the sibling Interaction package's published DocC site. If a skill or doc ever needs to point an agent at API docs for fetching, use the DocC-Render JSON data endpoints instead (same host, `data/documentation/<module>/<lowercased-symbol>.json`), not the human-facing page.
