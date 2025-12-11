# Transactional Workflow Runner Implementation Plan

## Overview

This document outlines the implementation plan for `TransactionalWorkflowRunner`, providing atomic all-or-nothing execution of the hatch lifecycle by running all operations in a transactional workspace (clone of working directory) with partial apply on success.

**Reference Documents:**
- [SANDBOXED_WORKFLOW_DESIGN.md](./SANDBOXED_WORKFLOW_DESIGN.md) - Complete design specification
- [LIFECYCLE_STEP_RUNNER_IMPLEMENTATION_PLAN.md](./LIFECYCLE_STEP_RUNNER_IMPLEMENTATION_PLAN.md) - Reference for implementation style

---

## Prerequisites

Before starting implementation:
- [ ] Review SANDBOXED_WORKFLOW_DESIGN.md in full
- [ ] Understand existing `LifecycleWorkflowRunner` implementation
- [ ] Understand `StepOutputsStorage` actor pattern (reference for TransactionalContext)
- [ ] Understand FileSysteming protocol (APFS clone, path validation, etc.)

---

## Phase 1: Foundation Layer (TransactionalContext + Nested Errors)

> Directory layout note: transactional-specific sources live under `Sources/EggKit/WorkflowRunner/Transactional/`, legacy runner under `WorkflowRunner/NonTransactional/`, and shared utilities under `WorkflowRunner/Shared/`. Tests mirror the same structure beneath `Tests/EggKitTests/WorkflowRunner/`.

**Goal:** Create the core transactional workspace management components.

### 1.1 Create TransactionalContext.Error

**Files:**
- `Sources/EggKit/WorkflowRunner/Transactional/TransactionalError.swift`
- `Sources/EggKit/WorkflowRunner/Transactional/ConflictInfo.swift`
- `Sources/EggKit/WorkflowRunner/Transactional/ChangeSummary.swift`

```swift
extension TransactionalContext {
enum Error: LocalizedError, Equatable {
    case alreadyDiscarded
    case creationFailed(reason: String)
    case escapeAttempt(path: String)
    case conflictingFiles([ConflictInfo])
    case userAborted  // User declined to apply changes
    case applyFailed(reason: String)
}

struct ConflictInfo: Equatable {
    let path: RelativePath
    let type: ConflictType

    enum ConflictType: Equatable {
        case bothModified
        case deletedButModified
    }
}

struct ChangeSummary {
    let added: [RelativePath]
    let modified: [RelativePath]
    let deleted: [RelativePath]
    var isEmpty: Bool { added.isEmpty && modified.isEmpty && deleted.isEmpty }
}
}
```

**Checklist:**
- [x] Create file with nested enum definition
- [x] Implement `LocalizedError` conformance with user-friendly messages
- [x] Add `Equatable` conformance for testing
- [x] Test: Error equality and description formatting

### 1.2 Create TransactionalContext Actor

**File:** `Sources/EggKit/WorkflowRunner/Transactional/TransactionalContext.swift`

**Implementation Order:**

1. **Basic structure:**
```swift
static func create(
    cloning workingDirectory: AbsolutePath,
    fileSystem: any FileSysteming
) async throws -> TransactionalContext
```
- Create temp directory with prefix `egg-workspace-`
- Use APFS clone (`clonefile()`) for instant copy-on-write copy
- Start workspace + working-directory watchers immediately after cloning so that change tracking is watcher-driven from the very beginning
- Handle symlinks (copy as symlinks)
- Skip device files/sockets with warning

2. **Path validation:**
```swift
func validatePath(_ path: AbsolutePath) throws {
    let normalized = path.lexicallyNormalized()
    guard normalized.isDescendant(of: root) else {
        throw TransactionalContext.Error.escapeAttempt(path: path.pathString)
    }
}
```

3. **Discard method:**
```swift
func discard(fileSystem: any FileSysteming) async {
    guard !isDiscarded else { return }  // Idempotent
    try? await fileSystem.remove(root)
    isDiscarded = true
}
```

4. **Apply changes (Phase 2)**
   - Delegated to the path-targeted diff approach described later.

