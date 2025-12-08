# LifecycleStepRunner Design Document

## Overview

LifecycleStepRunner is a system for executing pre_hatch and post_hatch lifecycle steps from config.yaml, with support for step outputs, variable substitution, and conditional execution.

## Core Design Principles

1. **Memory-based storage**: Store step outputs in memory (not files)
2. **stdout parsing**: Extract `key=value` outputs from shell script stdout
3. **Separation of concerns**: Each component has a single, well-defined responsibility
4. **Integration with existing code**: Follows project patterns and integrates seamlessly with HatchRunner

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ HatchRunner                                             │
│                                                         │
│  1. Pre-hatch phase                                     │
│     ↓                                                   │
│  LifecycleStepRunner.executePhase("pre_hatch", ...)    │
│     → Returns: StepOutputs                              │
│                                                         │
│  2. Hatch phase (existing logic)                        │
│                                                         │
│  3. Post-hatch phase                                    │
│     ↓                                                   │
│  LifecycleStepRunner.executePhase("post_hatch", ...)   │
│     → Can reference pre_hatch outputs                   │
└─────────────────────────────────────────────────────────┘
```

## Component Design

### 1. StepOutputs (Data Structure)

**Responsibility**: Store and retrieve step outputs across lifecycle execution

**Interface**:
- Store outputs for a step: `(phase, stepId, outputs) -> void`
- Retrieve output value: `(phase, stepId, key) -> String?`
- Check existence: `(phase, stepId, key) -> Bool`

**Storage format**: `"phase.stepId" -> [key: value]`

**Example**:
```
{
  "pre_hatch.setup": {
    "version": "1.0.0",
    "src-dir": "/tmp/src"
  },
  "pre_hatch.validate": {
    "valid": "true"
  }
}
```

### 2. StepOutputParser

**Responsibility**: Parse key-value pairs from shell script stdout

**Input**: stdout string
**Output**: Dictionary of key-value pairs

**Format**: `key=value` (one per line)

**Behavior**:
- Split by newlines
- Parse `key=value` format (split on first `=` only)
- Skip empty lines
- Trim whitespace

### 3. VariableResolver

**Responsibility**: Replace variables (macros and step outputs) in strings

**Input**:
- Text with variables
- Macros dictionary
- StepOutputs

**Output**: Text with variables replaced

**Handles two types**:
1. Macros: `___MACRO_NAME___` → value from macros dict
2. Step outputs: `${{ phase.step-id.outputs.key }}` → value from StepOutputs

**Behavior**:
- First pass: Replace macros (simple string replacement)
- Second pass: Replace step outputs (regex pattern matching)
- Throw error if undefined reference found

### 4. ShellScriptRunner

**Responsibility**: Execute shell commands and capture output

**Input**: Shell command string
**Output**: (stdout, stderr)

**Execution**: `/bin/sh -c "command"`

**Behavior**:
- Execute using ProcessRunning
- Capture stdout and stderr
- Set working directory
- Throw error on non-zero exit code

### 5. ConditionEvaluator

**Responsibility**: Evaluate conditional expressions (if field)

**Input**: Condition string
**Output**: Boolean (true/false)

**Phase 1 implementation**: Always return `true` (placeholder)

**Future**: Implement JavaScript-like expression evaluation

### 6. LifecycleStepRunner (Main Orchestrator)

**Responsibility**: Orchestrate execution of lifecycle phases

**Key methods**:
- `executePhase(phase, steps, macros, existingOutputs) -> StepOutputs`
- `executeStep(step, phase, resolver, evaluator) -> outputs?`

**Execution flow per step**:
```
1. Evaluate condition (if present)
   └─ Skip step if false

2. Resolve variables in run command
   ├─ Replace macros
   └─ Replace step outputs

3. Execute shell script
   └─ Capture stdout/stderr

4. Parse outputs (if step has id)
   ├─ Parse stdout for key=value
   └─ Store in StepOutputs

5. Return updated StepOutputs
```

## Data Flow

```
HatchRunner
    ↓
  macros: [String: String]
    ↓
LifecycleStepRunner.executePhase("pre_hatch", steps, macros, StepOutputs())
    ↓
  For each step:
    ↓
  VariableResolver.resolve(step.run)
    ├─ macros
    └─ StepOutputs (accumulated)
    ↓
  ShellScriptRunner.execute(resolvedCommand)
    ↓
  stdout/stderr
    ↓
  StepOutputParser.parse(stdout)
    ↓
  [key: value]
    ↓
  StepOutputs.store("pre_hatch", step.id, outputs)
    ↓
  Updated StepOutputs
    ↓
Return StepOutputs to HatchRunner
    ↓
(Hatch phase executes)
    ↓
LifecycleStepRunner.executePhase("post_hatch", steps, macros, previousOutputs)
    ↓
  (Can reference pre_hatch outputs)
