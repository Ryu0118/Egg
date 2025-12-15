# Staging Workflow Runner Design Document

## Overview

StagingWorkflowRunner is a system for executing the entire hatch lifecycle (pre_hatch → hatch → post_hatch) atomically in a staging. All file system changes occur within a temporary staging directory (a clone of the working directory), and changes are applied to the real working directory only when all phases complete successfully.

## Problem Statement

### Current Behavior

```
┌──────────────────────────────────────────────────────────────────┐
│ LifecycleWorkflowRunner (Current)                                │
│                                                                  │
│   1. pre_hatch: Shell commands run in workingDirectory           │
│      └─ Changes are PERMANENT (not atomic)                       │
│                                                                  │
│   2. hatch: TemplateExpander uses withAtomicCopyAndWrite         │
│      └─ Changes are ATOMIC (staged)                              │
│                                                                  │
│   3. post_hatch: Shell commands ALSO run in workingDirectory     │
│      └─ Changes are PERMANENT (not atomic)                       │
│                                                                  │
│   PROBLEM: workingDirectory (often user's repo root)             │
│            accumulates pre/post side effects even on failure     │
└──────────────────────────────────────────────────────────────────┘
```

### Failure Scenarios

1. **pre_hatch succeeds, hatch fails**: Files created by pre_hatch remain in working directory
2. **pre_hatch & hatch succeed, post_hatch fails**: workingDirectory keeps partial shell side effects while template expansion may be incomplete
3. User cannot cleanly retry after failure without manual cleanup

### Desired Behavior

- All operations (pre_hatch → hatch → post_hatch) should be atomic as a unit
- Work should be done in a staging (clone of working directory)
- Only when ALL phases complete successfully should changes be applied
- If any phase fails, all file system changes should be discarded
- Changes are applied as partial diff, not full replacement

---

## Core Design Principles

1. **All-or-nothing execution**: Either the entire workflow succeeds, or no changes are made
2. **Staging = workingDirectory clone**: Single staging directory that mirrors the working directory
3. **Workspace isolation**: All operations must stay within staging boundaries
4. **Partial apply**: Only changed files are applied back to working directory
5. **Conflict detection**: Detect concurrent modifications and fail safely
6. **Automatic cleanup**: Staging is discarded on failure, no manual cleanup needed

---

## Architecture