**Checklist:**
- [x] Create actor skeleton with properties
- [x] Implement `create()` with APFS clone (clonefile)
- [x] Implement watcher wiring + lifecycle hooks
- [x] Implement `validatePath()`
- [x] Implement `computeChangeSummary()` (leveraging path-targeted diffs)
- [x] Implement `applyChanges(force:)` (returns [ConflictInfo])
- [x] Implement `discard()`
- [x] Tests: Creation, path validation, change summary, apply with/without force, discard idempotency

---

## Phase 2: Partial Apply Implementation

**Goal:** Implement the change detection and partial apply logic.

### 2.1 Dual watcher infrastructure

**Goal:** Capture touched paths in both transactional workspace and working directory without scanning entire trees.

Steps:
1. Implement `WorkingDirectoryWatcher` abstraction (FSEvents on macOS) with `start()`, `stop()`, `drainEvents()` returning `Set<RelativePath>`. Because this feature targets macOS only, no cross-platform fallback is required.
2. Instantiate one watcher pointing at `workspace.root`, another at `originalWorkingDirectory`.
3. Normalize events:
   - Convert to relative paths (relative to respective roots)
   - Expand directory events to include descendants (e.g., rename)
   - Deduplicate thrashing (coalesce identical paths)
4. Ensure watchers survive the entire hatch run and stop deterministically before apply/discard.

**Checklist:**
- [x] Implement macOS FSEvents-backed watcher
- [x] Provide no-op mock for tests / unsupported platforms
- [x] Add unit tests simulating create/delete/modify/rename bursts

### 2.2 Apply Changes Method (path-targeted)

**Implementation Steps:**

1. **Guard discarded state**
2. **Drain watcher events**:
   - `workspaceTouched = workspaceWatcher.drainEvents()`
   - `workingTouched = workingWatcher.drainEvents()`
   - `targetPaths = workspaceTouched union workingTouched`
3. **Run git diff per target path (batched)**:
   - Invoke `git diff --no-index --name-status -z` restricted to `targetPaths`
   - Parse results into `ChangeEntry { path, kind (add/modify/delete) }`
4. **Conflict detection**:
   - If `path` is in `workingTouched`, emit `ConflictInfo(type: .potentialOverlap)`
5. **Handle conflicts**:
   - `isInteractive && !force`: display conflicts via Noora, prompt `Override these files?`; abort on negative response
   - `!isInteractive && !force`: throw `TransactionalContext.Error.conflictingFiles`
   - `force=true`: proceed but record conflicts for warning output
6. **Apply changes (targeted + staged)**:
   - For each path in `ChangeEntry`, materialize the new/removed state inside a temporary `applyStaging` directory located under the workspace root.
   - Once staging succeeds, perform filesystem updates against the real working directory in the order Deletes -> Adds -> Modifies. Each step tracks success so that, if an error surfaces mid-apply, the runner can revert to the previous state by replaying the inverse operations from staging (or simply abort before touching the working tree when staging fails).
   - Applying only after staging completes ensures no partial updates remain even when an exception interrupts the operation.
7. **Cleanup:** Remove workspace directory and staging artifacts, stop watchers, set `isDiscarded = true`
8. **Return:** Conflicts list

**Checklist:**
- [x] Implement watcher draining + union logic
- [x] Implement git diff wrapper that accepts explicit path list
- [x] Implement conflict detection based on workingTouched
- [x] Implement targeted apply (create parents, handle deletes)
- [x] Tests: new/modified/deleted path subsets, conflict detection, force override

#### ApplyStagingArea helper

Create a dedicated helper type (struct or class) responsible for managing the temporary staging directory and the metadata required for rollback.

- **Responsibilities**:
  - Create `applyStagingRoot` via `FileSystem.makeTemporaryDirectory` (typically `/tmp/egg-apply-staging-XXXX`). Keeping staging outside the workspace avoids surprise interactions with user files and ensures cleanup is trivial even if the workspace is removed mid-run.
  - Mirror the change plan (adds/modifies/deletes) inside the staging root, including permissions and file contents.
  - Return a manifest describing which filesystem actions must be applied to the real working directory, plus the inverse operations in case rollback is required mid-flight. The caller retains this manifest so orchestration state never lives inside `ApplyStagingArea`.
  - Provide APIs:
    - `stage(changes: ChangeSummary, sourceRoot: AbsolutePath, fileSystem: FileSysteming)`
    - `apply(to workingDirectory: AbsolutePath)` which streams staged content to disk
    - `cleanup()` that tears down staging regardless of success/failure.
