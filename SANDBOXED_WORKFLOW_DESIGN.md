# Sandboxed Workflow Runner Design Document

## Overview

SandboxedWorkflowRunner is a system for executing the entire hatch lifecycle (pre_hatch → hatch → post_hatch) atomically in a sandboxed environment. All file system changes occur within a temporary sandbox directory (a clone of the working directory), and changes are applied to the real working directory only when all phases complete successfully.

## Problem Statement

### Current Behavior

```
┌──────────────────────────────────────────────────────────────────┐
│ LifecycleWorkflowRunner (Current)                                │
│                                                                  │
│   1. pre_hatch: Shell commands run in workingDirectory           │
│      └─ Changes are PERMANENT (not sandboxed)                    │
│                                                                  │
│   2. hatch: TemplateExpander uses withAtomicCopyAndWrite         │
│      └─ Changes are ATOMIC (sandboxed)                           │
│                                                                  │
│   3. post_hatch: Shell commands ALSO run in workingDirectory     │
│      └─ Changes are PERMANENT (not sandboxed)                    │
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
- Work should be done in a sandbox (clone of working directory)
- Only when ALL phases complete successfully should changes be applied
- If any phase fails, all file system changes should be discarded
- Changes are applied as partial diff, not full replacement

---

## Core Design Principles

1. **All-or-nothing execution**: Either the entire workflow succeeds, or no changes are made
2. **Sandbox = workingDirectory clone**: Single sandbox directory that mirrors the working directory
3. **Sandbox isolation**: All operations must stay within sandbox boundaries
4. **Partial apply**: Only changed files are applied back to working directory
5. **Conflict detection**: Detect concurrent modifications and fail safely
6. **Automatic cleanup**: Sandbox is discarded on failure, no manual cleanup needed

---

## Architecture

```
┌───────────────────────────────────────────────────────────────────────────┐
│ SandboxedWorkflowRunner (Top-level Orchestrator)                          │
│                                                                           │
│  run(config, macros, templateDirectory)                                   │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │ 1. Create Sandbox (clone of workingDirectory)                       │ │
│  │    └─ SandboxContext.create(cloning: workingDirectory)              │ │
│  │                                                                      │ │
│  │ 2. Execute pre_hatch in sandbox                                      │ │
│  │    └─ LifecycleStepRunner(workingDir: sandbox.root)                 │ │
│  │                                                                      │ │
│  │ 3. Execute hatch to sandbox                                          │ │
│  │    └─ TemplateExpander.expand(outputDir: sandbox.root/output)       │ │
│  │    └─ Validate: output path must be within sandbox                   │ │
│  │                                                                      │ │
│  │ 4. Execute post_hatch in sandbox                                     │ │
│  │    └─ LifecycleStepRunner(workingDir: sandbox.root)                 │ │
│  │                                                                      │ │
│  │ 5. Partial apply sandbox changes to workingDirectory                 │ │
│  │    └─ sandbox.applyChanges(to: workingDirectory)                    │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                           │
│  On any failure:                                                          │
│    └─ sandbox.discard() → Removes all sandbox contents                    │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## Component Design

### 1. SandboxContext (Actor)

**Responsibility**: Manages the lifecycle of a sandbox environment

**File**: `Sources/EggKit/WorkflowRunner/Internals/SandboxContext.swift`