```
┌───────────────────────────────────────────────────────────────────────────┐
│ StagingWorkflowRunner (Top-level Orchestrator)                      │
│                                                                           │
│  run(config, macros, templateDirectory)                                   │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │ 1. Create Staging (clone of workingDirectory)       │ │
│  │    └─ StagingContext.create(cloning: workingDirectory)        │ │
│  │                                                                      │ │
│  │ 2. Execute pre_hatch in staging                      │ │
│  │    └─ LifecycleStepRunner(workingDir: workspace.root)               │ │
│  │                                                                      │ │
│  │ 3. Execute hatch to staging                          │ │
│  │    └─ TemplateExpander.expand(outputDir: workspace.root/output)     │ │
│  │    └─ Validate: output path must be within staging   │ │
│  │                                                                      │ │
│  │ 4. Execute post_hatch in staging                     │ │
│  │    └─ LifecycleStepRunner(workingDir: workspace.root)               │ │
│  │                                                                      │ │
  │  │ 5. Partial apply workspace changes via staging                      │ │
  │  │    └─ workspace.stageChanges() → verify                             │ │
  │  │    └─ staging.applyTo(workingDirectory)                             │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                           │
│  On any failure:                                                          │
│    └─ workspace.discard() → Removes all staging contents  │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## Component Design

### 1. StagingContext (Actor)

**Responsibility**: Manages the lifecycle of a workspace environment

**File**: `Sources/EggKit/WorkflowRunner/Staging/StagingContext.swift`

**Interface**:
```swift
/// Manages a workspaceed environment for atomic workflow execution.
///
/// StagingContext creates a temporary directory that is a clone of the working directory.
/// All workflow operations execute within this workspace. Only when all operations complete
/// successfully are the changes applied back to the real working directory.
actor StagingContext {
    /// The workspace root directory (clone of workingDirectory).
    var root: AbsolutePath { get }

    /// The original working directory that was cloned.
    var originalWorkingDirectory: AbsolutePath { get }

    /// Watchers that record which paths changed during workspace execution.
    private let workspaceWatcher: DirectoryWatching
    private let workingDirectoryWatcher: DirectoryWatching

    /// Creates a new workspace context by cloning the working directory.
    ///
    /// - Parameters:
    ///   - workingDirectory: The directory to clone into workspace
    ///   - fileSystem: File system for operations
    /// - Returns: A new StagingContext with cloned directory
    /// - Throws: StagingContext.Error.creationFailed on file system errors
    static func create(
        cloning workingDirectory: AbsolutePath,
        fileSystem: any FileSysteming
    ) async throws -> StagingContext

    /// Validates that a path is within workspace boundaries.
    ///
    /// - Parameter path: Path to validate (can be relative or absolute)
    /// - Throws: StagingContext.Error.escapeAttempt if path escapes workspace
    func validatePath(_ path: AbsolutePath) throws

    /// Applies workspace changes to the original working directory.
    ///
    /// Computes diff between workspace and baseline, then applies:
    /// - New files: Added to working directory
    /// - Modified files: Updated in working directory
    /// - Deleted files: Removed from working directory
    ///
    /// - Parameters:
    ///   - fileSystem: File system for operations
    ///   - force: If true, override conflicts with warning. If false, throw error on conflicts.
    /// - Returns: List of conflicts that were overridden (empty if no conflicts or force=false)
    /// - Throws: StagingContext.Error.conflictingFiles if conflicts detected and force=false
    func applyChanges(
        fileSystem: any FileSysteming,
        force: Bool
    ) async throws -> [ConflictInfo]

    /// Discards the workspace without applying changes.
    ///
    /// Removes all workspace contents. Safe to call multiple times (idempotent).
    func discard(fileSystem: any FileSysteming) async
}

/// Summary of changes to be applied from workspace to working directory.
struct ChangeSummary {
    let added: [RelativePath]
    let modified: [RelativePath]
    let deleted: [RelativePath]

