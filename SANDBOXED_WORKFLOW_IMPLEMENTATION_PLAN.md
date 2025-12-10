# Sandboxed Workflow Runner Implementation Plan

## Overview

This document outlines the implementation plan for `SandboxedWorkflowRunner`, providing atomic all-or-nothing execution of the hatch lifecycle by running all operations in a sandbox (clone of working directory) with partial apply on success.

**Reference Documents:**
- [SANDBOXED_WORKFLOW_DESIGN.md](./SANDBOXED_WORKFLOW_DESIGN.md) - Complete design specification
- [LIFECYCLE_STEP_RUNNER_IMPLEMENTATION_PLAN.md](./LIFECYCLE_STEP_RUNNER_IMPLEMENTATION_PLAN.md) - Reference for implementation style

---

## Prerequisites

Before starting implementation:
- [ ] Review SANDBOXED_WORKFLOW_DESIGN.md in full
- [ ] Understand existing `LifecycleWorkflowRunner` implementation
- [ ] Understand `StepOutputsStorage` actor pattern (reference for SandboxContext)
- [ ] Understand FileSysteming protocol and hash computation methods

---

## Phase 1: Foundation Layer (SandboxContext + SandboxError)

**Goal:** Create the core sandbox management components.

### 1.1 Create SandboxError

**File:** `Sources/EggKit/WorkflowRunner/Internals/SandboxError.swift`

```swift
enum SandboxError: LocalizedError, Equatable {
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
```

**Checklist:**
- [ ] Create file with enum definition
- [ ] Implement `LocalizedError` conformance with user-friendly messages
- [ ] Add `Equatable` conformance for testing
- [ ] Test: Error equality and description formatting

### 1.2 Create SandboxContext Actor

**File:** `Sources/EggKit/WorkflowRunner/Internals/SandboxContext.swift`

**Implementation Order:**

1. **Basic structure:**
```swift
actor SandboxContext {
    let root: AbsolutePath
    let originalWorkingDirectory: AbsolutePath
    private var baselineHashes: [RelativePath: String]
    private var isDiscarded: Bool = false
}
```

2. **Factory method:**
```swift
static func create(
    cloning workingDirectory: AbsolutePath,
    fileSystem: any FileSysteming
) async throws -> SandboxContext
```
- Create temp directory with prefix `egg-sandbox-`
- Use APFS clone (`clonefile()`) for instant copy-on-write copy
- Compute SHA256 hash for each file → baselineHashes
- Handle symlinks (copy as symlinks)
- Skip device files/sockets with warning

3. **Path validation:**
```swift
func validatePath(_ path: AbsolutePath) throws {
    let normalized = path.lexicallyNormalized()
    guard normalized.isDescendant(of: root) else {
        throw SandboxError.escapeAttempt(path: path.pathString)
    }
}
```

4. **Discard method:**
```swift
func discard(fileSystem: any FileSysteming) async {
    guard !isDiscarded else { return }  // Idempotent
    try? await fileSystem.remove(root)
    isDiscarded = true
}
```

5. **Apply changes (most complex - implement after testing basics):**
- See Phase 2

**Checklist:**
- [ ] Create actor skeleton with properties
- [ ] Implement `create()` with APFS clone (clonefile)
- [ ] Implement hash computation helper (SHA256)
- [ ] Implement file enumeration helper (recursive)
- [ ] Implement `validatePath()`
- [ ] Implement `computeChangeSummary()` (returns ChangeSummary)
- [ ] Implement `applyChanges(force:)` (returns [ConflictInfo])
- [ ] Implement `discard()`
- [ ] Tests: Creation, path validation, change summary, apply with/without force, discard idempotency

---

## Phase 2: Partial Apply Implementation

**Goal:** Implement the change detection and partial apply logic.

### 2.1 Hash Computation Helpers

**Location:** Inside SandboxContext or separate internal file

```swift
private func computeHash(
    _ path: AbsolutePath,
    fileSystem: any FileSysteming
) async throws -> String {
    let data = try await fileSystem.readFile(path)
    return SHA256.hash(data: data).hexString
}

private func enumerateFiles(
    in directory: AbsolutePath,
    fileSystem: any FileSysteming
) async throws -> [RelativePath]
```

**Checklist:**
- [ ] Implement `computeHash()` using CryptoKit SHA256
- [ ] Implement `enumerateFiles()` recursively (files only, not directories)
- [ ] Handle symlinks correctly (hash target content)
- [ ] Tests: Hash consistency, file enumeration

