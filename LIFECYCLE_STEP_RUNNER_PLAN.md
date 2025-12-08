# LifecycleStepRunner Implementation Plan

## Overview

Implementation plan for executing pre_hatch and post_hatch lifecycle steps from config.yaml, with support for step outputs, variable substitution, and conditional execution.

## Design Principles

1. **Memory-based storage**: Store step outputs in memory (not files)
2. **stdout parsing**: Extract `key=value` outputs from shell script stdout
3. **Follow existing patterns**: Reuse ProcessRunning, package access level, Internals/ structure
4. **Integration with HatchRunner**: Seamlessly integrate with existing hatching workflow

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ HatchRunner                                             │
│                                                         │
│  1. Execute pre_hatch steps (LifecycleStepRunner)      │
│     → Collect outputs                                   │
│                                                         │
│  2. Execute hatch (existing logic)                      │
│                                                         │
│  3. Execute post_hatch steps (LifecycleStepRunner)      │
│     → Can reference pre_hatch outputs                   │
└─────────────────────────────────────────────────────────┘

LifecycleStepRunner:
  ├─ StepOutputs (memory storage)
  ├─ VariableResolver (macro + outputs substitution)
  ├─ StepOutputParser (parse key=value from stdout)
  ├─ ShellScriptRunner (execute shell commands)
  └─ ConditionEvaluator (evaluate if conditions)
```

## Core Components

### 1. StepOutputs (Data Structure)

**File**: `Sources/EggKit/Internals/StepOutputs.swift`

```swift
/// Stores outputs from executed lifecycle steps
package struct StepOutputs {
    /// Storage: "phase.stepId" -> ["key": "value"]
    private var storage: [String: [String: String]] = [:]

    /// Store outputs for a step
    package mutating func store(phase: String, stepId: String, outputs: [String: String])

    /// Retrieve output value
    package func get(phase: String, stepId: String, key: String) -> String?

    /// Check if output exists
    package func has(phase: String, stepId: String, key: String) -> Bool
}
```

**Purpose**: In-memory storage for step outputs across the entire lifecycle execution.

### 2. StepOutputParser

**File**: `Sources/EggKit/Internals/StepOutputParser.swift`

```swift
/// Parses key=value outputs from shell script stdout
package struct StepOutputParser {
    /// Parse stdout into key-value pairs
    /// - Parameter stdout: Shell script output
    /// - Returns: Dictionary of key-value pairs
    package static func parse(_ stdout: String) -> [String: String]
}
```

**Purpose**: Extract `key=value` lines from stdout.

**Implementation details**:
- Split by newlines
- Trim whitespace
- Parse `key=value` format
- Skip empty lines
- Handle values with `=` in them (only split on first `=`)

### 3. VariableResolver

**File**: `Sources/EggKit/Internals/VariableResolver.swift`

```swift
/// Resolves variables (macros and step outputs) in strings
package struct VariableResolver {
    private let macros: [String: String]
    private let outputs: StepOutputs

    package init(macros: [String: String], outputs: StepOutputs)

    /// Resolve all variables in text
    /// - Parameter text: Text with variables
    /// - Returns: Text with variables replaced
    /// - Throws: VariableResolutionError if undefined reference
    package func resolve(_ text: String) throws -> String
}
```

**Purpose**: Replace both macros (`___NAME___`) and step outputs (`${{ phase.step-id.outputs.key }}`) in strings.

**Implementation details**:
1. First pass: Replace macros (simple string replacement)
2. Second pass: Replace step outputs (regex pattern matching)
   - Pattern: `\$\{\{\s*(\w+)\.([a-zA-Z0-9_-]+)\.outputs\.([a-zA-Z0-9_-]+)\s*\}\}`
   - Extract: phase, stepId, key
   - Lookup in StepOutputs
   - Throw error if undefined

### 4. ShellScriptRunner

**File**: `Sources/EggKit/Internals/ShellScriptRunner.swift`

```swift
/// Executes shell scripts using ProcessRunning
package struct ShellScriptRunner {
    private let processRunner: any ProcessRunning
    private let workingDirectory: AbsolutePath

    package init(processRunner: any ProcessRunning, workingDirectory: AbsolutePath)

    /// Execute a shell command
    /// - Parameter command: Shell script to execute
    /// - Returns: stdout and stderr
    /// - Throws: ShellExecutionError if command fails
    package func execute(_ command: String) async throws -> (stdout: String, stderr: String)
}
```

**Purpose**: Execute shell commands using `/bin/sh -c`.

**Implementation details**:
- Use ProcessRunning.run()
- Execute: `/bin/sh -c "command"`
- Working directory: Set to workingDirectory
- Capture stdout and stderr
- Throw error if non-zero exit code

### 5. ConditionEvaluator (Placeholder)

**File**: `Sources/EggKit/Internals/ConditionEvaluator.swift`

```swift
/// Evaluates conditional expressions (if field)
package struct ConditionEvaluator {
    private let macros: [String: String]
    private let outputs: StepOutputs

    package init(macros: [String: String], outputs: StepOutputs)

    /// Evaluate a condition expression
    /// - Parameter condition: Condition string
    /// - Returns: true if condition is met
    /// - Throws: ConditionEvaluationError
    package func evaluate(_ condition: String) throws -> Bool
}
```

**Purpose**: Evaluate `if` conditions (placeholder for now).

**Implementation**:
- Phase 1: Always return `true` (TODO comment)
- Phase 2: Implement JavaScript-like expression evaluation

### 6. LifecycleStepRunner (Main Orchestrator)

**File**: `Sources/EggKit/LifecycleStepRunner.swift`

```swift
/// Executes lifecycle steps (pre_hatch/post_hatch) from config.yaml
package struct LifecycleStepRunner {
    private let processRunner: any ProcessRunning
    private let workingDirectory: AbsolutePath

    package init(processRunner: any ProcessRunning, workingDirectory: AbsolutePath)

    /// Execute all steps in a phase
    /// - Parameters:
    ///   - phase: Phase name ("pre_hatch" or "post_hatch")
    ///   - steps: Lifecycle steps to execute
    ///   - macros: Resolved macros
    ///   - existingOutputs: Outputs from previous phases
    /// - Returns: Combined outputs (existing + new)
    package func executePhase(
        phase: String,
        steps: [Config.LifecycleStep],
        macros: [String: String],
        existingOutputs: StepOutputs
    ) async throws -> StepOutputs

    /// Execute a single step
    private func executeStep(
        _ step: Config.LifecycleStep,
        phase: String,
        resolver: VariableResolver,
        evaluator: ConditionEvaluator
    ) async throws -> [String: String]?
}
```

**Purpose**: Main orchestrator for executing lifecycle phases.

**Execution flow**:
```
For each step in phase:
  1. Evaluate condition (if present)
     - Skip if condition is false

  2. Resolve variables in run command
     - Replace macros
     - Replace step outputs

  3. Execute shell script
     - Run command via ShellScriptRunner
     - Capture stdout/stderr

  4. Parse outputs (if step has id)
     - Parse stdout for key=value
     - Store in StepOutputs

  5. Return updated StepOutputs
