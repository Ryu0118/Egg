# Template Manifests

Declare external template sources in `eggs.yml` and let egg resolve, fetch,
and pin them — a `Package.swift` for your templates.

## Overview

`egg template install` is imperative: it fetches templates once and leaves
no record of where they came from or which version was installed. A
manifest turns that into a declaration. You write *what* you want in
`eggs.yml`; `egg template sync` figures out *which revision* that means,
installs it, and records the answer in `eggs-lock.yml` so every later sync
— on this machine or another — produces the same bytes.

Two manifest scopes exist and are processed independently:

| Scope | Manifest | Lockfile | Installs to |
| --- | --- | --- | --- |
| Global | `$XDG_CONFIG_HOME/egg/eggs.yml` (default `~/.config/egg/eggs.yml`) | next to the manifest | `~/.eggs/` |
| Project | `<project>/eggs.yml` | `<project>/eggs-lock.yml` | `<project>/.eggs/` |

If the same URL appears in both manifests, nothing is merged: each scope
installs its own copy into its own `.eggs` directory.

## The manifest: eggs.yml

```yaml
eggs:
  - url: Ryu0118/swift-egg-templates   # GitHub shorthand
    from: "0.3.0"                       # upToNextMajor range
    only: [SwiftCLI, SwiftLibrary]      # optional name filter
  - url: git@github.com:owner/private-templates.git
    branch: main                        # follow a branch (floating, opt-in)
    exclude: [Experimental]
  - url: https://github.com/owner/repo.git
    exact: "1.2.0"
  - url: https://github.com/owner/repo2.git
    revision: 6c0f1a2b9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a
  - url: ./local-templates              # local path: never locked
```

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `url` | String | yes | Git URL (https/ssh/git/file), GitHub shorthand `owner/repo`, or local path |
| `from` | String | one of the four, for Git entries | Highest tag in `[from, nextMajor)`, SwiftPM semantics |
| `exact` | String | 〃 | Single version, matched by parsed-version equality |
| `branch` | String | 〃 | Branch to follow; `sync` installs the locked revision, `update` the tip |
| `revision` | String | 〃 | Commit SHA, trivially pinned |
| `only` | [String] | optional | Install only these template names |
| `exclude` | [String] | optional | Install everything except these names; mutually exclusive with `only` |

How a `url` is classified, deterministically and without touching the
filesystem:

1. `owner/repo` with no scheme and no leading `./`, `/`, or `~` is GitHub
   shorthand and expands to `https://github.com/owner/repo.git`.
2. Anything `git clone` accepts (https, ssh, `git://`, `file://`) is a
   Git URL.
3. Everything else is a local path. Write local paths as `./x`, `../x`,
   `/abs`, or `~/x`; relative paths resolve against the manifest's own
   directory, so a dotfiles-managed global manifest can carry its own
   template directories.

Git entries must carry exactly one of `from`/`exact`/`branch`/`revision`.
Local entries must carry none (there is nothing to resolve — the directory
is installed as-is on every sync). An empty or missing `eggs:` key is
a valid no-op.

### What `from:` selects

`from:` is SwiftPM's `.upToNextMajor`: the half-open range from the given
version up to the next major. Prereleases are excluded unless the bound
itself is a prerelease. A `v` tag prefix is tolerated; when a version is
tagged both ways (`1.2.3` and `v1.2.3`), the non-`v` tag wins.

| `from:` | Selected | Rejected |
| --- | --- | --- |
| `"1.0.0"` | 1.0.0, 1.0.1, 1.99.99 | 2.0.0, 0.9.9, 1.5.0-beta.1 |
| `"1.2.0-rc.1"` | 1.2.0-rc.1, 1.2.0-rc.2, 1.2.0, 1.3.0 | 1.2.0-beta.1, 2.0.0 |

Resolution never clones to answer this: egg enumerates the remote's tags
with `git ls-remote --tags`, parses them as strict SemVer (non-semver tags
are ignored), picks the highest satisfying version, and then installs from
that tag's exact commit — the peeled commit for annotated tags.

## The lockfile: eggs-lock.yml

`sync` writes the resolution result next to the manifest:

```yaml
eggs:
- requirement:
    from: "0.3.0"
  resolved:
    revision: 6c0f1a2b9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a
    tag: "0.4.2"
    version: 0.4.2
  url: https://github.com/Ryu0118/swift-egg-templates.git
version: 1
```