### 2.2 Apply Changes Method

**Implementation Steps:**

1. **Guard discarded state**
2. **Compute sandbox state:**
   - Enumerate all files in sandbox → sandboxFiles
   - Compute hash for each → sandboxHashes
3. **Compute current working directory state:**
   - For each file in baselineHashes, check if exists in workingDir
   - If exists, compute current hash → currentHashes
4. **Detect conflicts:**
   - Modified files: sandboxHash != baselineHash AND currentHash != baselineHash → CONFLICT
   - Deleted files: not in sandbox AND currentHash != baselineHash → CONFLICT
5. **Handle conflicts based on force parameter:**
   - `force=false`: If conflicts exist, throw `SandboxError.conflictingFiles`
   - `force=true`: Continue with apply (conflicts will be overridden)
6. **Apply changes:**
   - New files: Copy from sandbox to workingDir (create parent dirs)
   - Modified files: Overwrite in workingDir (including conflicting ones if force=true)
   - Deleted files: Remove from workingDir (including conflicting ones if force=true)
7. **Cleanup:** Remove sandbox directory, set isDiscarded = true
8. **Return:** List of overridden conflicts (for warning display)

**Checklist:**
- [ ] Implement sandbox state computation
- [ ] Implement current state computation
- [ ] Implement conflict detection logic
- [ ] Implement force parameter handling (throw vs continue)
- [ ] Implement change application (add, modify, delete)
- [ ] Implement directory creation for nested new files
- [ ] Handle empty directories correctly
- [ ] Return overridden conflicts list
- [ ] Tests: New files, modified files, deleted files, conflicts (with/without force)

---

## Phase 3: Protocol and Existing Component Updates

**Goal:** Create WorkflowRunning protocol and update existing components for sandbox support.

### 3.1 Create WorkflowRunning Protocol

**File:** `Sources/EggKit/WorkflowRunner/WorkflowRunning.swift`

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
- [ ] Create protocol file
- [ ] Add conformance to `LifecycleWorkflowRunner`
- [ ] Verify existing tests still pass

### 3.2 Update ShellScriptRunner

**File:** `Sources/EggKit/WorkflowRunner/ShellScriptRunner.swift`

**Changes:**
- Add optional `additionalEnvironment: [String: String]` parameter to `run()`
- Merge with existing environment in `executeProcess()`

```swift
func run(
    script: String,
    workingDirectory: AbsolutePath,
    additionalEnvironment: [String: String] = [:]
) async throws -> ShellOutput
```

**Checklist:**
- [ ] Add `additionalEnvironment` parameter
- [ ] Merge environment variables in process execution
- [ ] Update existing call sites (if any)
- [ ] Tests: Environment variable merging

### 3.3 Update LifecycleStepRunner

**File:** `Sources/EggKit/WorkflowRunner/LifecycleStepRunner.swift`

**Changes:**
- Accept optional `environmentOverrides: [String: String]` in initializer
- Pass to ShellScriptRunner

```swift
init(
    // ... existing params ...
    environmentOverrides: [String: String] = [:]
)
```

**Checklist:**
- [ ] Add `environmentOverrides` property
- [ ] Pass to ShellScriptRunner.run()
- [ ] Tests: Environment override propagation

---

## Phase 4: SandboxedWorkflowRunner Implementation

**Goal:** Create the main orchestrator that ties everything together.

### 4.1 Create SandboxedWorkflowRunner

**File:** `Sources/EggKit/WorkflowRunner/SandboxedWorkflowRunner.swift`

**Structure:**

```swift
struct SandboxedWorkflowRunner: WorkflowRunning {
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

1. **Sandbox creation:**
```swift
let sandbox = try await SandboxContext.create(
    cloning: workingDirectory,
    fileSystem: fileSystem
)
```

2. **Environment variables:**
```swift
let sandboxEnv = [
    "EGG_SANDBOX_ROOT": sandbox.root.pathString,
    "EGG_ORIGINAL_WORKING_DIR": workingDirectory.pathString
]
```

3. **Execute pre_hatch:**
```swift
let preHatchRunner = LifecycleStepRunner(
    // ... existing params ...
    workingDirectory: sandbox.root,
    environmentOverrides: sandboxEnv
)
```

4. **Validate and execute hatch:**
```swift
// Resolve output path
let resolvedOutput = try resolveOutputPath(...)
let absoluteOutput = sandbox.root.appending(resolvedOutput)

