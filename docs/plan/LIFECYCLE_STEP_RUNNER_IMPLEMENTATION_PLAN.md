# LifecycleStepRunner Implementation Plan

## Overview

This document outlines the step-by-step implementation plan for the LifecycleStepRunner system based on `LIFECYCLE_STEP_RUNNER_DESIGN.md`.

## Implementation Phases

### Phase 1: Foundation - Data Structures and Parsers

**Goal**: Implement the most fundamental components with no external dependencies.

#### 1.1 StepOutputs.swift ✓ (Priority: HIGHEST)

**File**: `Sources/EggKit/Internals/StepOutputs.swift`

**Why first?**
- Most fundamental data structure
- No dependencies on other components
- Required by all subsequent components
- Easy to test in isolation

**Implementation**:
```swift
package struct StepOutputs {
    package init()
    package mutating func store(phase: String, stepId: String, outputs: [String: String])
    package func get(phase: String, stepId: String, key: String) -> String?
    package func has(phase: String, stepId: String, key: String) -> Bool
}
```

**Storage format**: `[phase.stepId: [key: value]]`

**Tests**:
- Store and retrieve outputs
- Cross-phase access (pre_hatch → post_hatch)
- Missing key handling

---

#### 1.2 StepOutputParser.swift

**File**: `Sources/EggKit/Internals/StepOutputParser.swift`

**Dependencies**: StepOutputs (for testing)

**Why second?**
- Simple parsing logic
- Only depends on StepOutputs
- Clear input/output contract
- Easy to test

**Implementation**:
```swift
package struct StepOutputParser {
    package static func parse(_ stdout: String) -> [String: String]
}
```

**Parsing rules**:
- Split by newlines
- Find first `=` in each line
- Trim whitespace
- Skip empty lines
- Handle values containing `=`

**Tests**:
- Basic key=value parsing
- Multi-line output
- Values with `=` characters
- Empty lines and whitespace
- Edge cases (no `=`, empty values)

---

### Phase 2: Utilities - Errors and Shell Execution

**Goal**: Implement utility components needed by the main orchestrator.

#### 2.1 LifecycleErrors.swift

**File**: `Sources/EggKit/Internals/LifecycleErrors.swift`

**Why third?**
- Defines error types used across components
- No dependencies
- Enables proper error handling in subsequent components

**Error types**:
```swift
package enum LifecycleStepError: Error {
    case shellExecutionError(command: String, exitCode: Int32, stderr: String)
    case undefinedOutputReference(phase: String, stepId: String, key: String)
    case conditionEvaluationError(condition: String, reason: String)
}
```

**Tests**:
- Error message formatting
- LocalizedError conformance

---

#### 2.2 ShellScriptRunner.swift

**File**: `Sources/EggKit/Internals/ShellScriptRunner.swift`

**Dependencies**:
- ProcessRunning protocol
- LifecycleErrors

**Why fourth?**
- Independent component
- Follows existing pattern from OpenRunner.swift
- Can be tested in isolation

**Implementation**:
```swift
package struct ShellScriptRunner {
    package init(processRunner: any ProcessRunning, workingDirectory: AbsolutePath)
    package func execute(_ command: String) async throws -> (stdout: String, stderr: String)
}
```

**Execution**:
- Command: `/bin/sh -c "user_command"`
- Working directory: Set from context
- Capture stdout and stderr
- Throw on non-zero exit code

**Tests**:
- Successful command execution
- Stdout/stderr capture
- Error handling (non-zero exit)
- Working directory context

---

### Phase 3: Variable Resolution and Conditions

**Goal**: Implement variable substitution and conditional evaluation.

#### 3.1 VariableResolver.swift

**File**: `Sources/EggKit/Internals/VariableResolver.swift`

**Dependencies**:
- ResolvedMacro
- StepOutputs
- LifecycleErrors

**Why fifth?**
- Required by ShellScriptRunner (command string resolution)
- Required by ConditionEvaluator
- Two-pass resolution logic needs careful implementation

**Implementation**:
```swift
package struct VariableResolver {
    package init(macros: [ResolvedMacro], outputs: StepOutputs)
    package func resolve(_ text: String) throws -> String
}
```

**Resolution process**:
1. **First pass - Macros**: `___MACRO_NAME___`
   - Convert ResolvedMacro.value to string (no quoting)
   - `.string(s)` → `s`
   - `.boolean(b)` → `true` or `false`
   - `.choice(c)` → `c`
   - `.array(a)` → `item1,item2`
   - `.path(p)` → `p.pathString`

