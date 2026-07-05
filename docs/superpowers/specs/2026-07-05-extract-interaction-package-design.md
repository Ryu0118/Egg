# Extract Interaction into `swift-interaction` package

Date: 2026-07-05
Repo target: `git@github.com:Ryu0118/swift-interaction.git`
New local path: `../Interaction` (sibling of `Egg`)

## Goal

Move the `Interaction` module out of the `Egg` monorepo into its own standalone
Swift package at `../Interaction`, together with the full development harness
(linters, formatters, git hooks, CI workflows, docs, agent skills/plugins).
Egg then depends on the extracted package via SwiftPM.

## Why this is safe

`Sources/Interaction/` has **zero** dependencies on `EggKit`, `EggCLI`, or
`EggMCP` (verified: no `import EggKit/EggCLI/EggMCP` anywhere under
`Sources/Interaction` or `Tests/InteractionTests`). Its only consumers are
inside Egg. So the module code and its tests move verbatim; only Egg's
`Package.swift` and a few harness references change.

## New package layout (`../Interaction`)

```
Interaction/
├── Package.swift                 # name: swift-interaction; product: Interaction; no external deps
├── Sources/Interaction/          # moved verbatim (21 files)
│   └── Interaction.docc/         # NEW DocC catalog
├── Tests/InteractionTests/       # moved verbatim (7 files)
├── README.md                     # egg/ctxmv-style, library Installation section
├── LICENSE                       # MIT, copied from Egg (author unchanged)
├── Makefile                      # format / swiftlint / my-lint / lint / test / docs / check  (no e2e)
├── AGENTS.md  -> .agents/rules/base.md   # symlink
├── CLAUDE.md  -> .agents/rules/base.md   # symlink
├── .agents/
│   ├── rules/base.md             # NEW: Interaction-specific agent rules
│   ├── plugins/marketplace.json  # Codex marketplace
│   └── skills/interaction-guide -> ../../.claude/plugins/interaction/skills/interaction-guide
├── .claude/plugins/interaction/  # SSoT for skills + plugin manifest
│   ├── .claude-plugin/plugin.json
│   └── skills/interaction-guide/SKILL.md (+ references/)
├── .claude-plugin/marketplace.json   # Claude Code marketplace
├── plugins/interaction/
│   ├── .codex-plugin/plugin.json
│   └── skills -> ../../.claude/plugins/interaction/skills   # symlink
├── .cursor/rules/base.mdc        # NEW: mirrors base.md
├── nestfile.yaml                 # swiftformat, swiftlint, gitnagg, my-swift-linter, docsync
├── .mise.toml                    # gitleaks
├── .swiftformat
├── .swiftlint.yml
├── .swift-ast-lint.yml           # missing-docs include -> Sources/Interaction/**
├── .gitignore
├── .gitnagg.yml
├── docsync.yml                   # remapped for Interaction sources/docs
├── .githooks/{pre-commit,pre-push}
├── scripts/{nest.sh,setup-hooks.sh}
└── .github/workflows/
    ├── test.yml                  # lint + unit tests (no e2e job)
    ├── docs.yml                  # DocC -> Pages, target Interaction
    ├── release.yml               # LIGHTWEIGHT: tag-triggered GitHub Release only (no binary)
    ├── docsync-check.yml
    └── gitleaks.yml
```