// Validate within sandbox
try sandbox.validatePath(absoluteOutput)

// Expand templates
let expander = TemplateExpander(...)
try await expander.expand(to: absoluteOutput, ...)
```

5. **Execute post_hatch:**
```swift
let postHatchRunner = LifecycleStepRunner(
    // ... existing params ...
    workingDirectory: sandbox.root,
    environmentOverrides: sandboxEnv
)
```

6. **User confirmation (unless force=true):**
```swift
let changeSummary = try await sandbox.computeChangeSummary(fileSystem: fileSystem)

if !force {
    // Display change summary to user
    displayChangeSummary(changeSummary, noora: noora)

    // Prompt for confirmation
    let confirmed = await noora.confirm("Apply these changes?")
    guard confirmed else {
        await sandbox.discard(fileSystem: fileSystem)
        throw SandboxError.userAborted
    }
}
```

7. **Apply changes and display conflict warnings:**
```swift
// force=true: override conflicts with warning
// force=false: throw error on conflicts
let overriddenConflicts = try await sandbox.applyChanges(fileSystem: fileSystem, force: force)

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
    await sandbox.discard(fileSystem: fileSystem)
    throw error
}
```

**Checklist:**
- [ ] Create basic structure with dependencies (including `force` parameter)
- [ ] Implement sandbox creation
- [ ] Implement pre_hatch execution with environment
- [ ] Implement output path validation
- [ ] Implement hatch execution
- [ ] Implement post_hatch execution
- [ ] Implement change summary display (helper function)
- [ ] Implement user confirmation prompt (using Noora)
- [ ] Implement apply with force parameter (pass to applyChanges)
- [ ] Implement conflict warning display (when force=true)
- [ ] Implement discard on failure or user abort
- [ ] Tests: Full workflow, user confirmation, user abort, force mode, conflict override

---

## Phase 5: CLI Integration

**Goal:** Integrate SandboxedWorkflowRunner into HatchRunner with `--no-sandbox` and `--force` options.

### 5.1 Update HatchRunner

**File:** `Sources/EggKit/HatchRunner.swift`

**Changes:**

1. **Add useSandbox and force parameters:**
```swift
init(
    // ... existing params ...
    useSandbox: Bool = true,
    force: Bool = false
)
```

2. **Factory pattern for runner selection:**
```swift
private func makeWorkflowRunner() -> any WorkflowRunning {
    if useSandbox {
        return SandboxedWorkflowRunner(
            processRunner: processRunner,
            fileSystem: fileSystem,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            noora: noora,
            isInteractive: isInteractive,
            force: force
        )
    } else {
        noora.warning("Running without sandbox; filesystem changes are permanent")
        return LifecycleWorkflowRunner(...)
    }
}
```

**Checklist:**
- [ ] Add `useSandbox` and `force` parameters to HatchRunner
- [ ] Implement runner factory method
- [ ] Pass `force` to SandboxedWorkflowRunner
- [ ] Add warning for no-sandbox mode
- [ ] Tests: Runner selection, force mode behavior

### 5.2 Update CLI Hatch Command

**File:** `Sources/EggCLI/Commands/HatchCommand.swift`

**Changes:**
```swift
@Flag(name: .long, help: "Disable sandboxing (filesystem changes are permanent)")
var noSandbox: Bool = false