```

## Integration with HatchRunner

**File**: `Sources/EggKit/HatchRunner.swift` (MODIFY)

### Current structure (from exploration):

```swift
package struct HatchRunner {
    func hatch(...) async throws {
        // 1. Validate arguments
        // 2. Resolve macros
        // 3. Copy template files
        // 4. Substitute macros in files
    }
}
```

### Modified structure:

```swift
package struct HatchRunner {
    private let lifecycleRunner: LifecycleStepRunner

    func hatch(...) async throws {
        // 1. Validate arguments

        // 2. Resolve macros
        let macros = resolveAllMacros(...)

        // NEW: 3. Execute pre_hatch
        var stepOutputs = StepOutputs()
        if let preHatchSteps = config.preHatch {
            stepOutputs = try await lifecycleRunner.executePhase(
                phase: "pre_hatch",
                steps: preHatchSteps,
                macros: macros,
                existingOutputs: stepOutputs
            )
        }

        // 4. Copy template files (existing logic)

        // 5. Substitute macros in files (existing logic)

        // NEW: 6. Execute post_hatch
        if let postHatchSteps = config.postHatch {
            stepOutputs = try await lifecycleRunner.executePhase(
                phase: "post_hatch",
                steps: postHatchSteps,
                macros: macros,
                existingOutputs: stepOutputs
            )
        }
    }
}
```

### Changes needed:
1. Add `lifecycleRunner` property
2. Initialize in `init`
3. Call `executePhase` for pre_hatch before template copying
4. Call `executePhase` for post_hatch after template copying
5. Pass `stepOutputs` between phases

## Error Handling

### Error types to define:

**File**: `Sources/EggKit/Internals/LifecycleErrors.swift`

```swift
package enum LifecycleError: Error, LocalizedError {
    case shellExecutionFailed(command: String, exitCode: Int32, stderr: String)
    case undefinedOutputReference(phase: String, stepId: String, key: String)
    case conditionEvaluationFailed(condition: String, reason: String)
    case invalidOutputFormat(line: String)

    package var errorDescription: String? {
        switch self {
        case .shellExecutionFailed(let command, let exitCode, let stderr):
            return "Shell command failed with exit code \(exitCode): \(command)\n\(stderr)"
        case .undefinedOutputReference(let phase, let stepId, let key):
            return "Undefined output reference: ${{ \(phase).\(stepId).outputs.\(key) }}"
        case .conditionEvaluationFailed(let condition, let reason):
            return "Failed to evaluate condition '\(condition)': \(reason)"
        case .invalidOutputFormat(let line):
            return "Invalid output format (expected key=value): \(line)"
        }
    }
}
```

## Testing Strategy

### Test files to create:

#### 1. StepOutputParserTests.swift

```swift
struct StepOutputParserTests {
    @Test func parseSimpleOutput()
    @Test func parseMultipleOutputs()
    @Test func parseOutputWithSpaces()
    @Test func parseOutputWithEqualsInValue()
    @Test func skipEmptyLines()
    @Test func trimWhitespace()
}
```

#### 2. VariableResolverTests.swift

```swift
struct VariableResolverTests {
    @Test func resolveMacros()
    @Test func resolveStepOutputs()
    @Test func resolveMixed()
    @Test func undefinedOutputThrowsError()
    @Test func complexPattern()
}
```

#### 3. ShellScriptRunnerTests.swift

```swift
struct ShellScriptRunnerTests {
    @Test func executeSimpleCommand()
    @Test func captureStdout()
    @Test func captureStderr()
    @Test func workingDirectoryRespected()
    @Test func failedCommandThrowsError()
}
```

#### 4. LifecycleStepRunnerTests.swift

```swift
struct LifecycleStepRunnerTests {
    @Test func executeSimpleStep()
    @Test func executeStepWithOutputs()
    @Test func executeStepWithMacroSubstitution()
    @Test func executeStepWithOutputReference()
    @Test func executeConditionalStep()
    @Test func executeMultipleStepsWithDependencies()
    @Test func skipStepWhenConditionFalse()
    @Test func crossPhaseOutputReferences()
}
```

### Test fixtures:

Create YAML fixtures similar to ConfigDecodingTests:
- `lifecycle_simple.yml` - Basic step execution
- `lifecycle_with_outputs.yml` - Steps with outputs
- `lifecycle_with_conditions.yml` - Conditional execution
- `lifecycle_cross_reference.yml` - Cross-step output references

### Mock ProcessRunner:

Reuse or extend existing mock from tests:

```swift
final class MockProcessRunner: ProcessRunning {
    var mockStdout: String = ""
    var mockStderr: String = ""
    var mockExitCode: Int32 = 0
    var capturedCommands: [(executable: String, arguments: [String])] = []