**Interface**:
```swift
/// Manages a sandboxed environment for atomic workflow execution.
///
/// SandboxContext creates a temporary directory that is a clone of the working directory.
/// All workflow operations execute within this sandbox. Only when all operations complete
/// successfully are the changes applied back to the real working directory.
actor SandboxContext {
    /// The sandbox root directory (clone of workingDirectory).
    var root: AbsolutePath { get }

    /// The original working directory that was cloned.
    var originalWorkingDirectory: AbsolutePath { get }

    /// Snapshot of file hashes at sandbox creation time.
    /// Used for change detection during apply.
    private var baselineHashes: [RelativePath: String]

    /// Creates a new sandbox context by cloning the working directory.
    ///
    /// - Parameters:
    ///   - workingDirectory: The directory to clone into sandbox
    ///   - fileSystem: File system for operations
    /// - Returns: A new SandboxContext with cloned directory
    /// - Throws: SandboxError.creationFailed on file system errors
    static func create(
        cloning workingDirectory: AbsolutePath,
        fileSystem: any FileSysteming
    ) async throws -> SandboxContext

    /// Validates that a path is within sandbox boundaries.
    ///
    /// - Parameter path: Path to validate (can be relative or absolute)
    /// - Throws: SandboxError.escapeAttempt if path escapes sandbox
    func validatePath(_ path: AbsolutePath) throws

    /// Applies sandbox changes to the original working directory.
    ///
    /// Computes diff between sandbox and baseline, then applies:
    /// - New files: Added to working directory
    /// - Modified files: Updated in working directory
    /// - Deleted files: Removed from working directory
    ///
    /// - Parameters:
    ///   - fileSystem: File system for operations
    ///   - force: If true, override conflicts with warning. If false, throw error on conflicts.
    /// - Returns: List of conflicts that were overridden (empty if no conflicts or force=false)
    /// - Throws: SandboxError.conflictingFiles if conflicts detected and force=false
    func applyChanges(
        fileSystem: any FileSysteming,
        force: Bool
    ) async throws -> [ConflictInfo]

    /// Computes a summary of changes between sandbox and original working directory.
    ///
    /// Used to display changes to user before confirmation.
    /// - Returns: ChangeSummary with added, modified, and deleted files
    func computeChangeSummary(
        fileSystem: any FileSysteming
    ) async throws -> ChangeSummary

    /// Discards the sandbox without applying changes.
    ///
    /// Removes all sandbox contents. Safe to call multiple times (idempotent).
    func discard(fileSystem: any FileSysteming) async
}

/// Summary of changes to be applied from sandbox to working directory.
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
/tmp/egg-sandbox-XXXXXX/              (root = clone of workingDirectory)
├── (all contents from workingDirectory)
└── (hatch output created here, e.g., ./MyProject/)
```

**Key Characteristics**:
- Single sandbox directory (no staging/output split)
- Baseline hash snapshot taken at creation time
- All operations happen within sandbox.root
- Change detection via content hash comparison

**Design Rationale**:
- Actor ensures thread-safe access to sandbox state
- Content hashing enables accurate change detection
- Single sandbox simplifies mental model
- Idempotent discard allows safe cleanup in any error path

---

### 2. SandboxError

**Responsibility**: Define sandbox-specific errors

**File**: `Sources/EggKit/WorkflowRunner/Internals/SandboxError.swift`

**Interface**:
```swift
enum SandboxError: LocalizedError, Equatable {
    /// Attempted to use a sandbox that has already been discarded.
    case alreadyDiscarded

    /// Failed to create sandbox directory structure.
    case creationFailed(reason: String)

    /// Path attempted to escape sandbox boundaries.
    /// This can occur in pre_hatch, hatch output, or post_hatch.
    case escapeAttempt(path: String)

    /// Conflicting changes detected during apply.
    /// Contains list of conflicting relative paths and conflict type.
    case conflictingFiles([ConflictInfo])

    /// User declined to apply changes when prompted.
    case userAborted

    /// Failed to apply sandbox changes to destination.
    case applyFailed(reason: String)

    var errorDescription: String? { get }
}

struct ConflictInfo: Equatable {
    let path: RelativePath
    let type: ConflictType

    enum ConflictType: Equatable {
        /// File was modified in sandbox but also modified in working directory
        case bothModified
        /// File was deleted in sandbox but modified in working directory
        case deletedButModified
    }
}
```

---

### 3. Change Detection and Partial Apply

**Responsibility**: Detect changes and apply only the diff to working directory.

**File**: Logic lives inside `SandboxContext.applyChanges`

**Change Detection Algorithm (Dual FSEvents)**:

```
At sandbox creation:
  1. Clone workingDirectory → sandbox.root (APFS CoW)
  2. Attach FSEvents watcher to sandbox.root (records sandboxTouchedPaths)
  3. Attach FSEvents watcher to workingDirectory (records workingDirTouchedPaths)

During hatch execution:
  - All sandbox mutations automatically populate sandboxTouchedPaths
  - Any user edits in workingDirectory populate workingDirTouchedPaths

After post_hatch completes:
  1. Stop both watchers and snapshot the two path sets
  2. targetPaths = sandboxTouchedPaths ∪ workingDirTouchedPaths
  3. For each path in targetPaths:
        - Compare sandbox vs workingDirectory contents via git diff --no-index <sandbox/path> <working/path>
        - Classify as Added / Modified / Deleted based solely on sandbox result
        - If path ∈ workingDirTouchedPaths, mark as potential conflict
  4. Generate ChangeSummary + apply plan using this classified list only
```