    var isEmpty: Bool {
        added.isEmpty && modified.isEmpty && deleted.isEmpty
    }
}
```

**Directory Structure**:
```
/tmp/egg-workspace-XXXXXX/              (root = clone of workingDirectory)
├── (all contents from workingDirectory)
└── (hatch output created here, e.g., ./MyProject/)
```

**Key Characteristics**:
- Single workspace directory (no staging/output split)
- Dual filesystem watchers capture touched paths in workspace + working dir
- All operations happen within workspace.root
- Change detection compares only watcher-reported files

**Design Rationale**:
- Actor ensures thread-safe access to workspace state
- Watcher-driven diff keeps large trees fast (no full rescans)
- Single workspace simplifies mental model
- Idempotent discard allows safe cleanup in any error path

---

### 2. Staging Errors and Types

**Responsibility**: Define workspace-specific errors and supporting types

**Files**:
- `Sources/EggKit/WorkflowRunner/Staging/StagingError.swift`
- `Sources/EggKit/WorkflowRunner/Staging/ConflictInfo.swift`
- `Sources/EggKit/WorkflowRunner/Staging/ChangeSummary.swift`

**Interface**:
```swift
extension StagingContext {
    enum Error: LocalizedError, Equatable {
        case alreadyDiscarded
        case creationFailed(reason: String)
        case escapeAttempt(path: String)
        case conflictingFiles([ConflictInfo])
        case userAborted
        case applyFailed(reason: String)
    }

}
```

---

### 3. Change Detection and Partial Apply

**Responsibility**: Detect changes and apply only the diff to working directory.

**File**: Logic lives inside `StagingContext.applyChanges`

**Change Detection Approach (Dual FSEvents)**:

1. **Watch both trees**: Immediately after cloning, start lightweight filesystem watchers on `workspace.root` and on the original working directory. Each watcher accumulates relative paths that actually changed during the run.
2. **Limit diff scope**: When hatch completes, union the two path sets. Only those paths are compared (via `git diff --no-index` or an equivalent file comparer) to derive Added / Modified / Deleted entries for `ChangeSummary`.
3. **Surface potential conflicts**: Any path that appears in the working-directory watcher set is automatically treated as “potential conflict,” regardless of the diff outcome. This conservatively flags files the user touched mid-run.
4. **Apply only what changed**: The resulting change list (typically tiny compared to the full tree) drives the partial-apply step—new files copied in, modified files overwritten, deleted files removed.

**Conflict Matrix**:

| Staging | Working Dir Event | Result |
|---------|-------------------|--------|
| Added   | No                | Add |
| Added   | Yes               | Potential conflict (new file created both sides) |
| Modified| No                | Update |
| Modified| Yes               | Potential conflict |
| Deleted | No                | Delete |
| Deleted | Yes               | Potential conflict |

**Implementation Notes**:
- The design focuses on “signal extraction” (watchers + minimal diffs). Actual scheduling of watcher draining, git invocations, and copy/delete operations is left to the implementation plan.
- Potential conflicts are decided purely from watcher overlap. Interactive runs prompt before overriding; non-interactive runs fail fast unless `--force` was specified.
- Cleanup (removing the workspace directory, disposing watchers) follows the same guarantees as the original design.

This targeted approach dramatically reduces work on large projects (e.g., untouched `node_modules` never enters the diff), while still surfacing all user-edited paths as potential conflicts.

### Apply Staging Area

- **Purpose**: guarantee that no partial changes reach the real working directory even if a late failure occurs.
- **Mechanics**:
  1. `StagingContext` materializes every add/modify/delete described by the watcher-derived change set inside a temporary `applyStagingRoot` created via `FileSystem.makeTemporaryDirectory` (typically under `/tmp/egg-apply-staging-XXXXXX`). This keeps staging isolated from both the workspace and working directories while still benefiting from fast local storage.
  2. The staging step performs file copies, deletions, permission updates, and conflict resolution exactly as they would occur on the real tree, but against the staging root. Errors (permission issues, disk full, template bugs) surface here before the working directory is touched.
  3. Once staging succeeds, the helper returns a `ChangeManifest` describing everything that was materialized. `StagingContext` owns this manifest (ensuring single source of truth) and passes it back to the helper for the apply phase.
  4. A final, deterministic pass streams staged contents into the real working directory (Deletes → Adds → Modifies). Because all side effects are already computed, this pass is a simple transfer with well-defined rollback data.
- **Additional requirements**:
  - `applyStagingRoot` must be automatically cleaned up, even on crash/abort.
  - Disk space check: ensure there is enough space for staging before copying large trees.
  - File metadata parity (permissions, executability, timestamps) must be preserved so transfer back is faithful.
  - Conflict overrides (`--force`) are recorded in staging metadata so the user can see which files were overwritten during the final apply.
  - Errors raised during staging/apply are encapsulated by `ApplyStagingArea.Error`, a nested enum that groups staging-specific failure reasons (rollback failure, missing staged artifact). Keeping the error scoped to the type upholds single-responsibility boundaries and avoids polluting the global namespace.

### Conflict confirmation UX

- **Interactive mode**: if potential conflicts exist and `--force` is not supplied, Noora lists the paths and prompts `Override these files? [y/N]`. Choosing `y` proceeds (equivalent to force for this apply), otherwise the run aborts cleanly.
- **Non-interactive / direct mode**: potential conflicts immediately raise `StagingContext.Error.conflictingFiles` unless `--force` was set on the CLI.
- **Force flag**: skips prompts in both modes and records overridden paths for warning output after apply.

### 4. Staging Escape Detection

**Responsibility**: Prevent operations from accessing paths outside the workspace.

**Applies to**:
- pre_hatch shell commands
- hatch output path
- post_hatch shell commands

**Detection Methods**:

1. **Path Validation** (for explicit paths like hatch output):
```swift
func validatePath(_ path: AbsolutePath) throws {
    let normalizedPath = path.lexicallyNormalized()
    guard normalizedPath.isDescendant(of: root) else {
        throw StagingContext.Error.escapeAttempt(path: path.pathString)
    }
}
```

2. **Environment Variables** (for shell scripts):
```bash
STAGING_ROOT=/tmp/egg-workspace-xxx
EGG_ORIGINAL_WORKING_DIR=/Users/user/projects  # Read-only reference
```

3. **Working Directory Enforcement**:
- Shell scripts execute with `workingDirectory` set to workspace.root
- Relative paths stay within workspace
- Absolute paths outside workspace will fail (no access)

**Current Implementation (Incomplete)**:

The current implementation does **not** use OS-level sandboxing. It only provides:
- Working directory set to workspace.root
- Environment variables (`STAGING_ROOT`, `EGG_ORIGINAL_WORKING_DIR`) for reference
- Path validation for explicit outputs (hatch output directory)

⚠️ **This is insufficient.** Shell scripts can escape the staging via `cd ..`, absolute paths, or symlinks.

**Required Implementation (TODO)**:

OS-level sandboxing **must** be implemented:
- macOS: `sandbox-exec` with generated profile restricting file access to workspace.root
- Linux: `landlock` or similar mechanism

Without this, the staging only provides atomicity but not security isolation. This is a **required feature**, not optional.

---

### 5. StagingWorkflowRunner

**Responsibility**: Orchestrate the complete lifecycle workflow atomically within a workspace

**File**: `Sources/EggKit/WorkflowRunner/StagingWorkflowRunner.swift`

**Interface**:
```swift
/// Orchestrates atomic lifecycle workflow execution in a workspaceed environment.
struct StagingWorkflowRunner: WorkflowRunning {
    init(
        processRunner: any ProcessRunning,
        fileSystem: any FileSysteming,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        noora: some Noorable,
        isInteractive: Bool,
        force: Bool = false  // Skip user confirmation before apply
    )