- **Error handling**:
  - If staging fails, abort before touching the real working directory and surface the error.
  - If applying fails halfway, use the inverse manifest to undo any writes already performed (or leave the working directory untouched when failure occurs prior to starting).
  - Scope staging-specific failures to `ApplyStagingArea.Error` (nested enum) so that callers only need to reason about workspace-level errors (`TransactionalContext.Error`) vs. staging internals. The valid cases focus on rollback failures and missing staged artifacts; high-level lifecycle state is tracked by `TransactionalContext`.
- **Extra considerations**:
  - Validate available disk space before staging large trees (compare `du` of change set vs. free space).
  - Normalize ownership/permissions so staged artifacts exactly match the workspace equivalents.
  - Ensure staging paths are hidden from user templates to avoid accidental interactions (prefix with `.`).
- **Tests**:
  - Successful staging/apply for add/modify/delete combinations.
  - Simulated failure during staging (e.g., permission error) leaves working directory unchanged.
  - Simulated failure mid-apply triggers rollback and reports error.

### 2.3 Git diff --no-index integration (optional fast path)

`git diff --no-index` can now be invoked with a narrowed list of `targetPaths`. Implementation notes:

1. **Batch diff**: call `git diff --no-index --name-status -z workspace/path working/path ...` once, enumerating pairs via arguments.
2. **Rename detection**: when Git outputs `Rxxx`, treat it as a delete+add so downstream logic stays simple.
3. **Ignore unchanged paths**: if Git reports "no differences" for a path, skip it from the apply set.

**Checklist:**
- [x] Git diff wrapper that accepts N path pairs
- [x] Parser converting `A/M/D/R` into `ChangeEntry`
- [x] Tests with recorded git output fixtures


---

## Phase 3: Protocol and Existing Component Updates

**Goal:** Create WorkflowRunning protocol and update existing components for transactional workspace support.

### 3.1 Create WorkflowRunning Protocol

**File:** `Sources/EggKit/WorkflowRunner/Shared/WorkflowRunning.swift`

```swift
/// Protocol for workflow runners that execute the hatch lifecycle.
protocol WorkflowRunning {
    func run(
        config: Config,
        macros: [ResolvedMacro],
        templateDirectory: AbsolutePath
    ) async throws -> AbsolutePath
}
```

**Checklist:**
- [x] Create protocol file
- [x] Add conformance to `LifecycleWorkflowRunner`
- [x] Verify existing tests still pass

### 3.2 Update ShellScriptRunner

**File:** `Sources/EggKit/WorkflowRunner/ShellScriptRunner.swift`

**Changes:**
- Add optional `additionalEnvironment: [String: String]` parameter to `init()`
- Merge with existing environment using `Subprocess.Environment.inherit.updating()`

```swift
init(
    processRunner: any ProcessRunning,
    workingDirectory: AbsolutePath,
    additionalEnvironment: [String: String] = [:]
)
```

**Checklist:**
- [x] Add `additionalEnvironment` parameter
- [x] Merge environment variables in process execution
- [x] Update existing call sites (if any)
- [x] Tests: Environment variable merging

### 3.3 Update LifecycleStepRunner

**File:** `Sources/EggKit/WorkflowRunner/LifecycleStepRunner.swift`

**Changes:**
- Accept optional `additionalEnvironment: [String: String]` in initializer
- Pass to ShellScriptRunner

```swift
init(
    // ... existing params ...
    additionalEnvironment: [String: String] = [:]
)
```

**Checklist:**
- [x] Add `additionalEnvironment` property
- [x] Pass to ShellScriptRunner.run()
- [x] Tests: Environment variable propagation

---

## Phase 4: TransactionalWorkflowRunner Implementation

**Goal:** Create the main orchestrator that ties everything together.

### 4.1 Create TransactionalWorkflowRunner

**File:** `Sources/EggKit/WorkflowRunner/Transactional/TransactionalWorkflowRunner.swift`

**Structure:**