2. **Second pass - Step outputs**: `${{ phase.step-id.outputs.key }}`
   - Regex matching and lookup
   - Direct string replacement (no quoting)
   - Throw if undefined reference

**Tests**:
- Macro replacement (all types)
- Step output replacement
- Combined macro + output resolution
- Undefined reference error
- Edge cases (nested patterns, special characters)

---

#### 3.2 ConditionEvaluator.swift (Full Implementation)

**File**: `Sources/EggKit/Internals/ConditionEvaluator.swift`

**Dependencies**:
- ResolvedMacro
- StepOutputsStorage
- LifecycleErrors
- JSEvaluator

**Why sixth?**
- Required by LifecycleStepRunner
- Implements full JavaScript-like expression evaluation
- Type-aware variable expansion

**Implementation**:
```swift
struct ConditionEvaluator {
    init(macros: [ResolvedMacro], outputs: StepOutputsStorage)
    func evaluate(_ condition: String) async throws -> Bool
}
```

**Features**:
- Use JSEvaluator for JavaScript expression evaluation
- Type-aware variable expansion:
  - Macros: Quote strings/choices/paths, unquote booleans, JSON arrays
  - Step outputs: Direct replacement (user handles quoting in condition)
- Support operators: `===`, `!==`, `&&`, `||`, `includes()`
- Two-pass resolution: Macros first, then step outputs

**Tests**:
- Boolean macro evaluation
- String comparison with step outputs
- Array includes operations
- Complex expressions with multiple operators
- Error cases (undefined references, invalid syntax)

**Type-Aware Variable Expansion**:

**IMPORTANT**: ConditionEvaluator uses **different quoting rules** than VariableResolver:

- **VariableResolver** (for `run` fields): Direct string replacement, NO quoting
- **ConditionEvaluator** (for `if` fields): Type-aware quoting for JavaScript evaluation

When expanding variables in conditions, proper quoting is essential for JavaScript evaluation:

1. **Macros (from config.yaml)**:
   - `.string(s)` → `"s"` (quoted)
   - `.boolean(b)` → `true` or `false` (unquoted)
   - `.choice(c)` → `"c"` (quoted)
   - `.array(a)` → `["item1", "item2"]` (JSON array)
   - `.path(p)` → `"path"` (quoted)

2. **Step outputs**: Direct replacement (user adds quotes in condition when comparing strings)

**Example Usage**:
```yaml
macros:
  - name: ___DEBUG___
    type: boolean
    default: true
  - name: ___PLATFORMS___
    type: array
    default: ["iOS", "macOS"]
  - name: ___BUILD_TYPE___
    type: choice
    default: "release"

pre_hatch:
  - id: setup
    run: echo "ready=true"

  # Boolean macro - no quotes (unquoted)
  - if: ___DEBUG___ === true
    run: echo "Debug mode enabled"

  # String output - quoted
  - if: "${{ pre_hatch.setup.outputs.ready }}" === "true"
    run: echo "Setup complete"

  # Array includes - macro becomes JSON array
  - if: ___PLATFORMS___.includes("iOS")
    run: echo "iOS platform detected"

  # Complex expression with multiple operators
  - if: (___DEBUG___ && ___PLATFORMS___.includes("iOS")) || ___BUILD_TYPE___ === "debug"
    run: echo "Complex condition met"
```

**Variable Expansion Process**:
1. **First pass - Macros**:
   - `___DEBUG___ === true` → `true === true`
   - `___PLATFORMS___.includes("iOS")` → `["iOS", "macOS"].includes("iOS")`
   - `___BUILD_TYPE___ === "debug"` → `"release" === "debug"`

2. **Second pass - Step outputs** (direct replacement, user handles quoting):
   - `"${{ pre_hatch.setup.outputs.ready }}" === "true"` → `"true" === "true"`
   - Note: The quotes around `${{ }}` are user-provided in the condition

3. **JavaScript evaluation**:
   - JSEvaluator evaluates the final expression
   - Returns boolean result or throws error

---

### Phase 4: Phase Executor

**Goal**: Implement the phase executor that runs individual lifecycle phases.

#### 4.1 LifecycleStepRunner.swift

**File**: `Sources/EggKit/LifecycleStepRunner.swift`

**Dependencies**: ALL previous components

**Why seventh?**
- Phase-level execution orchestrator
- Requires all components to be complete
- Focused responsibility: execute steps within one phase