    /// Executes the complete lifecycle workflow atomically.
    /// Shows change summary and prompts for confirmation unless force=true.
    func run(
        config: Config,
        macros: [ResolvedMacro],
        templateDirectory: AbsolutePath
    ) async throws -> AbsolutePath
}
```

**Design Rationale**:
- Wraps existing components rather than modifying them
- Same interface as `LifecycleWorkflowRunner` via `WorkflowRunning` protocol
- Automatic cleanup in error path ensures no orphaned workspace directories

---

## Data Flow

```
Input:
  ├─ config: Config (with pre_hatch, hatch, post_hatch definitions)
  ├─ macros: [ResolvedMacro]
  └─ templateDirectory: AbsolutePath

Flow:
  1. Create Staging (clone workingDirectory)
     ├─ StagingContext.create(cloning: workingDirectory)
     ├─ Copy all files from workingDirectory to workspace.root
     └─ Attach workspace + workingDir watchers to capture touched paths

  2. Execute pre_hatch (in workspace.root)
     ├─ LifecycleStepRunner(workingDirectory: workspace.root)
     ├─ Shell commands run, outputs captured
     ├─ Any path escape attempt → StagingContext.Error.escapeAttempt
     └─ StepOutputsStorage updated with pre_hatch outputs

  3. Execute hatch (to workspace.root/output)
     ├─ Resolve config.hatch.output using macros + pre_hatch outputs
     ├─ Validate: resolved output path is within workspace
     ├─ TemplateExpander(outputDirectory: workspace.root/resolvedOutput)
     └─ Template files expanded with macro/output substitution

  4. Execute post_hatch (in workspace.root)
     ├─ LifecycleStepRunner(workingDirectory: workspace.root)
     ├─ Shell commands run in workspace
     ├─ Any path escape attempt → StagingContext.Error.escapeAttempt
     └─ StepOutputsStorage updated with post_hatch outputs

  5. Partial apply (on success only)
     ├─ Drain workspace + workingDir watcher events
     ├─ Run targeted diffs for touched paths
     ├─ Flag overlapping paths as potential conflicts
     └─ Apply classified changes (add/update/delete) if user/flags allow

  On error at any step:
     └─ workspace.discard() → Remove all workspace contents