## Package.swift (new package)

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-interaction",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Interaction", targets: ["Interaction"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.1.0"),
    ],
    targets: [
        .target(name: "Interaction", dependencies: []),
        .testTarget(name: "InteractionTests", dependencies: ["Interaction"]),
    ]
)
```

`swift-docc-plugin` is kept so `make docs` works standalone.

## Harness adaptation rules (Egg -> Interaction)

Copy each harness file from Egg, then adapt:

- **Makefile**: drop `e2e-test`; `MY_SWIFT_LINTER_PATHS := Sources Tests Package.swift`;
  `docs` target uses `--target Interaction`; `check: format lint test`.
- **.swift-ast-lint.yml**: `included_paths` drop `E2ETestsPackage/...`;
  `missing-docs.include` -> `Sources/Interaction/**` only (drop the Egg Staging path).
- **.swiftlint.yml / .swiftformat**: drop `E2ETestsPackage` excludes/includes.
- **.githooks/pre-commit**: lint paths `Sources Tests Package.swift` (no E2E).
- **.github/workflows/test.yml**: remove the `e2e-tests` job and E2E path filters;
  keep `swiftlint` + `unit-tests`.
- **.github/workflows/docs.yml**: `--target Interaction`.
- **.github/workflows/release.yml**: replace binary-build pipeline with a
  lightweight tag-triggered `gh release create` (library needs no binary artifact).
- **docsync.yml**: rebuild source->doc checksum mappings for Interaction files.
- **nestfile.yaml, .mise.toml, .gitnagg.yml, .gitignore, gitleaks.yml,
  docsync-check.yml, scripts/**: copy as-is (path-agnostic).

## Agent skill / plugin distribution

Interaction is a **library**, so there is **no MCP server**. Distribute one
developer-facing skill, `interaction-guide`, that documents the Interaction API
(prompts, single/multiple choice, table, styled text, validation, terminal
capabilities). Structure mirrors Egg's two-marketplace setup, minus all MCP
wiring (`.mcp.json` and `mcpServers` keys are omitted).

- SSoT: `.claude/plugins/interaction/skills/interaction-guide/`
- `plugins/interaction/skills` and `.agents/skills/interaction-guide` are symlinks into the SSoT.
- `.claude-plugin/marketplace.json` (Claude Code) and
  `.agents/plugins/marketplace.json` (Codex) advertise the plugin.
- `.claude/plugins/interaction/.claude-plugin/plugin.json` and
  `plugins/interaction/.codex-plugin/plugin.json` are the plugin manifests.

## README (new package)

egg/ctxmv-style. Sections: title + badges, short description, Features,
Quick Start for Agents (install the Claude Code / Codex plugin, ask about the
API), Quick Start for Humans (minimal Swift usage snippet: a prompt + a choice),
Installation (SwiftPM `.package(url:...)`), Documentation (DocC + `make docs`),
Development (`make` targets), License. No `install.sh` (library, not a CLI).

## Egg-side changes

1. **Package.swift**:
   - Remove the `Interaction` target and the `InteractionTests` testTarget.
   - Remove `.library(name: "Interaction", ...)` product.
   - Add dependency `.package(url: "https://github.com/Ryu0118/swift-interaction", from: "0.1.0")`.
   - In `EggCLI`, `EggKit`, and `EggKitTests`, replace the bare `"Interaction"`
     dependency with `.product(name: "Interaction", package: "swift-interaction")`.
2. **Delete** `Sources/Interaction/` and `Tests/InteractionTests/`.
3. **Harness cleanup**:
   - `.swift-ast-lint.yml`: remove `Sources/Interaction/**` from `missing-docs.include`.
   - `.agents/rules/base.md`: drop the `Sources/Interaction/` row and the
     `Tests/InteractionTests/` row from the directory table.
   - `docsync.yml`: remove any Interaction-file mappings if present.
   - Package.resolved will regenerate on build.

## Versioning / ordering (confirmed with user)

Two-phase, tag `0.1.0`, `from:` reference:

1. Build out `../Interaction` fully → **fable 5 security review** → push to
   `git@github.com:Ryu0118/swift-interaction.git` → tag `0.1.0`.
2. Point Egg's `Package.swift` at `from: "0.1.0"` → `swift build` + `swift test`
   to confirm → commit.

## Git remote

Register the new repo as remote of `../Interaction`:
`git remote add origin git@github.com:Ryu0118/swift-interaction.git`.

## Constraints

- Push happens **only after** a fable 5 security review passes.
- Granular commits (per user global rules).
- No destructive git ops without explicit instruction.

## Verification

- `../Interaction`: `swift build`, `swift test`, `make lint`, `make docs` all pass.
- `Egg`: after repointing dependency, `swift build`, `swift test`,
  `cd E2ETestsPackage && swift test`, `make lint` all pass.
```