```swift
struct TransactionalWorkflowRunner: WorkflowRunning {
    private let processRunner: any ProcessRunning
    private let fileSystem: any FileSysteming
    private let workingDirectory: AbsolutePath
    private let homeDirectory: AbsolutePath
    private let noora: any Noorable
    private let isInteractive: Bool
    private let force: Bool  // Skip user confirmation

    func run(
        config: Config,
        macros: [ResolvedMacro],
        templateDirectory: AbsolutePath
    ) async throws -> AbsolutePath
}
```

**Implementation Order:**

1. **Transactional Workspace creation:**
```swift
let workspace = try await TransactionalContext.create(
    cloning: workingDirectory,
    fileSystem: fileSystem
)
```

2. **Environment variables:**
```swift
let workspaceEnv = [
    "EGG_WORKSPACE_ROOT": workspace.root.pathString,
    "EGG_ORIGINAL_WORKING_DIR": workingDirectory.pathString
]
```

3. **Execute pre_hatch:**
```swift
let preHatchRunner = LifecycleStepRunner(
    // ... existing params ...
    workingDirectory: workspace.root,
    additionalEnvironment: workspaceEnv
)
```

4. **Validate and execute hatch:**
```swift
// Resolve output path
let resolvedOutput = try resolveOutputPath(...)
let absoluteOutput = workspace.root.appending(resolvedOutput)

// Validate within workspace
try workspace.validatePath(absoluteOutput)

// Expand templates
let expander = TemplateExpander(...)
try await expander.expand(to: absoluteOutput, ...)
```

5. **Execute post_hatch:**
```swift
let postHatchRunner = LifecycleStepRunner(
    // ... existing params ...
    workingDirectory: workspace.root,
    additionalEnvironment: workspaceEnv
)
```

6. **User confirmation (unless force=true):**
```swift
let changeSummary = try await workspace.computeChangeSummary(fileSystem: fileSystem)

if !force {
    // Display change summary to user
    displayChangeSummary(changeSummary, noora: noora)

    // Prompt for confirmation
    let confirmed = await noora.confirm("Apply these changes?")
    guard confirmed else {
        await workspace.discard(fileSystem: fileSystem)
        throw TransactionalContext.Error.userAborted
    }
}
```

7. **Stage + apply changes and display conflict warnings:**
```swift
// Phase 1: build the staged diff. This touches only applyStagingRoot.
let staging = try await workspace.stageChanges(fileSystem: fileSystem, force: force)

// Phase 2: push staged changes into the working directory (Deletes -> Adds -> Modifies)
let overriddenConflicts = try await staging.apply(to: workingDirectory)

// Display warning for overridden conflicts (only when force=true)
if !overriddenConflicts.isEmpty {
    noora.warning("Overwriting conflicting files:")
    for conflict in overriddenConflicts {
        noora.warning("  - \(conflict.path) (\(conflict.type.description))")
    }
}

// Return path in real workingDirectory
return workingDirectory.appending(resolvedOutput)
```

8. **Error handling:**
```swift
do {
    // ... all operations ...
} catch {
    await workspace.discard(fileSystem: fileSystem)
    throw error
}
```

**Checklist:**
- [x] Create basic structure with dependencies (including `force` parameter)
- [x] Implement workspace creation
- [x] Implement pre_hatch execution with environment
- [x] Implement output path validation
- [x] Implement hatch execution
- [x] Implement post_hatch execution
- [x] Implement change summary display (helper function)
- [x] Implement user confirmation prompt (using Noora)
- [x] Implement stage/apply pipeline with force-aware conflict handling
- [x] Implement conflict warning display (when force=true)
- [x] Implement discard on failure or user abort
- [x] Tests: Full workflow, user confirmation, user abort, force mode, conflict override

---

## Phase 5: CLI Integration

**Goal:** Integrate TransactionalWorkflowRunner into HatchRunner with `--no-transactional-workspace` and `--force` options.

### 5.1 Update HatchRunner

**File:** `Sources/EggKit/HatchRunner.swift`

**Changes:**

1. **Add useTransactionalWorkspace and force parameters:**
```swift
init(
    // ... existing params ...
    useTransactionalWorkspace: Bool = true,
    force: Bool = false
)
```