Output:
  └─ Final output directory path (in real workingDirectory)
```

---

## Working Directory Strategy

All phases execute in the same workspace directory:

| Phase | Working Directory | Description |
|-------|------------------|-------------|
| pre_hatch | `workspace.root` | Prepare environment, create files |
| hatch | `workspace.root` (output subpath) | Template expansion to specified output path |
| post_hatch | `workspace.root` | Operate on generated files (git init, etc.) |

**Environment Variables**:
```bash
STAGING_ROOT=/tmp/egg-workspace-xxx
EGG_ORIGINAL_WORKING_DIR=/Users/user/projects  # Read-only reference
```

---

## Apply Strategy

### Partial Apply Model

```
Timeline:
  t0: Staging created (clone of workingDirectory)
      └─ Watchers attached to workspace + workingDirectory
  t1: pre_hatch, hatch, post_hatch execute in workspace
      └─ Watchers record any touched files
  t2: Stage changes
      └─ Drain watcher sets, run per-path diffs only on touched files
      └─ Materialize adds/modifies/deletes inside applyStagingRoot
      └─ Conflicts checked: overlap between workspace + workingDirectory events
  t3: Apply staged diff
      └─ Transfer staged contents into workingDirectory (Deletes → Adds → Modifies)
```

### Why Partial Apply?

- **Safety**: Only changed files are touched
- **Concurrent modification detection**: User edits during hatch are detected
- **Minimal impact**: Unchanged files are never touched
- **Predictable**: User knows exactly what will change
- **Two-phase commit**: Staging ensures the real working directory is only touched after a dry-run of the file operations succeeds

### User Confirmation Before Apply

Before applying changes, the user must confirm the operation (unless `--force` is specified):

```
The following changes will be applied:

  Added (3 files):
    + MyProject/Package.swift
    + MyProject/Sources/main.swift
    + .egg-config

  Modified (1 file):
    ~ README.md

  Deleted (1 file):
    - old-config.txt

Apply these changes? [y/N]
```

**Behavior**:
- Default: Show diff summary and prompt for confirmation
- `--force`: Skip confirmation, apply immediately
- User enters `y` or `Y`: Apply changes
- User enters anything else: Abort, discard workspace

**Implementation**:
```swift
// In StagingWorkflowRunner
let changeSummary = try await workspace.computeChangeSummary(fileSystem: fileSystem)

if !force {
    displayChangeSummary(changeSummary, noora: noora)
    let confirmed = await noora.confirm("Apply these changes?")
    guard confirmed else {
        await workspace.discard(fileSystem: fileSystem)
        throw StagingContext.Error.userAborted
    }
}

// Apply changes (force parameter controls conflict handling)
let overriddenConflicts = try await workspace.applyChanges(fileSystem: fileSystem, force: force)