| Manifest requirement | Lock records |
| --- | --- |
| `from` / `exact` | resolved `version`, actual `tag` string, commit `revision` |
| `branch` | `branch` name and the pinned `revision` |
| `revision` | the `revision` (trivially locked) |
| local path | nothing — local entries are never locked |

The lock follows `Package.resolved` semantics:

- **`sync` reuses a pin while it still satisfies the current manifest.**
  A locked `1.1.0` under `from: "1.0.0"` installs from the locked commit
  without consulting the remote. Bump the manifest to `from: "2.0.0"` and
  the pin no longer satisfies it, so sync re-resolves.
- **`update` ignores pins.** `from:` ranges move to the highest satisfying
  tag, `branch:` entries move to the branch tip, and the lock is rewritten.
- **Installs always check out the pinned commit**, not the tag name — a
  re-pointed tag upstream cannot change what you get.
- The lock is regenerated from the manifest on every write: entries whose
  URL left the manifest drop out, and a *failing* entry keeps its previous
  pin (a transient SSH failure must not lose your version).

Commit `eggs-lock.yml` alongside `eggs.yml`. Entries are sorted and keys are
stable, so diffs stay one-line small: a version bump reads as exactly the
`requirement`/`resolved` lines that changed.

## Syncing and updating

```sh
egg template sync              # every manifest that exists (global + project)
egg template sync --project    # one scope only
egg template update --global   # move global pins to the latest eligible
egg template sync --dry-run    # resolve and report; no install, no lock write
egg template sync --json       # machine-readable result for agents/CI
```

Manifest-managed template names are overwritten on every sync — the
manifest is the source of truth for those names. Templates *not* declared
in a manifest are never touched; there is no pruning. When two entries
provide the same template name, the earlier manifest entry wins and the
later one is reported as failed — disambiguate with `only:`/`exclude:`.

A failing entry (authentication, no matching version, missing branch) does
not abort the run: healthy entries still install, the failure is reported
with the underlying git stderr, and the command exits nonzero.

Over MCP the same workflow is exposed as `egg_template_sync` and
`egg_template_update` (arguments `scope`, `dry_run`, `project_directory`),
returning the same JSON as the CLI's `--json` flag.

## Registering from install

`egg template install <git-url> --global` bridges the imperative and
declarative worlds: after installing, it also upserts an entry for that
repo into the global `eggs.yml` (creating it if needed) and pins the
resolved commit in `eggs-lock.yml`, so the repo is managed by future
`sync`/`update` runs without any manual manifest editing.

| Install flag | Requirement written |
| --- | --- |
| `--tag <name>`, parses as SemVer | `exact: <version>` |
| `--tag <name>`, not SemVer | `revision: <resolved-SHA>` |
| `--branch <name>` | `branch: <name>` |
| `--revision <sha>` | `revision: <sha>` |
| none (default branch) | `revision: <resolved-SHA>` |

Tag SHAs resolve via a remote `ls-remote` lookup (no extra clone); branch
and default-branch SHAs resolve from the already-cloned working directory.
Re-running `install --global` against an already-declared URL replaces that
entry's requirement in place rather than duplicating it, and keeps the
existing `only:`/`exclude:` filter unless the new install passed
`--template`/`--exclude` explicitly — so a filter-less re-install can't
silently widen an already-scoped entry back open.

`--project` and local-path installs never touch any manifest — this is a
`--global` git-source-only behavior. If registration fails after the
templates already installed (e.g. a permission error writing
`~/.config/egg/`), the install itself still succeeds; a warning is printed
instead.

## Troubleshooting

- **`no version satisfying 'from: X'`** — the error names the highest
  semver tag the remote advertises; either lower the bound or ask the
  template author to cut a release.
- **`branch 'X' not found`** — the remote does not advertise that branch;
  check the spelling against `git ls-remote <url>`.
- **`git ls-remote failed`** — the underlying git stderr is printed
  verbatim; SSH keys and credential helpers are used exactly as your
  `git` CLI would.
- **`version specifiers are not allowed for local paths`** — a bare path
  like `/tmp/repo` is a *local* entry even if it happens to be a git
  checkout. Use a `file://` URL if you want tag resolution against it.