2. **Factory pattern for runner selection:**
```swift
private func makeWorkflowRunner() -> any WorkflowRunning {
    if useTransactionalWorkspace {
        return TransactionalWorkflowRunner(
            processRunner: processRunner,
            fileSystem: fileSystem,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            noora: noora,
            isInteractive: isInteractive,
            force: force
        )
    } else {
        noora.warning("Running without transactional workspace; filesystem changes are permanent")
        return LifecycleWorkflowRunner(...)
    }
}
```

**Checklist:**
- [x] Add `useTransactionalWorkspace` and `force` parameters to HatchRunner
- [x] Implement runner factory method
- [x] Pass `force` to TransactionalWorkflowRunner
- [x] Add warning for no-transactional-workspace mode
- [x] Tests: Runner selection, force mode behavior

### 5.2 Update CLI Hatch Command

**File:** `Sources/EggCLI/Commands/HatchCommand.swift`

**Changes:**
```swift
@Flag(name: .long, help: "Disable transactional workspace (filesystem changes are permanent)")
var noTransactionalWorkspace: Bool = false

@Flag(name: .long, help: "Skip confirmation and override conflicts with warning")
var force: Bool = false
```

Pass to HatchRunner:
```swift
let runner = HatchRunner(
    // ... existing params ...
    useTransactionalWorkspace: !noTransactionalWorkspace,
    force: force
)
```

**Checklist:**
- [x] Add `--no-transactional-workspace` flag
- [x] Add `--force` flag
- [x] Pass both flag values to HatchRunner
- [x] Update help text for both flags
- [x] Integration test: transactional workspace + no-transactional-workspace + force combinations

---

## Phase 6: Testing and Polish

**Goal:** Comprehensive testing and documentation.

### 6.1 Unit Tests

**New Test Files:**
- `Tests/EggKitTests/WorkflowRunner/TransactionalContextTests.swift`
- `Tests/EggKitTests/WorkflowRunner/TransactionalWorkflowRunnerTests.swift`

**Test Categories:**

1. **TransactionalContext Tests:**
   - [ ] Creation clones all files
   - [ ] Baseline hashes computed correctly
   - [ ] Path validation: valid paths
   - [ ] Path validation: escape attempts
   - [ ] Discard is idempotent
   - [ ] Apply: new files added
   - [ ] Apply: modified files updated
   - [ ] Apply: deleted files removed
   - [ ] Apply: unchanged files not touched
   - [ ] Apply: conflict detection (bothModified)
   - [ ] Apply: conflict detection (deletedButModified)
   - [ ] Apply: empty working directory

2. **TransactionalWorkflowRunner Tests:**
   - [ ] Full workflow success (with user confirmation)
   - [ ] Force mode skips confirmation
   - [ ] User abort discards workspace
   - [ ] Conflict without force throws error
   - [ ] Conflict with force overrides and shows warning
   - [ ] Pre-hatch failure discards workspace
   - [ ] Hatch failure discards workspace
   - [ ] Post-hatch failure discards workspace
   - [ ] Output path escape throws error
   - [ ] Environment variables set correctly

3. **Integration Tests:**
   - [ ] End-to-end with real filesystem (user confirms)
   - [ ] --force flag skips confirmation
   - [ ] --no-transactional-workspace flag works
   - [ ] APFS clone performance (instant for large directories)
   - [ ] Symlink handling

### 6.2 Documentation Updates

- [ ] Update README with workspace feature
- [ ] Document --no-transactional-workspace flag
- [ ] Document conflict resolution workflow
- [ ] Add examples of workspace behavior

### 6.3 Error Messages

- [ ] Clear conflict error messages with file paths
- [ ] Escape attempt error shows problematic path
- [ ] Creation failure shows underlying reason

---

## Implementation Order Summary

| Phase | Components | Dependencies | Estimated Complexity |
|-------|------------|--------------|---------------------|
| 1 | TransactionalContext.Error, TransactionalContext (basic) | FileSysteming | Medium |
| 2 | Hash computation, Apply changes | Phase 1 | High |
| 3 | WorkflowRunning protocol, Updates | Existing code | Low |
| 4 | TransactionalWorkflowRunner | Phases 1-3 | High |
| 5 | CLI integration | Phase 4 | Low |
| 6 | Testing, documentation | Phases 1-5 | Medium |