// Display warning for overridden conflicts
if !overriddenConflicts.isEmpty {
    noora.warning("Overwriting conflicting files:")
    for conflict in overriddenConflicts {
        noora.warning("  - \(conflict.path) (\(conflict.type.description))")
    }
}
```

### Performance Considerations

**Staging Clone (APFS Copy-on-Write)**:
- On macOS with APFS, directory cloning uses copy-on-write (CoW)
- Clone operation is **instant** regardless of directory size
- Disk space is only consumed for files that are actually modified
- Use `clonefile()` system call or `cp -c` for CoW copy

```swift
// Use APFS clone for instant copy
try fileSystem.copy(from: workingDirectory, to: workspace.root, usingClone: true)
```

**Watcher & Diff Cost**:
- FSEvents delivers only the paths that actually changed, so untouched trees (e.g., `node_modules`) are never scanned.
- Per-path diffs still read file contents, but the number of files is limited to the union of watcher results.

**Mitigation Strategies**:
1. Use APFS clone for workspace creation (instant)
2. Deduplicate watcher bursts to keep the target set small
3. Batch git diff calls so multiple paths are compared in a single process launch

### Git diff-based change detection

`git diff --no-index <baseline> <workspace>` runs Git の差分エンジンをディレクトリ同士に直接適用できる。StagingContext がこのコマンドを呼び出して `--raw` や `--name-status -z` の結果をパースすれば、Git の stat キャッシュ／rename 検出／巨大ファイル処理などをそのまま再利用可能。すでに Git 依存はあるため追加のライブラリ導入も不要で、`computeChangeSummary` / `applyChanges` は Git の出力をトリガにコピー・削除を行うだけで済む。libgit2 を組み込むより手軽に「Git と同じ方法」を実現できる。

---

## Error Handling

### Error Propagation

```
StagingContext.Error.escapeAttempt        ───┐
StagingContext.Error.conflictingFiles        │
ShellExecutionError                  ├──► StagingWorkflowRunner
UndefinedOutputReferenceError        │           │
ConditionEvaluationError             │           ▼
TemplateExpander.Error           ───┘    workspace.discard()
                                                │
                                                ▼
                                          throw error
```

### Cleanup Guarantee

```swift
func run(...) async throws -> AbsolutePath {
    let workspace = try await StagingContext.create(
        cloning: workingDirectory,
        fileSystem: fileSystem
    )

    do {
        try await executePreHatch(workspace: workspace, ...)
        let outputPath = try await executeHatch(workspace: workspace, ...)
        try await executePostHatch(workspace: workspace, ...)

        try await workspace.applyChanges(fileSystem: fileSystem)
        return outputPath

    } catch {
        await workspace.discard(fileSystem: fileSystem)
        throw error
    }
}
```

---

## File Organization

```
Sources/EggKit/
├── WorkflowRunner/
│   ├── Shared/
│   │   ├── WorkflowRunning.swift
│   │   ├── LifecycleStepRunner.swift
│   │   ├── ShellScriptRunner.swift
│   │   └── TemplateExpander.swift
│   ├── NonStaging/
│   │   └── LifecycleWorkflowRunner.swift
│   └── Staging/
│       ├── StagingWorkflowRunner.swift
│       ├── StagingContext.swift
│       ├── ApplyStagingArea.swift
│       ├── StagingError.swift
│       ├── WorkingDirectoryWatcher.swift
│       └── (supporting internals)
└── HatchRunner.swift                     (factory: staging vs legacy)
```

This separation keeps staging-specific logic isolated, retains the legacy runner in `NonStaging/`, and leaves reusable components accessible under `Shared/`.

---

## CLI Options

### `--no-staging`

Disables staging and uses legacy `LifecycleWorkflowRunner`:

- **Default**: staging enabled (new behavior)
- `--no-staging`: falls back to legacy behavior
- Emits warning: `⚠️ Running without staging; filesystem changes are permanent`

### `--force`

Skips user confirmation and overrides conflicts:

- **Default**: Show change summary, prompt for confirmation, error on conflicts
- `--force`: Apply immediately, override conflicts with warning

```bash
# Examples
$ egg hatch MyTemplate                              # staging ON, prompt before apply
$ egg hatch MyTemplate --force                      # staging ON, no prompt, override conflicts
$ egg hatch MyTemplate --no-staging # staging OFF (legacy behavior)