@Flag(name: .long, help: "Skip confirmation and override conflicts with warning")
var force: Bool = false
```

Pass to HatchRunner:
```swift
let runner = HatchRunner(
    // ... existing params ...
    useSandbox: !noSandbox,
    force: force
)
```

**Checklist:**
- [ ] Add `--no-sandbox` flag
- [ ] Add `--force` flag
- [ ] Pass both flag values to HatchRunner
- [ ] Update help text for both flags
- [ ] Integration test: sandbox + no-sandbox + force combinations

---

## Phase 6: Testing and Polish

**Goal:** Comprehensive testing and documentation.

### 6.1 Unit Tests

**New Test Files:**
- `Tests/EggKitTests/WorkflowRunner/SandboxContextTests.swift`
- `Tests/EggKitTests/WorkflowRunner/SandboxedWorkflowRunnerTests.swift`

**Test Categories:**

1. **SandboxContext Tests:**
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

2. **SandboxedWorkflowRunner Tests:**
   - [ ] Full workflow success (with user confirmation)
   - [ ] Force mode skips confirmation
   - [ ] User abort discards sandbox
   - [ ] Conflict without force throws error
   - [ ] Conflict with force overrides and shows warning
   - [ ] Pre-hatch failure discards sandbox
   - [ ] Hatch failure discards sandbox
   - [ ] Post-hatch failure discards sandbox
   - [ ] Output path escape throws error
   - [ ] Environment variables set correctly

3. **Integration Tests:**
   - [ ] End-to-end with real filesystem (user confirms)
   - [ ] --force flag skips confirmation
   - [ ] --no-sandbox flag works
   - [ ] APFS clone performance (instant for large directories)
   - [ ] Symlink handling

### 6.2 Documentation Updates

- [ ] Update README with sandbox feature
- [ ] Document --no-sandbox flag
- [ ] Document conflict resolution workflow
- [ ] Add examples of sandbox behavior

### 6.3 Error Messages

- [ ] Clear conflict error messages with file paths
- [ ] Escape attempt error shows problematic path
- [ ] Creation failure shows underlying reason

---

## Implementation Order Summary

| Phase | Components | Dependencies | Estimated Complexity |
|-------|------------|--------------|---------------------|
| 1 | SandboxError, SandboxContext (basic) | FileSysteming | Medium |
| 2 | Hash computation, Apply changes | Phase 1 | High |
| 3 | WorkflowRunning protocol, Updates | Existing code | Low |
| 4 | SandboxedWorkflowRunner | Phases 1-3 | High |
| 5 | CLI integration | Phase 4 | Low |
| 6 | Testing, documentation | Phases 1-5 | Medium |

**Recommended Implementation Strategy:**
1. Phases 1-2 first (core sandbox logic)
2. Phase 3 in parallel with testing Phase 1-2
3. Phase 4 after Phases 1-3 complete
4. Phases 5-6 last

---

## Success Criteria

### Functional Requirements

- [ ] Sandbox clones working directory instantly (APFS clone)
- [ ] All phases execute within sandbox
- [ ] Escape attempts are detected and blocked
- [ ] Change summary displayed before apply
- [ ] User confirmation required (unless --force)
- [ ] Partial apply only changes modified files
- [ ] Conflicts detected with clear error messages
- [ ] Sandbox discarded on failure or user abort
- [ ] --no-sandbox falls back to legacy behavior
- [ ] --force skips confirmation and overrides conflicts with warning

### Non-Functional Requirements

- [ ] APFS clone is instant (regardless of directory size)
- [ ] Hash computation is reasonably fast
- [ ] Memory usage stays bounded
- [ ] No orphaned sandbox directories on crash

### Test Coverage

- [ ] All SandboxError cases covered (including userAborted)
- [ ] SandboxContext: creation, validation, change summary, apply, discard
- [ ] SandboxedWorkflowRunner: success, user confirmation, user abort, force mode
- [ ] CLI integration: --no-sandbox, --force, combined flags

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
| `SandboxError.swift` | Error types for sandbox operations |
| `SandboxContext.swift` | Actor managing sandbox lifecycle |
| `WorkflowRunning.swift` | Protocol for workflow runners |
| `SandboxedWorkflowRunner.swift` | Main orchestrator |
| `SandboxContextTests.swift` | Unit tests for SandboxContext |
| `SandboxedWorkflowRunnerTests.swift` | Unit tests for runner |

### Modified Files

| File | Changes |
|------|---------|
| `LifecycleWorkflowRunner.swift` | Add WorkflowRunning conformance |
| `LifecycleStepRunner.swift` | Add environmentOverrides parameter |
| `ShellScriptRunner.swift` | Add additionalEnvironment parameter |
| `HatchRunner.swift` | Add useSandbox and force parameters, factory method |
| `HatchCommand.swift` | Add --no-sandbox and --force flags |

---

## Notes

- Start with Phase 1-2 to establish core sandbox mechanics
- Test extensively before integrating with workflow
- Actor pattern from StepOutputsStorage is good reference
- APFS clone makes directory size irrelevant (instant copy-on-write)
- User confirmation is default; `--force` for automation/scripts
- `--force` overrides conflicts with warning (not silent)
- Consider mtime optimization for hash computation as follow-up