**Conflict Matrix**:

| Sandbox | Working Dir Event | Result |
|---------|-------------------|--------|
| Added   | No                | Add |
| Added   | Yes               | Potential conflict (new file created both sides) |
| Modified| No                | Update |
| Modified| Yes               | Potential conflict |
| Deleted | No                | Delete |
| Deleted | Yes               | Potential conflict |

**Implementation**:
```swift
func applyChanges(fileSystem: any FileSysteming, force: Bool) async throws -> [ConflictInfo] {
    guard !isDiscarded else { throw SandboxError.alreadyDiscarded }

    // 1. Obtain watcher results
    let sandboxTouchedPaths = await sandboxWatcher.drainEvents()
    let workingDirTouchedPaths = await workingDirWatcher.drainEvents()
    let targetPaths = sandboxTouchedPaths.union(workingDirTouchedPaths)

    // 2. Classify sandbox changes via git diff --no-index (path-scoped)
    let changeEntries = try await diffPaths(targetPaths)

    // 3. Detect conflicts (event-based)
    var conflicts: [ConflictInfo] = []
    for entry in changeEntries where workingDirTouchedPaths.contains(entry.path) {
        conflicts.append(ConflictInfo(path: entry.path, type: .potentialOverlap))
    }

    // 4. Handle conflicts
    if !conflicts.isEmpty && !force {
        throw SandboxError.conflictingFiles(conflicts)
    }
    // If force=true, conflicts will be returned for warning display

    // 5. Apply changes
    // 4. Apply changes in targetPaths only (order: deletes → adds → modifies)
    try await applyChangeEntries(changeEntries, respectingConflicts: conflicts, force: force)

    // 6. Cleanup
    try await fileSystem.remove(root)
    isDiscarded = true

    return conflicts  // Return for warning display if force=true
}
```

---

### Dual Watchers for Targeted Diff

Both sandbox and original workingDirectory receive FSEvents watchers once cloning finishes. These watchers record only the relative paths that actually changed during the hatch run. Instead of hashing entire trees:

- `sandboxTouchedPaths` tells us exactly which files the workflow touched.
- `workingDirTouchedPaths` tells us which files the user or another process touched concurrently.
- The union determines which paths require diffing via `git diff --no-index`. Everything else is implicitly unchanged and skipped.

This dramatically reduces diff scope on large projects (e.g., `node_modules` stays untouched, so never diffed) while still surfacing “potential conflict” warnings whenever both sides touched the same path. `--force` continues to override but emits a warning that the file changed outside the sandbox.

### 4. Sandbox Escape Detection