    func run(...) async throws -> CollectedResult {
        // Capture command
        capturedCommands.append(...)

        // Return mock result
        return CollectedResult(
            terminationStatus: mockExitCode == 0 ? .success : .failure(mockExitCode),
            standardOutput: Data(mockStdout.utf8),
            standardError: Data(mockStderr.utf8)
        )
    }
}
```

## Implementation Steps

### Phase 1: Core Components (Independent)

1. **StepOutputs.swift** - Data structure (30 min)
   - Define struct with storage
   - Implement store/get/has methods
   - Unit tests

2. **StepOutputParser.swift** - Parser (30 min)
   - Implement parse() method
   - Handle edge cases
   - Unit tests

3. **LifecycleErrors.swift** - Error types (15 min)
   - Define error enum
   - Add error descriptions

### Phase 2: Execution Components

4. **ShellScriptRunner.swift** - Shell execution (45 min)
   - Implement execute() method
   - Use ProcessRunning
   - Error handling
   - Unit tests

5. **VariableResolver.swift** - Variable substitution (1 hour)
   - Implement macro replacement
   - Implement output reference regex
   - Error handling
   - Unit tests

6. **ConditionEvaluator.swift** - Placeholder (15 min)
   - Stub that returns true
   - TODO comment for future implementation

### Phase 3: Main Orchestrator

7. **LifecycleStepRunner.swift** - Main logic (1.5 hours)
   - Implement executePhase()
   - Implement executeStep()
   - Integrate all components
   - Error handling
   - Unit tests

### Phase 4: Integration

8. **HatchRunner.swift** - Modify existing (1 hour)
   - Add lifecycleRunner property
   - Call executePhase for pre_hatch
   - Call executePhase for post_hatch
   - Pass outputs between phases
   - Integration tests

### Phase 5: End-to-End Testing

9. **Integration tests** (1 hour)
   - Create YAML fixtures
   - Test full lifecycle execution
   - Test cross-phase output references
   - Test error cases

## Total Estimated Time

- Phase 1: 1.25 hours
- Phase 2: 2 hours
- Phase 3: 1.5 hours
- Phase 4: 1 hour
- Phase 5: 1 hour
- **Total: ~7 hours**

## Example Usage

### config.yaml:

```yaml
name: MyTemplate
description: Example with lifecycle steps

