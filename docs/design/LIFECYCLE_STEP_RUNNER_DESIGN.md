# LifecycleStepRunner Design Document

## Overview

LifecycleStepRunner is a system for executing pre_hatch and post_hatch lifecycle steps from config.yaml, with support for step outputs, variable substitution, and conditional execution.

## Core Design Principles

1. **Memory-based storage**: Store step outputs in memory (not files)
2. **stdout parsing**: Extract `key=value` outputs from shell script stdout
3. **Separation of concerns**: Each component has a single, well-defined responsibility
4. **Follow existing patterns**: Use ProcessRunning, package access level, Internals/ directory structure

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│ LifecycleWorkflowRunner (Top-level Orchestrator)        │
│                                                          │
│  run(config, macros, templateDirectory)                 │
│                                                          │
│  ┌────────────────────────────────────────────────┐     │
│  │ 1. Execute pre_hatch phase                     │     │
│  │    └─ LifecycleStepRunner.executePhase()       │     │
│  │                                                 │     │
│  │ 2. Execute hatch (template expansion)          │     │
│  │    └─ TemplateExpander.expand()                │     │
│  │                                                 │     │
│  │ 3. Execute post_hatch phase                    │     │
│  │    └─ LifecycleStepRunner.executePhase()       │     │
│  └────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────┐
│ LifecycleStepRunner (Phase Executor)        │
│                                             │
│  executePhase(phase, steps, macros, ...)   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ For each step:                      │   │
│  │                                     │   │
│  │  1. ConditionEvaluator              │   │
│  │     └─ Evaluate if condition        │   │
│  │                                     │   │
│  │  2. VariableResolver                │   │
│  │     ├─ Replace ___MACROS___         │   │
│  │     └─ Replace ${{ outputs }}       │   │
│  │                                     │   │
│  │  3. ShellScriptRunner               │   │
│  │     └─ Execute /bin/sh -c "cmd"    │   │
│  │                                     │   │
│  │  4. StepOutputParser                │   │
│  │     └─ Parse key=value from stdout  │   │
│  │                                     │   │
│  │  5. StepOutputsStorage              │   │
│  │     └─ Store outputs by phase.id    │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

## Component Design

### 1. StepOutputs (Data Structure)

**Responsibility**: In-memory storage for step outputs

**Interface**:
```swift
package struct StepOutputs {
    package init()

    package mutating func store(phase: String, stepId: String, outputs: [String: String])
    package func get(phase: String, stepId: String, key: String) -> String?
    package func has(phase: String, stepId: String, key: String) -> Bool
}
```

**Storage format**:
```
[phase.stepId: [key: value]]

Example:
{
  "pre_hatch.setup": {
    "version": "1.0.0",
    "src-dir": "/tmp/src"
  }
}
```

**Design rationale**: Simple dictionary-based storage, keyed by `phase.stepId` for uniqueness.

---

### 2. StepOutputParser

**Responsibility**: Parse key-value pairs from shell script stdout

**Interface**:
```swift
package struct StepOutputParser {
    package static func parse(_ stdout: String) -> [String: String]
}
```

**Parsing logic**:
- Split by newlines
- For each line: find first `=`, split into key and value
- Trim whitespace
- Skip empty lines

**Example**:
```
Input:  "version=1.0.0\nsrc-dir=/tmp/src\n"
Output: ["version": "1.0.0", "src-dir": "/tmp/src"]
```

**Design rationale**: Simple line-based parsing, robust to values containing `=`.

---

### 3. VariableResolver

**Responsibility**: Replace variables (macros and step outputs) in strings

**Interface**:
```swift
package struct VariableResolver {
    package init(macros: [ResolvedMacro], outputs: StepOutputs)

    package func resolve(_ text: String) throws -> String
}
```

**Resolution process**:
1. **First pass - Macros**:
   - Pattern: `___MACRO_NAME___`
   - Method: Convert `ResolvedMacro.value` to string, then replace (no quoting)
   - Value conversion:
     - `.string(s)` → `s`
     - `.boolean(b)` → `true` or `false`
     - `.choice(c)` → `c`
     - `.array(a)` → `item1,item2` (comma-separated, no quotes)
     - `.path(p)` → `p.pathString`

2. **Second pass - Step outputs**:
   - Pattern: `${{ phase.step-id.outputs.key }}`
   - Method: Regex matching and lookup in StepOutputs
   - Replacement: Direct string replacement (no quoting)
   - Error: Throw if undefined reference

**Note**: This resolver is for `run` fields (shell scripts). For `if` fields (conditions), see ConditionEvaluator which uses type-aware quoting.

**Example**:
```
Input:  "echo ___NAME___ ${{ pre_hatch.setup.outputs.version }}"
Macros: [ResolvedMacro(name: "___NAME___", value: .string("MyApp"))]
Outputs: pre_hatch.setup.version = "1.0.0"
Output: "echo MyApp 1.0.0"
```