**Responsibility**: Prevent operations from accessing paths outside the sandbox.

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
        throw SandboxError.escapeAttempt(path: path.pathString)
    }
}
```

2. **Environment Variables** (for shell scripts):
```bash
EGG_SANDBOX_ROOT=/tmp/egg-sandbox-xxx
EGG_ORIGINAL_WORKING_DIR=/Users/user/projects  # Read-only reference
```

3. **Working Directory Enforcement**:
- Shell scripts execute with `workingDirectory` set to sandbox.root
- Relative paths stay within sandbox
- Absolute paths outside sandbox will fail (no access)

**Note on Shell Escape Prevention**:
Full sandbox enforcement for shell scripts (preventing `cd ..` or absolute paths) requires platform-specific mechanisms:
- macOS: `sandbox-exec` with generated profile
- Linux: `landlock` or similar

For initial implementation, we rely on:
- Working directory set to sandbox
- Environment variables for reference
- Path validation for explicit outputs

Advanced escape prevention can be added as future enhancement.

---

### 5. SandboxedWorkflowRunner

**Responsibility**: Orchestrate the complete lifecycle workflow atomically within a sandbox

**File**: `Sources/EggKit/WorkflowRunner/SandboxedWorkflowRunner.swift`

**Interface**:
```swift
/// Orchestrates atomic lifecycle workflow execution in a sandboxed environment.
struct SandboxedWorkflowRunner: WorkflowRunning {
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
- Automatic cleanup in error path ensures no orphaned sandbox directories

---

## Data Flow

```
Input:
  ├─ config: Config (with pre_hatch, hatch, post_hatch definitions)
  ├─ macros: [ResolvedMacro]
  └─ templateDirectory: AbsolutePath

Flow:
  1. Create Sandbox (clone workingDirectory)
     ├─ SandboxContext.create(cloning: workingDirectory)
     ├─ Copy all files from workingDirectory to sandbox.root
     └─ Compute baseline hashes for all files

  2. Execute pre_hatch (in sandbox.root)
     ├─ LifecycleStepRunner(workingDirectory: sandbox.root)
     ├─ Shell commands run, outputs captured
     ├─ Any path escape attempt → SandboxError.escapeAttempt
     └─ StepOutputsStorage updated with pre_hatch outputs

  3. Execute hatch (to sandbox.root/output)
     ├─ Resolve config.hatch.output using macros + pre_hatch outputs
     ├─ Validate: resolved output path is within sandbox
     ├─ TemplateExpander(outputDirectory: sandbox.root/resolvedOutput)
     └─ Template files expanded with macro/output substitution

  4. Execute post_hatch (in sandbox.root)
     ├─ LifecycleStepRunner(workingDirectory: sandbox.root)
     ├─ Shell commands run in sandbox
     ├─ Any path escape attempt → SandboxError.escapeAttempt
     └─ StepOutputsStorage updated with post_hatch outputs

  5. Partial apply (on success only)
     ├─ Compute sandbox hashes
     ├─ Detect conflicts with current workingDirectory
     ├─ If conflicts → SandboxError.conflictingFiles
     └─ Apply diff: add new, update modified, delete removed

  On error at any step:
     └─ sandbox.discard() → Remove all sandbox contents

Output:
  └─ Final output directory path (in real workingDirectory)
```

---

## Working Directory Strategy

All phases execute in the same sandbox directory:

| Phase | Working Directory | Description |
|-------|------------------|-------------|
| pre_hatch | `sandbox.root` | Prepare environment, create files |
| hatch | `sandbox.root` (output subpath) | Template expansion to specified output path |
| post_hatch | `sandbox.root` | Operate on generated files (git init, etc.) |

**Environment Variables**:
```bash
EGG_SANDBOX_ROOT=/tmp/egg-sandbox-xxx
EGG_ORIGINAL_WORKING_DIR=/Users/user/projects  # Read-only reference
```

---

## Apply Strategy

### Partial Apply Model

```
Timeline:
  t0: Sandbox created (clone of workingDirectory)
      └─ baselineHashes computed
  t1: pre_hatch, hatch, post_hatch execute in sandbox
      └─ Files created, modified, deleted within sandbox
  t2: Apply changes
      └─ Diff computed: sandbox vs baseline
      └─ Conflicts checked: baseline vs current workingDirectory
      └─ Changes applied: only the diff
```

### Why Partial Apply?

- **Safety**: Only changed files are touched
- **Concurrent modification detection**: User edits during hatch are detected
- **Minimal impact**: Unchanged files are never touched
- **Predictable**: User knows exactly what will change

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
- User enters anything else: Abort, discard sandbox

**Implementation**:
```swift
// In SandboxedWorkflowRunner
let changeSummary = try await sandbox.computeChangeSummary(fileSystem: fileSystem)

if !force {
    displayChangeSummary(changeSummary, noora: noora)
    let confirmed = await noora.confirm("Apply these changes?")
    guard confirmed else {
        await sandbox.discard(fileSystem: fileSystem)
        throw SandboxError.userAborted
    }
}

// Apply changes (force parameter controls conflict handling)
let overriddenConflicts = try await sandbox.applyChanges(fileSystem: fileSystem, force: force)

// Display warning for overridden conflicts
if !overriddenConflicts.isEmpty {
    noora.warning("Overwriting conflicting files:")
    for conflict in overriddenConflicts {
        noora.warning("  - \(conflict.path) (\(conflict.type.description))")
    }
}
```

### Performance Considerations

**Sandbox Clone (APFS Copy-on-Write)**:
- On macOS with APFS, directory cloning uses copy-on-write (CoW)
- Clone operation is **instant** regardless of directory size
- Disk space is only consumed for files that are actually modified
- Use `clonefile()` system call or `cp -c` for CoW copy

```swift
// Use APFS clone for instant copy
try fileSystem.copy(from: workingDirectory, to: sandbox.root, usingClone: true)
```

**Hash Computation Cost**:
- SHA256 is O(file size)
- For large directories with many files, this can be expensive
- Optimization: Skip hashing for files with unchanged mtime

**Mitigation Strategies**:
1. Use APFS clone for sandbox creation (instant)
2. Use mtime as quick check before hashing
3. Parallelize hash computation for large directories

### Git diff-based change detection

`git diff --no-index <baseline> <sandbox>` runs Git の差分エンジンをディレクトリ同士に直接適用できる。SandboxContext がこのコマンドを呼び出して `--raw` や `--name-status -z` の結果をパースすれば、Git の stat キャッシュ／rename 検出／巨大ファイル処理などをそのまま再利用可能。すでに Git 依存はあるため追加のライブラリ導入も不要で、`computeChangeSummary` / `applyChanges` は Git の出力をトリガにコピー・削除を行うだけで済む。libgit2 を組み込むより手軽に「Git と同じ方法」を実現できる。

---

## Error Handling

### Error Propagation

```
SandboxError.escapeAttempt        ───┐
SandboxError.conflictingFiles        │
ShellExecutionError                  ├──► SandboxedWorkflowRunner
UndefinedOutputReferenceError        │           │
ConditionEvaluationError             │           ▼
TemplateExpander.Error           ───┘    sandbox.discard()
                                                │
                                                ▼
                                          throw error
```

### Cleanup Guarantee

```swift
func run(...) async throws -> AbsolutePath {
    let sandbox = try await SandboxContext.create(
        cloning: workingDirectory,
        fileSystem: fileSystem
    )

    do {
        try await executePreHatch(sandbox: sandbox, ...)
        let outputPath = try await executeHatch(sandbox: sandbox, ...)
        try await executePostHatch(sandbox: sandbox, ...)

        try await sandbox.applyChanges(fileSystem: fileSystem)
        return outputPath

    } catch {
        await sandbox.discard(fileSystem: fileSystem)
        throw error
    }
}
```

---

## File Organization

```
Sources/EggKit/
├── WorkflowRunner/
│   ├── SandboxedWorkflowRunner.swift     (NEW - main orchestrator)
│   ├── WorkflowRunning.swift             (NEW - protocol)
│   ├── LifecycleWorkflowRunner.swift     (existing - add protocol conformance)
│   ├── LifecycleStepRunner.swift         (existing - add env overrides)
│   ├── TemplateExpander.swift            (existing - no changes)
│   ├── ShellScriptRunner.swift           (existing - add environment param)
│   └── Internals/
│       ├── SandboxContext.swift          (NEW)
│       ├── SandboxError.swift            (NEW)
│       └── ... (existing internals)
└── HatchRunner.swift                     (update to use SandboxedWorkflowRunner)
```

---

## CLI Options

### `--no-sandbox`

Disables sandboxing and uses legacy `LifecycleWorkflowRunner`:

- **Default**: sandbox enabled (new behavior)
- `--no-sandbox`: falls back to legacy behavior
- Emits warning: `⚠️ Running without sandbox; filesystem changes are permanent`

### `--force`

Skips user confirmation and overrides conflicts:

- **Default**: Show change summary, prompt for confirmation, error on conflicts
- `--force`: Apply immediately, override conflicts with warning

```bash
# Examples
$ egg hatch MyTemplate                      # sandbox ON, prompt before apply
$ egg hatch MyTemplate --force              # sandbox ON, no prompt, override conflicts
$ egg hatch MyTemplate --no-sandbox         # sandbox OFF (legacy behavior)

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
  - Package.swift: modified both in sandbox and working directory
Please resolve conflicts manually and retry.

# With --force, conflict causes warning but continues
$ egg hatch MyTemplate --force
⚠️ Overwriting conflicting files:
  - Package.swift (modified in both sandbox and working directory)
✓ Changes applied successfully
```

---

## Edge Cases and Considerations

### 1. Output Directory Outside Sandbox

**Problem**: `config.hatch.output` resolves to path outside sandbox (e.g., `../other-project`)

**Solution**: Validate resolved output path before hatch execution
```swift
let resolvedOutput = try resolveOutputPath(config.hatch.output, macros: macros, outputs: outputs)
let absoluteOutput = sandbox.root.appending(resolvedOutput)
try sandbox.validatePath(absoluteOutput)  // Throws if escape attempt
```

### 2. Shell Commands with Absolute Paths

**Problem**: Shell commands may reference absolute paths outside sandbox

**Solution**:
- Set working directory to sandbox.root
- Provide `$EGG_ORIGINAL_WORKING_DIR` for read-only reference
- Document that commands should use relative paths
- Advanced: Platform-specific sandbox enforcement (future)

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
- Sandbox created as empty directory
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

### Why single sandbox instead of staging/output split?

**Answer**:
- Matches user's mental model (working directory clone)
- Simpler to understand and implement
- All operations naturally stay within one boundary
- Partial apply handles all change types uniformly

### Why content hashing instead of mtime?

**Answer**:
- Accurate change detection regardless of timestamps
- Handles edge cases (file touched but not changed)
- Required for proper conflict detection
- Can optimize with mtime as quick pre-check

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
- Builds trust in the sandbox system
- `--force` available for automation/scripting use cases

### Why does --force override conflicts with warning (not silently)?

**Answer**:
- `--force` means "apply without prompting" - consistent behavior
- Conflicts are rare (user editing same file during sandbox execution)
- User explicitly chose `--force`, so they accept overwriting
- Warning ensures user is aware of what was overwritten (not silent)
- Enables CI/CD automation without manual intervention

### Why actor for SandboxContext?

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

### Execution (Sandboxed):

**Step 1: Create Sandbox**
```
Working Directory: /Users/user/projects/
Contains: README.md, existing-file.txt

Sandbox Created: /tmp/egg-sandbox-abc123/
Contains: README.md, existing-file.txt (cloned)
Baseline Hashes: { README.md: abc..., existing-file.txt: def... }
```

**Step 2: Execute pre_hatch (in sandbox)**
- Command 1: Creates `version=1.0.0` output, creates `.egg-config` file
- Command 2: Echoes version
- Sandbox now contains: `README.md`, `existing-file.txt`, `.egg-config`

**Step 3: Execute hatch (to sandbox/MyProject/)**
- Validate: `./MyProject` is within sandbox ✓
- Template expanded to `/tmp/egg-sandbox-abc123/MyProject/`
- Sandbox now contains: `README.md`, `existing-file.txt`, `.egg-config`, `MyProject/`

**Step 4: Execute post_hatch (in sandbox)**
- Git init runs in `sandbox/MyProject/`
- `.git` directory created

**Step 5: Partial Apply**
```
Sandbox State:
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
  t0: Sandbox created, baseline has README.md (hash: abc)
  t1: User edits README.md in working directory (hash: xyz)
  t2: post_hatch modifies README.md in sandbox (hash: 123)
  t3: Apply detects conflict:
      - Sandbox hash (123) != Baseline hash (abc) → Modified in sandbox
      - Current hash (xyz) != Baseline hash (abc) → Modified in working dir
      → CONFLICT: bothModified

Error:
  SandboxError.conflictingFiles([
    ConflictInfo(path: "README.md", type: .bothModified)
  ])
```

---

## Summary

| Feature | Description |
|---------|-------------|
| **Single sandbox** | Clone of workingDirectory (APFS instant clone), all operations here |
| **Sandbox isolation** | Escape attempts detected and blocked |
| **Partial apply** | Only changed files applied via diff |
| **User confirmation** | Show changes and prompt before apply (skip with `--force`) |
| **Conflict handling** | Error by default; `--force` overrides with warning |
| **Automatic cleanup** | Sandbox discarded on any failure or user abort |
| **Content hashing** | Accurate change detection |
| **Actor-based safety** | Thread-safe sandbox management |

The architecture provides:
- Atomic all-or-nothing execution
- User visibility into all changes before they happen
- Safe handling of concurrent user modifications (conflict detection)
- `--force` for automation with warning on conflicts
- Predictable partial apply semantics
- Clean error recovery without manual cleanup