# Normal flow (without --force)
$ egg hatch MyTemplate
The following changes will be applied:

  Added (2 files):
    + MyProject/Package.swift
    + MyProject/Sources/main.swift

Apply these changes? [y/N] y
✓ Changes applied successfully

# With --force (no conflicts)
$ egg hatch MyTemplate --force
✓ Changes applied successfully

# Without --force, conflict causes error
$ egg hatch MyTemplate
Error: Conflicting changes detected:
  - Package.swift: modified both in workspace and working directory
Please resolve conflicts manually and retry.

# With --force, conflict causes warning but continues
$ egg hatch MyTemplate --force
⚠️ Overwriting conflicting files:
  - Package.swift (modified in both workspace and working directory)
✓ Changes applied successfully
```

---

## Edge Cases and Considerations

### 1. Output Directory Outside Staging

**Problem**: `config.hatch.output` resolves to path outside workspace (e.g., `../other-project`)

**Solution**: Validate resolved output path before hatch execution
```swift
let resolvedOutput = try resolveOutputPath(config.hatch.output, macros: macros, outputs: outputs)
let absoluteOutput = workspace.root.appending(resolvedOutput)
try workspace.validatePath(absoluteOutput)  // Throws if escape attempt
```

### 2. Shell Commands with Absolute Paths

**Problem**: Shell commands may reference absolute paths outside workspace

**Solution**:
- Set working directory to workspace.root
- Provide `$EGG_ORIGINAL_WORKING_DIR` for read-only reference
- Document that commands should use relative paths
- Advanced: Platform-specific workspace enforcement (future)

### 3. Large Working Directories

**Problem**: Cloning large directories is slow and disk-intensive

**Solution**:
- APFS clone (copy-on-write) on macOS for instant copies
- Consider `.gitignore`-aware cloning to skip unnecessary files
- Document: Requires ~1x working directory size during operation

### 4. Symlinks and Special Files

**Behavior**:
- Symlinks are copied as symlinks (not dereferenced)
- Device files and sockets are not supported (skipped with warning)

### 5. Empty Working Directory

**Behavior**:
- Staging created as empty directory
- All hatch output becomes "new files"
- Apply simply copies all new files

### 6. Conflict Resolution

**User Workflow**:
1. Hatch fails with conflict error
2. User reviews conflicting files
3. User manually resolves (keep their changes or discard)
4. User runs hatch again

---

## Design Decisions

### Why single workspace instead of staging/output split?

**Answer**:
- Matches user's mental model (working directory clone)
- Simpler to understand and implement
- All operations naturally stay within one boundary
- Partial apply handles all change types uniformly
- The apply staging area is lightweight and exists only for the final copy-back phase, so we still avoid maintaining two full execution workspacees

### Why watcher-driven diff instead of full rescans?

**Answer**:
- Touch-path capture means we only compare files that actually changed, keeping large repos fast.
- FSEvents surfaces concurrent user edits automatically, making conflict detection independent of timestamps.
- Eliminates reliance on expensive SHA hashing or mtime heuristics.
- Still compatible with `git diff --no-index`, which handles rename detection and large-file optimizations on the narrowed set.

### Why partial apply instead of full replacement?

**Answer**:
- Preserves user's concurrent modifications (when no conflict)
- Only applies what actually changed
- Safer and more predictable
- Standard approach in version control systems

### Why require user confirmation before apply?

**Answer**:
- User should see exactly what will change before it happens
- Prevents accidental overwrites or deletions
- Builds trust in the workspace system
- `--force` available for automation/scripting use cases

### Why does --force override conflicts with warning (not silently)?

**Answer**:
- `--force` means "apply without prompting" - consistent behavior
- Conflicts are rare (user editing same file during workspace execution)
- User explicitly chose `--force`, so they accept overwriting
- Warning ensures user is aware of what was overwritten (not silent)
- Enables CI/CD automation without manual intervention

### Why actor for StagingContext?

**Answer**:
- Thread-safe state management without locks
- Clear ownership model
- Idempotent discard is easy to implement
- Matches existing patterns in codebase (StepOutputsStorage)

---

## Example

### Input (config.yaml):

```yaml
pre_hatch:
  - id: setup
    run: |
      echo "version=1.0.0"
      echo "Creating config file..."
      echo "debug=true" > .egg-config

  - run: echo "Using version: ${{ pre_hatch.setup.outputs.version }}"