**Design rationale**: Two-pass approach ensures macros are resolved before output references.

---

### 4. ShellScriptRunner

**Responsibility**: Execute shell commands and capture output

**Interface**:
```swift
package struct ShellScriptRunner {
    package init(processRunner: any ProcessRunning, workingDirectory: AbsolutePath)

    package func execute(_ command: String) async throws -> (stdout: String, stderr: String)
}
```

**Execution**:
- Command: `/bin/sh -c "user_command"`
- Working directory: Set from context
- Output capture: Both stdout and stderr

**Error handling**: Throw on non-zero exit code

**Design rationale**: Use `/bin/sh` for shell feature support (pipes, variables, etc.). Follows pattern from OpenRunner.swift.

---

### 5. ConditionEvaluator

**Responsibility**: Evaluate conditional expressions (if field)

**Interface**:
```swift
package struct ConditionEvaluator {
    package init(macros: [ResolvedMacro], outputs: StepOutputs)

    package func evaluate(_ condition: String) throws -> Bool
}
```

**Variable resolution in conditions**:

Conditions require type-aware variable expansion:

1. **Macros** (`___MACRO___`):
   - `.string(s)` → `"s"` (quoted)
   - `.boolean(b)` → `true` or `false` (unquoted)
   - `.choice(c)` → `"c"` (quoted)
   - `.array(a)` → `["item1", "item2"]` (JSON array with quoted items)
   - `.path(p)` → `"path"` (quoted)

2. **Step outputs** (`${{ phase.step-id.outputs.key }}`):
   - Always strings from stdout, but type inference is applied for JavaScript evaluation:
     - `"true"` → `true` (boolean, unquoted)
     - `"false"` → `false` (boolean, unquoted)
     - `"item1,item2,item3"` → `["item1", "item2", "item3"]` (JSON array with quoted items)
     - Other strings → `"value"` (quoted)

**Example**:
```yaml
macros:
  - name: ___DEBUG___
    type: boolean
    default: true
  - name: ___PLATFORMS___
    type: array
    default: ["iOS", "macOS"]

pre_hatch:
  - id: setup
    run: |
      echo "ready=true"
      echo "platforms=iOS,macOS,watchOS"

  # Boolean macro - no quotes
  - if: ___DEBUG___ === true
    run: echo "Debug mode"

  # Boolean output - auto-inferred as boolean (no user quotes needed)
  - if: ${{ pre_hatch.setup.outputs.ready }} === true
    run: echo "Ready"

  # Array output - auto-inferred as JSON array from comma-separated string
  - if: ${{ pre_hatch.setup.outputs.platforms }}.includes("iOS")
    run: echo "iOS platform detected"

  # Array macro - JSON array
  - if: ___PLATFORMS___.includes("iOS")
    run: echo "Building for iOS"
```

**Phase 1**: Placeholder - always returns `true`

**Design rationale**: Deferred to allow core functionality to work immediately. Complex feature that can be added later without affecting other components.

---

### 6. LifecycleStepRunner (Phase Executor)

**Responsibility**: Execute steps within a single lifecycle phase

**Interface**:
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
```
1. Check condition
   └─ If false, skip step

2. Resolve variables
   ├─ Create VariableResolver with macros + current outputs
   └─ Resolve step.run command

3. Execute command
   └─ ShellScriptRunner.execute(resolved_command)

4. Parse outputs (if step has id)
   ├─ StepOutputParser.parse(stdout)
   └─ StepOutputsStorage.store(phase, step.id, parsed_outputs)

5. Continue to next step
```

**Design rationale**: Single responsibility - handles execution of steps within one phase only.

---

### 7. LifecycleWorkflowRunner (Workflow Orchestrator)

**Responsibility**: Orchestrate the complete lifecycle workflow (pre_hatch → hatch → post_hatch)

**Interface**:
```swift
struct LifecycleWorkflowRunner {
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

**Workflow execution flow**:
```
1. Initialize outputs storage
   └─ StepOutputsStorage()

2. Execute pre_hatch phase
   ├─ LifecycleStepRunner.executePhase("pre_hatch", ...)
   └─ Update outputs storage

3. Execute hatch (template expansion)
   ├─ TemplateExpander.expand(...)
   └─ Use macros + step outputs for variable resolution

4. Execute post_hatch phase
   ├─ LifecycleStepRunner.executePhase("post_hatch", ...)
   └─ Use outputs from pre_hatch + hatch

5. Return successfully
```

**Design rationale**:
- Separates workflow orchestration from step execution
- HatchRunner delegates to this component instead of managing lifecycle directly
- Clear separation: LifecycleWorkflowRunner (what to run) vs LifecycleStepRunner (how to run)

---

## Data Flow

```
Input:
  ├─ phase: "pre_hatch"
  ├─ steps: [Config.LifecycleStep]
  ├─ macros: [ResolvedMacro]
  └─ existingOutputs: StepOutputs (possibly from previous phase)