macros:
  - name: ___PROJECT_NAME___
    description: Project name
    type: string

pre_hatch:
  # Step 1: Setup
  - id: setup
    run: |
      VERSION="1.0.0"
      SRC_DIR="./Sources/___PROJECT_NAME___"
      echo "version=$VERSION"
      echo "src-dir=$SRC_DIR"

  # Step 2: Validate
  - id: validate
    run: |
      echo "Validating version: ${{ pre_hatch.setup.outputs.version }}"
      if [ "${{ pre_hatch.setup.outputs.version }}" = "1.0.0" ]; then
        echo "valid=true"
      else
        echo "valid=false"
      fi

  # Step 3: Conditional
  - if: ${{ pre_hatch.validate.outputs.valid }} === "true"
    run: echo "Validation passed!"

hatch:
  output: ./output

post_hatch:
  - if: ${{ pre_hatch.validate.outputs.valid }} === "true"
    run: |
      echo "Project created at: ${{ pre_hatch.setup.outputs.src-dir }}"
      echo "Version: ${{ pre_hatch.setup.outputs.version }}"
```

### Execution flow:

```
1. HatchRunner.hatch() called
2. Resolve macros: ___PROJECT_NAME___ = "MyApp"
3. Execute pre_hatch:
   a. Step "setup":
      - Run: echo "version=1.0.0" ...
      - Parse outputs: {version: "1.0.0", src-dir: "./Sources/MyApp"}
      - Store: pre_hatch.setup -> outputs
   b. Step "validate":
      - Resolve: ${{ pre_hatch.setup.outputs.version }} -> "1.0.0"
      - Run: echo "Validating version: 1.0.0" ...
      - Parse outputs: {valid: "true"}
      - Store: pre_hatch.validate -> outputs
   c. Step (conditional):
      - Evaluate: ${{ pre_hatch.validate.outputs.valid }} === "true"
      - Condition: true
      - Run: echo "Validation passed!"
4. Execute hatch (existing logic)
5. Execute post_hatch:
   a. Step (conditional):
      - Resolve: ${{ pre_hatch.setup.outputs.src-dir }} -> "./Sources/MyApp"
      - Run: echo "Project created at: ./Sources/MyApp"
```

## Future Enhancements

### Phase 6 (Future): Condition Evaluation

Implement full JavaScript-like expression evaluation in ConditionEvaluator:
- Boolean operators: `&&`, `||`, `!`
- Comparison: `===`, `!==`, `>`, `<`, `>=`, `<=`
- Array methods: `.includes()`
- String methods: `.startsWith()`, `.endsWith()`

Consider using:
- JavaScriptCore (built-in on macOS/iOS)
- Swift Expression evaluation library
- Custom expression parser

## Dependencies

All dependencies already available in the project:
- `ProcessRunning` (for shell execution)
- `Path` (for file paths)
- `Foundation` (for string manipulation, regex)
- Swift Testing (for tests)

No new dependencies needed.

## Success Criteria

1. ✅ All lifecycle steps execute in order
2. ✅ Step outputs are captured and stored
3. ✅ Variable resolution works for macros and outputs
4. ✅ Conditional execution works (with placeholder evaluator)
5. ✅ Shell scripts execute correctly
6. ✅ Errors are handled gracefully
7. ✅ Integration with HatchRunner is seamless
8. ✅ All tests pass
9. ✅ Code follows project conventions
10. ✅ No new dependencies added

## Notes

- This implementation uses **memory-based storage** (not files), which is simpler and sufficient for this use case
- **Condition evaluation** is stubbed for Phase 1, to be implemented in Phase 6
- **ProcessRunning** API usage follows patterns from OpenRunner.swift
- All new code uses **package** access level following project conventions
- Error messages are descriptive and user-friendly
- Tests follow existing patterns from ConfigDecodingTests and other test files