hatch:
  output: ./___PROJECT_NAME___

post_hatch:
  - run: |
      echo "Initializing git repository..."
      cd ./___PROJECT_NAME___
      git init
      echo "Project version: ${{ pre_hatch.setup.outputs.version }}"
```

### Execution (Staginged):

**Step 1: Create Staging**
```
Working Directory: /Users/user/projects/
Contains: README.md, existing-file.txt

Staging Created: /tmp/egg-workspace-abc123/
Contains: README.md, existing-file.txt (cloned)
Baseline Hashes: { README.md: abc..., existing-file.txt: def... }
```

**Step 2: Execute pre_hatch (in workspace)**
- Command 1: Creates `version=1.0.0` output, creates `.egg-config` file
- Command 2: Echoes version
- Staging now contains: `README.md`, `existing-file.txt`, `.egg-config`

**Step 3: Execute hatch (to workspace/MyProject/)**
- Validate: `./MyProject` is within workspace ✓
- Template expanded to `/tmp/egg-workspace-abc123/MyProject/`
- Staging now contains: `README.md`, `existing-file.txt`, `.egg-config`, `MyProject/`

**Step 4: Execute post_hatch (in workspace)**
- Git init runs in `workspace/MyProject/`
- `.git` directory created

**Step 5: Partial Apply**
```
Staging State:
  - README.md (unchanged)
  - existing-file.txt (unchanged)
  - .egg-config (NEW)
  - MyProject/ (NEW)
    - main.swift
    - Package.swift
    - .git/

Changes Applied to /Users/user/projects/:
  - .egg-config → ADDED
  - MyProject/ → ADDED (recursively)

Unchanged (not touched):
  - README.md
  - existing-file.txt
```

**Result**: `/Users/user/projects/` contains original files + new project

### Conflict Scenario:

```
Timeline:
  t0: Staging created, watchers attach
  t1: User edits README.md in working directory → working watcher records `README.md`
  t2: post_hatch modifies README.md in workspace → workspace watcher records `README.md`
  t3: Apply drains both watcher sets, union contains `README.md`
      - git diff on that path shows workspace intends to update the file
      - working watcher indicates concurrent change
      → Potential conflict surfaced to user

Error:
  StagingContext.Error.conflictingFiles([
    ConflictInfo(path: "README.md", type: .bothModified)
  ])
```

---

## Summary

| Feature | Description |
|---------|-------------|
| **Single workspace** | Clone of workingDirectory (APFS instant clone), all operations here |
| **Staging isolation** | Escape attempts detected and blocked |
| **Partial apply** | Only changed files applied via diff |
| **User confirmation** | Show changes and prompt before apply (skip with `--force`) |
| **Conflict handling** | Error by default; `--force` overrides with warning |
| **Automatic cleanup** | Staging discarded on any failure or user abort |
| **Watcher-driven diff** | Only touched paths are compared/applied |
| **Actor-based safety** | Thread-safe workspace management |

The architecture provides:
- Atomic all-or-nothing execution
- User visibility into all changes before they happen
- Safe handling of concurrent user modifications (conflict detection)
- `--force` for automation with warning on conflicts
- Predictable partial apply semantics
- Clean error recovery without manual cleanup