**Implementation**:
```swift
struct LifecycleStepRunner {
    init(processRunner: any ProcessRunning, workingDirectory: AbsolutePath)

    func executePhase(
        phase: String,
        steps: [Config.LifecycleStep],
        macros: [ResolvedMacro],
        existingOutputs: StepOutputsStorage
    ) async throws -> StepOutputsStorage
}
```

**Per-step execution flow**:
1. Check condition with ConditionEvaluator
2. Skip if condition is false
3. Resolve variables with VariableResolver
4. Execute command with ShellScriptRunner
5. Parse outputs with StepOutputParser (if step has id)
6. Store outputs in StepOutputsStorage
7. Continue to next step

**Tests**:
- Full phase execution
- Step skipping based on conditions
- Output propagation between steps
- Cross-phase output access
- Error propagation
- Integration with all components

---

### Phase 5: Workflow Orchestrator

**Goal**: Implement the top-level workflow orchestrator that manages the complete lifecycle.

#### 5.1 LifecycleWorkflowRunner.swift

**File**: `Sources/EggKit/LifecycleWorkflowRunner.swift`

**Dependencies**:
- LifecycleStepRunner
- TemplateExpander (for hatch phase)
- Config
- ResolvedMacro
- StepOutputsStorage

**Why eighth?**
- Top-level workflow orchestrator
- Separates workflow logic from HatchRunner
- Manages pre_hatch → hatch → post_hatch flow

**Implementation**:
```swift
struct LifecycleWorkflowRunner {
    private let processRunner: any ProcessRunning
    private let workingDirectory: AbsolutePath
    private let outputDirectory: AbsolutePath

    init(
        processRunner: any ProcessRunning,
        workingDirectory: AbsolutePath,
        outputDirectory: AbsolutePath
    )

    func run(
        config: Config,
        macros: [ResolvedMacro],
        templateDirectory: AbsolutePath
    ) async throws
}
```

**Workflow execution**:
1. Initialize StepOutputsStorage
2. Execute pre_hatch phase (if exists)
   - Use LifecycleStepRunner.executePhase()
3. Execute hatch (template expansion)
   - Use TemplateExpander (existing implementation)
   - Pass macros + step outputs for variable resolution
4. Execute post_hatch phase (if exists)
   - Use LifecycleStepRunner.executePhase()
   - Pass outputs from pre_hatch

**Tests**:
- Complete workflow execution
- pre_hatch → hatch → post_hatch flow
- Output propagation across all phases
- Error handling in each phase
- Skip phases that don't exist in config

---

### Phase 6: HatchRunner Integration

**Goal**: Integrate LifecycleStepRunner into the existing HatchRunner.

#### 5.1 Update HatchRunner.swift

**File**: `Sources/EggKit/HatchRunner.swift`

**Changes needed**:
1. Add LifecycleStepRunner instance
2. Call `executePhase` for pre_hatch
3. Perform template expansion (existing hatch logic)
4. Call `executePhase` for post_hatch (passing pre_hatch outputs)

**Implementation outline**:
```swift
package func run() async throws {
    // ... existing macro resolution ...
    let resolvedMacros = generator.generateQuestions()

    // NEW: Execute pre_hatch
    var stepOutputs = StepOutputs()
    if let preHatchSteps = template.config.preHatch {
        let lifecycleRunner = LifecycleStepRunner(
            processRunner: processRunner,
            workingDirectory: workingDirectory
        )
        stepOutputs = try await lifecycleRunner.executePhase(
            phase: "pre_hatch",
            steps: preHatchSteps,
            macros: resolvedMacros,
            existingOutputs: stepOutputs
        )
    }

    // TODO: Template expansion (hatch)

    // NEW: Execute post_hatch
    if let postHatchSteps = template.config.postHatch {
        let lifecycleRunner = LifecycleStepRunner(
            processRunner: processRunner,
            workingDirectory: workingDirectory
        )
        stepOutputs = try await lifecycleRunner.executePhase(
            phase: "post_hatch",
            steps: postHatchSteps,
            macros: resolvedMacros,
            existingOutputs: stepOutputs
        )
    }
}
```

**Tests**:
- End-to-end hatch flow with lifecycle steps
- Pre-hatch → Hatch → Post-hatch integration
- Output passing between phases

---

## Implementation Checklist

### Phase 1: Foundation
- [x] 1.1 StepOutputsStorage.swift (renamed from StepOutputs)
  - [x] Implementation (actor with LifecyclePhase enum)
  - [x] Unit tests (8 test cases)
- [x] 1.2 StepOutputParser.swift
  - [x] Implementation (enum with static method)
  - [x] Unit tests (16 test cases)