Flow:
  Step 1:
    ├─ ConditionEvaluator.evaluate(step.if) → true/false
    ├─ VariableResolver.resolve(step.run)
    ├─ ShellScriptRunner.execute(resolved_command) → (stdout, stderr)
    ├─ StepOutputParser.parse(stdout) → [key: value]
    └─ StepOutputs.store("pre_hatch", step.id, outputs)

  Step 2:
    ├─ VariableResolver now has access to Step 1 outputs
    ├─ Can reference ${{ pre_hatch.step1.outputs.key }}
    └─ (same flow as Step 1)

Output:
  └─ Updated StepOutputs (existingOutputs + new outputs)
```

---

## Cross-Phase Output References

Steps in `post_hatch` can reference outputs from `pre_hatch`:

```yaml
pre_hatch:
  - id: setup
    run: echo "version=1.0.0"

post_hatch:
  - run: echo "Version: ${{ pre_hatch.setup.outputs.version }}"
```

**Mechanism**: `executePhase()` accepts `existingOutputs` parameter, allowing post_hatch phase to access pre_hatch outputs through VariableResolver.

---

## Error Handling

### Error Types:

1. **ShellExecutionError**
   - When: Command exits with non-zero code
   - Contains: command, exit code, stderr

2. **UndefinedOutputReferenceError**
   - When: `${{ phase.step-id.outputs.key }}` not found
   - Contains: phase, stepId, key

3. **ConditionEvaluationError**
   - When: Invalid condition syntax (future)
   - Contains: condition, reason

**Error propagation**: All errors propagate up from component to LifecycleStepRunner, then to caller (HatchRunner).

---

## File Organization

```
Sources/EggKit/
  ├─ LifecycleStepRunner.swift
  └─ Internals/
      ├─ StepOutputs.swift
      ├─ StepOutputParser.swift
      ├─ VariableResolver.swift
      ├─ ShellScriptRunner.swift
      ├─ ConditionEvaluator.swift
      └─ LifecycleErrors.swift
```

**Design rationale**:
- Main orchestrator at top level
- Implementation details in Internals/
- Follows existing project structure

---

## Design Decisions

### Why memory-based storage instead of files?

**Answer**: Simpler, faster, and sufficient for single-process execution. No inter-process communication needed.

### Why stdout parsing for outputs?

**Answer**:
- Simple and intuitive for users
- No special syntax required in shell scripts
- Easy to debug (just echo key=value)
- Familiar pattern (similar to GitHub Actions)

### Why two-pass variable resolution?

**Answer**: Ensures macros are fully resolved before attempting output reference resolution. Prevents ambiguity.

### Why placeholder ConditionEvaluator?

**Answer**:
- Condition evaluation is complex (JavaScript-like expressions)
- Core functionality (step execution, outputs) can work without it
- Can be implemented separately without affecting other components
- Steps without conditions work from day one

### Why separate components instead of monolithic runner?

**Answer**:
- Single responsibility principle
- Each component testable in isolation
- Easy to understand and maintain
- Easy to extend (e.g., add new variable types)

---

## Example

### Input (config.yaml):

```yaml
pre_hatch:
  - id: setup
    run: |
      echo "version=1.0.0"
      echo "name=___PROJECT_NAME___"

  - id: validate
    run: |
      VERSION="${{ pre_hatch.setup.outputs.version }}"
      echo "Checking version: $VERSION"
      echo "valid=true"

  - if: ${{ pre_hatch.validate.outputs.valid }} === "true"
    run: echo "Validation passed"

post_hatch:
  - run: echo "Created ___PROJECT_NAME___ v${{ pre_hatch.setup.outputs.version }}"
```

### Execution:

**Pre-hatch phase:**

Step "setup":
- Input: `echo "version=1.0.0"\necho "name=MyApp"`
- Execute: `/bin/sh -c "..."`
- Stdout: `version=1.0.0\nname=MyApp\n`
- Parse: `{version: "1.0.0", name: "MyApp"}`
- Store: `pre_hatch.setup → {version: "1.0.0", name: "MyApp"}`

Step "validate":
- Resolve: `${{ pre_hatch.setup.outputs.version }}` → `"1.0.0"`
- Input: `VERSION="1.0.0"\necho "Checking version: $VERSION"\necho "valid=true"`
- Stdout: `Checking version: 1.0.0\nvalid=true\n`
- Parse: `{valid: "true"}`
- Store: `pre_hatch.validate → {valid: "true"}`

Step (conditional):
- Condition: `${{ pre_hatch.validate.outputs.valid }} === "true"` → `true` (placeholder always true)
- Execute: `echo "Validation passed"`

**Post-hatch phase:**

Step:
- Resolve: `___PROJECT_NAME___` → `"MyApp"`, `${{ pre_hatch.setup.outputs.version }}` → `"1.0.0"`
- Input: `echo "Created MyApp v1.0.0"`
- Execute: `/bin/sh -c "..."`