**Recommended Implementation Strategy:**
1. Phases 1-2 first (core workspace logic)
2. Phase 3 in parallel with testing Phase 1-2
3. Phase 4 after Phases 1-3 complete
4. Phases 5-6 last

---

## Success Criteria

### Functional Requirements

- [ ] Transactional Workspace clones working directory instantly (APFS clone)
- [ ] All phases execute within workspace
- [ ] Escape attempts are detected and blocked
- [ ] Change summary displayed before apply
- [ ] User confirmation required (unless --force)
- [ ] Partial apply only changes modified files
- [ ] Conflicts detected with clear error messages
- [ ] Transactional Workspace discarded on failure or user abort
- [ ] --no-transactional-workspace falls back to legacy behavior
- [ ] --force skips confirmation and overrides conflicts with warning

### Non-Functional Requirements

- [ ] APFS clone is instant (regardless of directory size)
- [ ] Hash computation is reasonably fast
- [ ] Memory usage stays bounded
- [ ] No orphaned workspace directories on crash

### Test Coverage

- [ ] All `TransactionalContext.Error` cases covered (including userAborted)
- [ ] TransactionalContext: creation, validation, change summary, apply, discard
- [ ] TransactionalWorkflowRunner: success, user confirmation, user abort, force mode
- [ ] CLI integration: --no-transactional-workspace, --force, combined flags

---

## Risk Areas and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Non-APFS filesystem | Clone is slow | Document APFS requirement, fallback to regular copy |
| Hash computation slow | Performance | Use mtime as pre-check optimization |
| Symlink edge cases | Correctness | Test extensively, document behavior |
| Concurrent file access | Race conditions | Actor isolation, clear locking |
| --force data loss | User surprise | Warning message on conflict override (not silent) |

---

## Dependencies

### New Dependencies

None required - using:
- CryptoKit (system framework for SHA256)
- Foundation (file operations)

### Existing Dependencies Used

- `FileSysteming` protocol
- `ProcessRunning` protocol
- `LifecycleStepRunner`
- `TemplateExpander`
- `StepOutputsStorage` (pattern reference for actors)

---

## File Changes Summary

### New Files

| File | Description |
|------|-------------|
| `WorkflowRunner/Transactional/TransactionalError.swift` | Nested error types for transactional workspace operations |
| `WorkflowRunner/Transactional/TransactionalContext.swift` | Actor managing transactional workspace lifecycle |
| `WorkflowRunner/Transactional/TransactionalWorkflowRunner.swift` | Main orchestrator |
| `WorkflowRunner/Transactional/ApplyStagingArea.swift` | Helper managing staged diff + rollback |
| `WorkflowRunner/Transactional/WorkingDirectoryWatcher.swift` | Dual FSEvents implementation |
| `WorkflowRunner/Shared/WorkflowRunning.swift` | Protocol for workflow runners |
| `Tests/EggKitTests/WorkflowRunner/Transactional/TransactionalContextTests.swift` | Unit tests for TransactionalContext |
| `Tests/EggKitTests/WorkflowRunner/Transactional/TransactionalWorkflowRunnerTests.swift` | Unit tests for runner |
| `Tests/EggKitTests/WorkflowRunner/Transactional/ApplyStagingAreaTests.swift` | Unit tests for staging helper |

### Modified Files

| File | Changes |
|------|---------|
| `WorkflowRunner/NonTransactional/LifecycleWorkflowRunner.swift` | Add WorkflowRunning conformance |
| `WorkflowRunner/Shared/LifecycleStepRunner.swift` | Add additionalEnvironment parameter |
| `WorkflowRunner/Shared/ShellScriptRunner.swift` | Add additionalEnvironment parameter |
| `HatchRunner.swift` | Add useTransactionalWorkspace and force parameters, runner factory |
| `EggCLI/Commands/HatchCommand.swift` | Add --no-transactional-workspace and --force flags |

---

## Notes

- Start with Phase 1-2 to establish core workspace mechanics
- Test extensively before integrating with workflow
- Actor pattern from StepOutputsStorage is good reference
- APFS clone makes directory size irrelevant (instant copy-on-write)
- User confirmation is default; `--force` for automation/scripts
- `--force` overrides conflicts with warning (not silent)
- Consider mtime optimization for hash computation as follow-up