### Phase 2: Utilities
- [x] 2.1 LifecycleErrors.swift
  - [x] Implementation
  - [x] Unit tests
- [x] 2.2 ShellScriptRunner.swift
  - [x] Implementation
  - [x] Unit tests (15 test cases: 10 execute + 5 executeStreaming)

### Phase 3: Variable Resolution
- [x] 3.1 VariableResolver.swift
  - [x] Implementation (async resolve, two-pass algorithm)
  - [x] Unit tests (29 test cases with TestOutput struct)
- [x] 3.2 ConditionEvaluator.swift (Full Implementation)
  - [x] Implementation (JSEvaluator, type-aware variable expansion)
  - [x] Unit tests (comprehensive test cases)

### Phase 4: Phase Executor
- [x] 4.1 LifecycleStepRunner.swift
  - [x] Implementation
  - [x] Integration tests (14 test cases)

### Phase 4.5: Template Expander (Hatch Phase) ✓
- [x] 4.5.1 TemplateExpander.swift
  - [x] Implementation
  - [x] Integration tests (12 test cases) ✓
  - [x] Recursive directory traversal
  - [x] Macro substitution in filenames and content
  - [x] Step output substitution
  - [x] Glob pattern exclusion
  - [x] Conditional exclusion evaluation
  - [x] Binary file handling
  - **Result**: All 12 tests passed

### Phase 5: Workflow Orchestrator
- [ ] 5.1 LifecycleWorkflowRunner.swift
  - [ ] Implementation
  - [ ] Integration tests

### Phase 6: HatchRunner Integration
- [ ] 6.1 Update HatchRunner.swift
  - [ ] Pre-hatch integration
  - [ ] Post-hatch integration
  - [ ] End-to-end tests

---

## Testing Strategy

### Unit Tests
- Each component tested in isolation
- Mock dependencies using protocols
- Cover edge cases and error conditions

### Integration Tests
- Test component interactions
- Use real implementations where possible
- Test cross-phase output access

### End-to-End Tests
- Full hatch flow with lifecycle steps
- Real config.yaml scenarios
- Verify output propagation

---

## Future Enhancements

### None (Phase 3 is now complete with full implementation)

---

## Dependencies

### External
- ProcessRunning (already in Package.swift)
- FileSystem (already in Package.swift)
- Path (via FileSystem)

### Internal
- Config (already implemented)
- ResolvedMacro (already implemented)
- JSEvaluator (already implemented, for future ConditionEvaluator)

---

## Design Rationale

### Why this order?

1. **Dependency-driven**: Implement dependencies before dependents
2. **Testability**: Each component can be tested independently
3. **Early feedback**: Core functionality works before complex features
4. **Risk mitigation**: Defer complex ConditionEvaluator to later phase
5. **Incremental value**: Each phase delivers working functionality

### Why placeholder ConditionEvaluator?

- Complex feature (JavaScript evaluation)
- Core functionality (step execution, outputs) works without it
- Can be enhanced later without affecting other components
- Steps without conditions work from day one

---

## Success Criteria

### Phase 1-2 Complete
✓ Can store and retrieve step outputs
✓ Can parse stdout for key=value pairs
✓ Can execute shell commands

### Phase 3 Complete
✓ Can resolve macros in strings
✓ Can resolve step output references
✓ Can evaluate conditions (full JavaScript evaluation)

### Phase 4 Complete
✓ Can execute complete lifecycle phases
✓ Outputs propagate between steps
✓ Errors handled correctly

### Phase 5 Complete
- Can orchestrate pre_hatch → hatch → post_hatch workflow
- Outputs flow across all phases

### Phase 6 Complete
✓ HatchRunner executes pre_hatch
✓ HatchRunner executes post_hatch
✓ End-to-end hatch flow works

---

## Timeline Estimate

**Phase 1**: 1-2 days (foundation) ✓
**Phase 2**: 1-2 days (utilities) ✓
**Phase 3**: 2-3 days (variable resolution) ✓
**Phase 4**: 2-3 days (phase executor) ✓
**Phase 5**: 1-2 days (workflow orchestrator)
**Phase 6**: 1-2 days (integration)

**Total**: ~1-2 weeks for complete implementation

---

## Notes

- All components use internal access level (no `package` modifiers needed)
- Follow existing project patterns (ProcessRunning, Internals/ directory)
- Use dependency injection for testability
- Comprehensive error handling with custom error types
- Memory-based storage (no file I/O for outputs)