```

## Integration Points

### HatchRunner Modifications

**Before**:
```
1. Validate arguments
2. Resolve macros
3. Copy template files
4. Substitute macros in files
```

**After**:
```
1. Validate arguments
2. Resolve macros
3. Execute pre_hatch → StepOutputs
4. Copy template files
5. Substitute macros in files
6. Execute post_hatch (with StepOutputs from pre_hatch)
```

### Required Changes:
- Add `LifecycleStepRunner` as property
- Call `executePhase()` before and after hatching
- Thread `StepOutputs` between phases

## Error Handling

### Error Categories:

1. **Shell execution errors**
   - Non-zero exit code
   - Include: command, exit code, stderr

2. **Variable resolution errors**
   - Undefined output reference
   - Include: phase, stepId, key

3. **Condition evaluation errors** (future)
   - Invalid condition syntax
   - Include: condition, reason

4. **Output parsing errors** (optional)
   - Invalid format
   - Include: offending line

## File Organization

### New Files:

```
Sources/EggKit/
  ├─ LifecycleStepRunner.swift          (Main orchestrator)
  └─ Internals/
      ├─ StepOutputs.swift               (Data structure)
      ├─ StepOutputParser.swift          (Parser)
      ├─ VariableResolver.swift          (Variable substitution)
      ├─ ShellScriptRunner.swift         (Shell execution)
      ├─ ConditionEvaluator.swift        (Condition eval)
      └─ LifecycleErrors.swift           (Error types)
```

### Modified Files:

```
Sources/EggKit/
  └─ HatchRunner.swift                   (Integration point)
```

## Testing Strategy

### Unit Tests:

1. **StepOutputParser**: Parse various stdout formats
2. **VariableResolver**: Replace macros and outputs
3. **ShellScriptRunner**: Execute commands, capture output
4. **StepOutputs**: Store and retrieve operations
5. **LifecycleStepRunner**: Step execution, phase execution

### Integration Tests:

1. Full lifecycle execution (pre_hatch → hatch → post_hatch)
2. Cross-phase output references
3. Conditional execution
4. Error cases

### Test Fixtures:

YAML files with various lifecycle configurations:
- Simple steps
- Steps with outputs
- Conditional steps
- Cross-reference scenarios

## Example Workflow

### Input (config.yaml):

```yaml
pre_hatch:
  - id: setup
    run: |
      echo "version=1.0.0"
      echo "src-dir=./Sources/___PROJECT_NAME___"

  - id: validate
    run: |
      echo "Checking: ${{ pre_hatch.setup.outputs.version }}"
      echo "valid=true"

  - if: ${{ pre_hatch.validate.outputs.valid }} === "true"
    run: echo "Validated!"

post_hatch:
  - run: echo "Created: ${{ pre_hatch.setup.outputs.src-dir }}"
```

### Execution Trace:

```
1. Pre-hatch phase:
   Step "setup":
     Input:  "echo \"version=1.0.0\"\necho \"src-dir=./Sources/MyApp\""
     Output: {version: "1.0.0", src-dir: "./Sources/MyApp"}
     Store:  pre_hatch.setup → outputs

   Step "validate":
     Resolve: "${{ pre_hatch.setup.outputs.version }}" → "1.0.0"
     Input:   "echo \"Checking: 1.0.0\"\necho \"valid=true\""
     Output:  {valid: "true"}
     Store:   pre_hatch.validate → outputs

   Step (conditional):
     Condition: "${{ pre_hatch.validate.outputs.valid }} === \"true\"" → true
     Input:     "echo \"Validated!\""
     Output:    (no id, outputs not stored)

2. Hatch phase:
   (Existing template copying logic)

3. Post-hatch phase:
   Step:
     Resolve: "${{ pre_hatch.setup.outputs.src-dir }}" → "./Sources/MyApp"
     Input:   "echo \"Created: ./Sources/MyApp\""
     Output:  (no id, outputs not stored)
```

## Design Decisions

### Why memory-based storage?

- Simpler than file-based
- Faster (no disk I/O)
- Sufficient for single-process execution
- No cleanup needed

### Why stdout parsing for outputs?

- Simple and intuitive
- Familiar pattern (GitHub Actions uses similar approach)
- No special syntax needed in shell scripts
- Easy to debug

### Why separate VariableResolver?

- Single responsibility
- Testable in isolation
- Reusable for other contexts (e.g., condition evaluation)

### Why placeholder ConditionEvaluator?

- Allows core functionality to work immediately
- Condition evaluation is complex and can be added later
- Steps without conditions work from day one

## Future Enhancements

### Phase 2: Full Condition Evaluation

Implement JavaScript-like expression evaluation:
- Boolean operators: `&&`, `||`, `!`
- Comparison: `===`, `!==`, `>`, `<`
- Array methods: `.includes()`
- String methods: `.startsWith()`, `.endsWith()`

Options:
- JavaScriptCore (macOS/iOS built-in)
- Custom expression parser
- Swift Expression library

### Phase 3: Enhanced Error Reporting

- Line numbers for failures
- Suggest fixes for common errors
- Better error messages for undefined references

### Phase 4: Dry-run Mode

- Preview what would be executed
- Show resolved variables
- Don't actually execute commands

## Success Criteria

1. All lifecycle steps execute in correct order
2. Step outputs are captured and accessible
3. Variable resolution works for both macros and outputs
4. Cross-phase output references work
5. Conditional execution works (with placeholder)
6. Shell scripts execute correctly
7. Errors are handled and reported clearly
8. Integration with HatchRunner is seamless
9. Code follows project conventions
10. All tests pass
