# Array Validation Implementation Plan

## Overview

Add validation support to array type macros, allowing regex pattern validation for each array element. Currently, `validate` field only works with `string` type macros.

## Current State Analysis

### Validation Architecture

The validation system operates at three levels:

1. **Config-time validation** (`ConfigValidator+MacrosValidator.swift`)
   - Validates that config.yaml is well-formed
   - Currently checks that `validate` field is only used with `string` type (line 286-293)
   - Validates regex patterns are syntactically correct
   - Checks field compatibility between types

2. **Runtime validation** (`ParsedMacroDefinitionValidator.swift`)
   - Validates user input values
   - Currently applies regex validation only to string types (line 188-214)
   - Uses `RegexPatternValidationRule` from Noora library
   - **Key Finding**: Already loops through all values in `resolvedValues` array (line 204-212), so will automatically validate array elements once restriction is removed!

3. **Interactive input validation** (`MacroResolver.swift`)
   - String type prompts use `RegexPatternValidationRule` directly (line 67-86)
   - Array type prompts have NO validation currently (line 144-157)

### Key Finding

The validation infrastructure is already in place! The `validateRegex` method in `ParsedMacroDefinitionValidator.swift` already loops through all values:

```swift
for value in resolvedValues {
    if !validationRule.validate(input: value) {
        return .valueDoesNotMatchRegex(
            macro: macroName,
            value: value,
            pattern: regexPattern
        )
    }
}
```

This means array elements will automatically be validated once we remove the type restriction!

## Implementation Phases

### Phase 1: Update Documentation (Optional, for reference only)

**File:** `docs/design/CONFIG_YAML.md`

Update documentation to reflect that `validate` will work with both `string` and `array` types.

**Changes:**
- Line 20: Change "string型のみ, 正規表現" to "string/array型, 正規表現"
- Line 240: Update the compatibility table to allow `validate` for array type

**Note:** This phase is documentation-only and doesn't affect code implementation.

### Phase 2: Remove Field Compatibility Restriction ⭐️ Core Change

**Estimated time:** 5 minutes

**File 1:** `Sources/EggKit/Config/ConfigValidator+MacrosValidator.swift`

**Change:** Update `validateValidateFieldCompatibility` method (line 286-293)

```swift
// FROM:
if macro.type != .string {
    return [.validateOnlyValidForStringType(context: context, name: macro.name)]
}

// TO:
let validTypes: Set<Config.MacroType> = [.string, .array]
if !validTypes.contains(macro.type) {
    return [.validateOnlyValidForStringAndArrayTypes(context: context, name: macro.name)]
}
```

**File 2:** `Sources/EggKit/Config/Config+Error.swift`

**Change:** Update error enum

```swift
// Add new case (replace validateOnlyValidForStringType):
case validateOnlyValidForStringAndArrayTypes(context: String, name: String)

// Update errorDescription:
case let .validateOnlyValidForStringAndArrayTypes(context, name):
    "\(context): Macro '\(name)' has 'validate' field, which is only valid for 'string' and 'array' types."
```

**Testing:**
- Run existing tests to ensure no breakage
- ConfigValidatorArrayFormatTests should still pass (we'll add new test cases in Phase 5)

### Phase 3: Verify Runtime Validation (Already Works!) ✅

**Estimated time:** 2 minutes

**File:** `Sources/EggKit/Internals/ParsedMacroDefinitionValidator.swift`

**Action:** No code changes needed!

The existing `validateRegex` method (line 188-214) already handles arrays correctly because it loops through all values in `resolvedValues`. Once Phase 2 is complete, this will automatically validate array elements.

**Verification:**
- Read through the code to confirm the logic is correct
- The guard statement at line 189 checks for regex pattern existence
- The loop at line 204-212 validates each value
- This works for both single strings and array elements!

### Phase 4: Add Interactive Validation for Array Input

**Estimated time:** 20 minutes

#### Step 4.1: Create ArrayElementValidationRule

**New File:** `Sources/EggKit/Noora/ArrayElementValidationRule.swift`

```swift
import Foundation
import Noora

/// Validates that each element in a comma-separated array matches a regex pattern.
package struct ArrayElementValidationRule: ValidatableRule {
    package let error: any ValidatableError
    private let elementPattern: String

    package init(elementPattern: String, error: String) {
        self.elementPattern = elementPattern
        self.error = error
    }

    package func validate(input: String) -> Bool {
        let parser = ArrayInputParser()
        let elements = parser.parseFromInteractive(input)

        guard let regex = try? NSRegularExpression(pattern: elementPattern) else {
            return false
        }

        for element in elements {
            let range = NSRange(element.startIndex..., in: element)
            guard regex.firstMatch(in: element, range: range) != nil else {
                return false
            }
        }

        return true
    }
}
```

#### Step 4.2: Update MacroResolver

**File:** `Sources/EggKit/Internals/MacroResolver.swift`

**Change:** Update `promptForArray` method (line 144-157)

```swift
// FROM:
private func promptForArray(_ macro: Config.Macro) -> ResolvedMacro {
    let input = noora.textPrompt(
        title: "\(macro.name)",
        prompt: "\(macro.description) (comma-separated)",
        collapseOnAnswer: true,
        validationRules: []  // ← Empty validation rules
    )
    let values = ArrayInputParser().parseFromInteractive(input)

    return ResolvedMacro(
        name: macro.name,
        description: macro.description,
        value: .array(values, format: macro.format)
    )
}

// TO:
private func promptForArray(_ macro: Config.Macro) -> ResolvedMacro {
    // Build validation rules for array elements
    var validationRules: [any ValidatableRule] = []

    if let validatePattern = macro.validate {
        // Create a custom validation rule that validates each comma-separated element
        validationRules.append(
            ArrayElementValidationRule(
                elementPattern: validatePattern,
                error: "One or more values do not match the required pattern: '\(validatePattern)'"
            )
        )
    }

    let input = noora.textPrompt(
        title: "\(macro.name)",
        prompt: "\(macro.description) (comma-separated)",
        collapseOnAnswer: true,
        validationRules: validationRules
    )
    let values = ArrayInputParser().parseFromInteractive(input)

    return ResolvedMacro(
        name: macro.name,
        description: macro.description,
        value: .array(values, format: macro.format)
    )
}
```

### Phase 5: Comprehensive Testing

**Estimated time:** 30 minutes

#### Test 5.1: Config Validation Tests

**File:** `Tests/EggKitTests/Config/ConfigValidatorArrayFormatTests.swift`

Add test cases around line 393 (after the existing "passes with validate on string type" test):

```swift
TestCase(
    description: "passes with validate on array type",
    config: makeConfig(
        macros: [
            Config.Macro(
                name: "___MODULES___",
                description: "Modules",
                type: .array,
                default: #"["ModuleA", "ModuleB"]"#,
                validate: "^[A-Z][a-zA-Z0-9]*$"
            ),
        ]
    ),
    expected: .success
),
TestCase(
    description: "fails with validate on choice type (still invalid)",
    config: makeConfig(
        macros: [
            Config.Macro(
                name: "___TYPE___",
                description: "Type",
                type: .choice,
                default: "a",
                validate: "^[a-z]$",
                choices: ["a", "b"]
            ),
        ]
    ),
    expected: .failure([
        .validateOnlyValidForStringAndArrayTypes(context: "macros[0]", name: "___TYPE___"),
    ])
),
```

#### Test 5.2: Runtime Validation Tests

**File:** `Tests/EggKitTests/ParsedMacroDefinitionValidatorTests.swift`

Add test cases after line 377:

```swift
TestCase(
    description: "validates array elements with regex pattern",
    config: Config(
        name: "Test",
        description: "Test",
        macros: [
            Config.Macro(
                name: "___MODULES___",
                description: "Modules",
                type: .array,
                validate: "^[A-Z][a-zA-Z0-9]*$"
            ),
        ],
        hatch: Config.HatchConfig(output: ".")
    ),
    parsedMacros: [
        ParsedMacroDefinition(macro: "___MODULES___", values: ["ModuleA", "ModuleB", "ModuleC"]),
    ],
    expected: .success([
        ResolvedMacro(
            name: "___MODULES___",
            description: "Modules",
            value: .array(["ModuleA", "ModuleB", "ModuleC"], format: nil)
        ),
    ])
),
TestCase(
    description: "fails when one array element does not match regex pattern",
    config: Config(
        name: "Test",
        description: "Test",
        macros: [
            Config.Macro(
                name: "___MODULES___",
                description: "Modules",
                type: .array,
                validate: "^[A-Z][a-zA-Z0-9]*$"
            ),
        ],
        hatch: Config.HatchConfig(output: ".")
    ),
    parsedMacros: [
        ParsedMacroDefinition(macro: "___MODULES___", values: ["ModuleA", "invalid-module", "ModuleC"]),
    ],
    expected: .failure([
        .valueDoesNotMatchRegex(
            macro: "___MODULES___",
            value: "invalid-module",
            pattern: "^[A-Z][a-zA-Z0-9]*$"
        ),
    ])
),
TestCase(
    description: "validates array with default value against regex",
    config: Config(
        name: "Test",
        description: "Test",
        macros: [
            Config.Macro(
                name: "___MODULES___",
                description: "Modules",
                type: .array,
                default: #"["ModuleA", "ModuleB"]"#,
                validate: "^[A-Z][a-zA-Z0-9]*$"
            ),
        ],
        hatch: Config.HatchConfig(output: ".")
    ),
    parsedMacros: [],
    expected: .success([
        ResolvedMacro(
            name: "___MODULES___",
            description: "Modules",
            value: .array(["ModuleA", "ModuleB"], format: nil)
        ),
    ])
),
```

#### Test 5.3: ArrayElementValidationRule Tests

**New File:** `Tests/EggKitTests/Noora/ArrayElementValidationRuleTests.swift`

```swift
@testable import EggKit
import Testing

struct ArrayElementValidationRuleTests {
    @Test(arguments: TestCase.allCases)
    func validate(_ testCase: TestCase) {
        let rule = ArrayElementValidationRule(
            elementPattern: testCase.pattern,
            error: "Test error"
        )
        let result = rule.validate(input: testCase.input)
        #expect(result == testCase.expected)
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let pattern: String
        let input: String
        let expected: Bool

        var testDescription: String { description }

        static let allCases: [TestCase] = [
            TestCase(
                description: "validates all elements match pattern",
                pattern: "^[A-Z][a-zA-Z0-9]*$",
                input: "ModuleA, ModuleB, ModuleC",
                expected: true
            ),
            TestCase(
                description: "fails when one element does not match",
                pattern: "^[A-Z][a-zA-Z0-9]*$",
                input: "ModuleA, invalid-name, ModuleC",
                expected: false
            ),
            TestCase(
                description: "validates empty array",
                pattern: "^[A-Z][a-zA-Z0-9]*$",
                input: "",
                expected: true
            ),
            TestCase(
                description: "validates single element",
                pattern: "^[A-Z][a-zA-Z0-9]*$",
                input: "ValidModule",
                expected: true
            ),
            TestCase(
                description: "handles whitespace correctly",
                pattern: "^[A-Z][a-zA-Z0-9]*$",
                input: "  ModuleA  ,  ModuleB  ",
                expected: true
            ),
        ]
    }
}
```

### Phase 6: Update Documentation

**Estimated time:** 10 minutes

**File:** `docs/design/CONFIG_YAML.md`

#### Change 1: Update line 20 (macro fields table)

```yaml
# FROM:
validate: String (string型のみ, 正規表現)

# TO:
validate: String (string/array型, 正規表現。arrayの場合は各要素に適用)
```

#### Change 2: Update line 240-247 (compatibility table)

```markdown
| フィールド | 使用可能な型 | 備考 |
|-----------|--------------|------|
| `validate` | `string`, `array` | 正規表現。arrayの場合は各要素に対してバリデーション。その他の型では使用不可。 |
| `choices` | `choice`, `choices` | `choice`/`choices` では必須。それ以外の型（array を含む）では使用不可。 |
| `format` | `array` | JavaScript式。その他の型で指定するとエラー。 |
```

#### Change 3: Add example around line 150-233 (array type section)

After the existing array examples, add:

```yaml
# 配列要素のバリデーション（正規表現）
- name: ___MODULE_NAMES___
  type: array
  description: "モジュール名（PascalCaseのみ許可）"
  validate: "^[A-Z][a-zA-Z0-9]*$"
  default: ["NetworkClient", "DataManager"]
  format: '$elements.map(x => `"${x}"`).join(", ")'
  # 入力例: NetworkClient, DataManager, APIClient
  # バリデーション: 各要素が ^[A-Z][a-zA-Z0-9]*$ にマッチすること
  # 出力: "NetworkClient", "DataManager", "APIClient"

# パッケージ名のバリデーション
- name: ___PACKAGES___
  type: array
  description: "パッケージ名（小文字とハイフンのみ）"
  validate: "^[a-z][a-z0-9-]*$"
  format: '$elements.map(x => `.package(name: "${x}")`).join(",\\n        ")'
  # 無効な入力例: Package_Name, PACKAGE, 123package
  # 有効な入力例: package-name, mypackage, swift-tools
```

## Implementation Sequence

### Recommended Order

1. ✅ **Phase 1** (Optional) - Update documentation (10 minutes)
   - Update CONFIG_YAML.md to reflect new specification
   - Can be done first or last

2. 🔴 **Phase 2** - Remove restriction in ConfigValidator (5 minutes)
   - Modify `validateValidateFieldCompatibility` method
   - Update error case definition
   - **This is the core change!**
   - Run existing tests to ensure no breakage

3. ✅ **Phase 3** - Verify runtime validation (2 minutes)
   - Review the existing code to confirm it works
   - No code changes needed!

4. 🟡 **Phase 4** - Add interactive validation (20 minutes)
   - Create `ArrayElementValidationRule.swift`
   - Modify `promptForArray` in MacroResolver
   - Test manually with interactive prompts

5. 🟢 **Phase 5** - Add comprehensive tests (30 minutes)
   - Update ConfigValidatorArrayFormatTests
   - Update ParsedMacroDefinitionValidatorTests
   - Create ArrayElementValidationRuleTests
   - Run all tests and ensure they pass

6. 📝 **Phase 6** - Final documentation update (10 minutes)
   - Add usage examples
   - Update field compatibility table
   - Add notes about validation behavior

**Total estimated time: ~1 hour 17 minutes**

## Testing Strategy

### Unit Tests

- ✅ Config validation accepts array + validate combination
- ✅ Config validation rejects validate on boolean/choice/choices/path
- ✅ ParsedMacroDefinitionValidator validates each array element
- ✅ ParsedMacroDefinitionValidator fails on first invalid element
- ✅ ArrayElementValidationRule validates comma-separated input
- ✅ Default array values are validated

### Integration Tests

- ✅ Interactive prompt with array validation
- ✅ CLI argument parsing with array validation
- ✅ Error messages are clear and helpful

### Edge Cases

- ✅ Empty array (should pass validation)
- ✅ Single element array
- ✅ Whitespace handling in array elements
- ✅ Invalid regex pattern (should fail at config validation time)
- ✅ Mix of valid and invalid elements (should fail on first invalid)

## Critical Files

### Files to Modify

1. `Sources/EggKit/Config/ConfigValidator+MacrosValidator.swift` - Remove type restriction (Phase 2)
2. `Sources/EggKit/Config/Config+Error.swift` - Update error case (Phase 2)
3. `Sources/EggKit/Internals/MacroResolver.swift` - Add interactive validation (Phase 4)
4. `Sources/EggKit/Noora/ArrayElementValidationRule.swift` - New validation rule (Phase 4, to be created)
5. `docs/design/CONFIG_YAML.md` - Update specification (Phase 6)

### Test Files to Modify

1. `Tests/EggKitTests/Config/ConfigValidatorArrayFormatTests.swift` - Add config validation tests (Phase 5)
2. `Tests/EggKitTests/ParsedMacroDefinitionValidatorTests.swift` - Add runtime validation tests (Phase 5)
3. `Tests/EggKitTests/Noora/ArrayElementValidationRuleTests.swift` - Create new test file (Phase 5)

### Files Already Supporting the Feature (No Changes Needed)

1. `Sources/EggKit/Config/Config.swift` - Already has `validate` field in Macro struct ✅
2. `Sources/EggKit/Internals/ParsedMacroDefinitionValidator.swift` - Already validates all values in array ✅

## Success Criteria

- ✅ Array type macros can have `validate` field in config.yaml
- ✅ ConfigValidator accepts array + validate combination
- ✅ Each array element is validated against the regex pattern
- ✅ Interactive prompts validate array input in real-time
- ✅ CLI arguments validate array input
- ✅ Clear error messages when validation fails
- ✅ All existing tests continue to pass
- ✅ New tests cover all edge cases
- ✅ Documentation is updated and accurate

## Example Usage

### config.yaml

```yaml
name: Swift Module Generator
description: Create Swift modules with validated names

macros:
  - name: ___MODULE_NAMES___
    description: "Module names (PascalCase only)"
    type: array
    validate: "^[A-Z][a-zA-Z0-9]*$"
    format: '$elements.map(x => `"${x}"`).join(", ")'
    default: ["NetworkClient", "DataManager"]

  - name: ___PACKAGE_NAMES___
    description: "Package names (lowercase with hyphens)"
    type: array
    validate: "^[a-z][a-z0-9-]*$"
    format: '$elements.map(x => `.package(name: "${x}")`).join(",\\n")'

hatch:
  output: "./output"
```

### CLI Usage

```bash
# Valid input
egg hatch MyTemplate --module-names NetworkClient DataManager APIClient

# Invalid input (will fail validation)
egg hatch MyTemplate --module-names invalid-name BadName_123
# Error: Value 'invalid-name' does not match regex pattern '^[A-Z][a-zA-Z0-9]*$'

# Interactive mode with validation
egg hatch MyTemplate
# Prompt: Module names (PascalCase only) (comma-separated): NetworkClient, invalid-name
# Error: One or more values do not match the required pattern: '^[A-Z][a-zA-Z0-9]*$'
# Prompt: Module names (PascalCase only) (comma-separated): NetworkClient, DataManager
# Success!
```

## Potential Issues & Solutions

### Issue 1: Empty array validation

**Problem:** Should an empty array pass validation?

**Solution:** Yes, empty arrays should pass validation. The validation rule only applies to elements that exist. This matches the behavior of other validation systems.

### Issue 2: Whitespace in array elements

**Problem:** Should whitespace around elements be trimmed before validation?

**Solution:** Yes, `ArrayInputParser` already trims whitespace (need to verify this). The validation should apply to the trimmed values.

### Issue 3: Invalid regex pattern

**Problem:** What happens if the regex pattern itself is invalid?

**Solution:** This is already handled by `ConfigValidator+MacrosValidator.swift` at line 299-313. Invalid regex patterns cause config validation to fail, preventing the template from loading.

### Issue 4: Performance with large arrays

**Problem:** Will validating each element in a large array be slow?

**Solution:** Regex matching is fast enough for typical use cases (< 100 elements). If this becomes an issue, we can add early termination after first failure (already implemented in `validateRegex` method).

## Future Enhancements

### Possible Future Features (Out of Scope)

1. **Custom validation functions**: Allow JavaScript functions instead of just regex
   ```yaml
   validate: "x => x.length > 3 && x.includes('Module')"
   ```

2. **Different validation per element**: Allow different patterns for different positions
   ```yaml
   validate: ["^[A-Z].*", ".*Client$", ".*Manager$"]
   ```

3. **Cross-field validation**: Validate array elements based on other macro values
   ```yaml
   validate: "___MODULE_TYPE___ === 'library' ? '^[A-Z].*' : '.*'"
   ```

These are not part of the current implementation plan but could be considered for future versions.

## References

- Config model: `Sources/EggKit/Config/Config.swift`
- Config validation: `Sources/EggKit/Config/ConfigValidator+MacrosValidator.swift`
- Runtime validation: `Sources/EggKit/Internals/ParsedMacroDefinitionValidator.swift`
- Interactive input: `Sources/EggKit/Internals/MacroResolver.swift`
- Documentation: `docs/design/CONFIG_YAML.md`
