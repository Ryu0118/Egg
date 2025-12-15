# Array Type Macro Feature Design

## 概要

`array` 型マクロのJavaScript式による出力フォーマット機能の設計ドキュメント。

## 型の分離

### `choice` vs `choices` vs `array`

| 型 | 用途 | 選択肢 | 入力方式 |
|----|------|--------|---------|
| `choice` | 単一選択 | `choices` 必須 | ラジオボタン形式 |
| `choices` | 複数選択 | `choices` 必須 | チェックボックス形式 |
| `array` | 自由入力配列 | なし | テキスト入力（カンマ区切り） |

- `choices` 型: ユーザーが定義済みの選択肢から複数を選ぶ（例: プラットフォーム選択）
- `array` 型: ユーザーが自由に複数の値を入力する（例: 依存パッケージ名）。`format` フィールドでJavaScript式による出力フォーマットが可能。

## 現状分析

### 既存インフラ

| コンポーネント | ファイル | 状態 |
|-------------|--------|------|
| `Config.MacroType.array` | `Config.swift` | 存在 |
| `Config.MacroType.choices` | `Config.swift` | 存在（複数選択用） |
| `ResolvedMacro.Value.array` | `ResolvedMacro.swift` | 存在（自由入力用） |
| `ResolvedMacro.Value.choices` | `ResolvedMacro.swift` | 存在（複数選択用） |
| `JSEvaluator` | `JSEvaluator.swift` | 存在（汎用JS評価器） |
| `MacroStringConverter` | `MacroStringConverter.swift` | 実装済み |
| `MacroResolver.promptForArray` | `MacroResolver.swift` | 自由入力対応 |
| `MacroResolver.promptForChoices` | `MacroResolver.swift` | 複数選択対応 |

---

## 新規型定義

### ArrayFormatEvaluating

**File:** `Sources/EggKit/WorkflowRunner/ArrayFormatEvaluating.swift`

```swift
/// 配列マクロ値のJavaScriptフォーマット式を評価する。
protocol ArrayFormatEvaluating: Sendable {
    /// フォーマット式を配列値に対して評価する。
    ///
    /// - Parameters:
    ///   - format: `$elements`で配列を参照するJavaScript式
    ///   - values: フォーマット対象の配列値
    /// - Returns: フォーマット済み文字列
    /// - Throws: 評価失敗時に`ArrayFormatError`
    func evaluate(format: String, values: [String]) throws -> String
}
```

---

### ArrayFormatEvaluator

**File:** `Sources/EggKit/WorkflowRunner/ArrayFormatEvaluator.swift`

```swift
/// JSEvaluatorを使用したArrayFormatEvaluatingの実装。
struct ArrayFormatEvaluator: ArrayFormatEvaluating {
    /// フォーマット未指定時のデフォルト式
    static let defaultFormat: String = #"$elements.join(", ")"#

    private let jsEvaluator: JSEvaluator

    init(jsEvaluator: JSEvaluator = JSEvaluator())

    func evaluate(format: String, values: [String]) throws -> String
}
```

---

### ArrayFormatError

**File:** `Sources/EggKit/WorkflowRunner/ArrayFormatError.swift`

```swift
/// 配列フォーマット評価時に発生するエラー。
enum ArrayFormatError: LocalizedError, Equatable {
    /// JavaScript評価がnullまたはundefinedを返した
    case evaluationFailed(format: String)

    /// JavaScript評価が文字列以外を返した
    case nonStringResult(format: String, actualType: String)

    var errorDescription: String? { ... }
}
```

---

### ArrayInputParser

**File:** `Sources/EggKit/Internals/ArrayInputParser.swift`

```swift
/// 各種入力ソースからの配列入力を正規化する。
struct ArrayInputParser: Sendable {
    /// CLI引数をパースする（MacrosParserで分割済み）。
    func parseFromCLI(_ values: [String]) -> [String]

    /// 対話モード入力をパースする（カンマ区切り文字列）。
    func parseFromInteractive(_ input: String) -> [String]
}
```

---

## 既存型の修正

### Config.Macro

**File:** `Sources/EggKit/Config/Config.swift`

```swift
package struct Macro: Codable, Equatable, Sendable {
    package let name: String
    package let description: String?
    package let type: MacroType
    package let `default`: MacroDefaultValue?
    package let validate: String?
    package let choices: [String]?

    /// array型専用のJavaScriptフォーマット式。
    ///
    /// `$elements`で入力配列を参照。JavaScriptCoreで評価される。
    /// デフォルト: `$elements.join(", ")`
    package let format: String?  // 追加
}
```

---

### ResolvedMacro.Value

**File:** `Sources/EggKit/Models/ResolvedMacro.swift`

```swift
package enum Value: Equatable, Sendable {
    case string(String)
    case boolean(Bool)
    /// 単一選択
    case choice(String)
    /// 複数選択（定義済み選択肢から）
    case choices([String])
    /// 自由入力配列（formatでJavaScript式による出力フォーマット可能）
    case array([String], format: String?)
    case path(URL)
}
```

---

### MacroStringConverter

**File:** `Sources/EggKit/Internals/MacroStringConverter.swift`

```swift
enum MacroStringConverter {
    /// 配列をフォーマット式でシェル文字列に変換する。
    static func toFormattedShellString(
        _ values: [String],
        format: String,
        evaluator: some ArrayFormatEvaluating
    ) throws -> String
}
```

---

### MacroResolver

**File:** `Sources/EggKit/Internals/MacroResolver.swift`

```swift
// promptForChoices: 定義済み選択肢から複数選択
private func promptForChoices(_ macro: Config.Macro) -> ResolvedMacro {
    // multipleChoicePromptを使用
    // ResolvedMacro.Value.choices を返す
}

// promptForArray: 自由入力配列
private func promptForArray(_ macro: Config.Macro) -> ResolvedMacro {
    // textPromptでカンマ区切り入力を受け付け
    // ArrayInputParser.parseFromInteractiveで変換
    // ResolvedMacro.Value.array を返す
}
```

---

### VariableResolver

**File:** `Sources/EggKit/WorkflowRunner/VariableResolver.swift`

```swift
// resolveMacrosの変更
private func resolveMacros(_ text: String) -> String {
    // array型の場合: ArrayFormatEvaluatorでフォーマットを適用
    // 依存注入: ArrayFormatEvaluating
}
```

---

### ConfigValidator.MacrosValidator

**File:** `Sources/EggKit/Config/ConfigValidator+MacrosValidator.swift`

```swift
private func validateArrayType(_ macro: Config.Macro, context: String) -> [Error] {
    // 既存のバリデーション...
    // 追加: format式の構文検証（指定時のみ）
}
```

---

## データフロー

```
CLI入力                      対話モード入力
    |                              |
    v                              v
MacrosParser              ArrayInputParser
    |                              |
    +--------> [String] <----------+
                  |
                  v
        ParsedMacroDefinition
                  |
                  v
     ParsedMacroDefinitionValidator
                  |
                  v
           ResolvedMacro.Value.array([String], format: String)
                  |
                  v
    +-------------+-------------+
    |                           |
    v                           v
VariableResolver        ConditionEvaluator
    |                           |
    v                           v
ArrayFormatEvaluator      JSEvaluator
    |
    v
フォーマット済み文字列
```

---

## テストケース

### ArrayFormatEvaluatorTests

**File:** `Tests/EggKitTests/WorkflowRunner/ArrayFormatEvaluatorTests.swift`

```swift
@testable import EggKit
import Testing

struct ArrayFormatEvaluatorTests {
    let evaluator = ArrayFormatEvaluator()

    @Test(arguments: EvaluateTestCase.allCases)
    func evaluate(_ testCase: EvaluateTestCase) throws {
        switch testCase.expected {
        case let .success(expectedResult):
            let result = try evaluator.evaluate(format: testCase.format, values: testCase.values)
            #expect(result == expectedResult)
        case let .failure(expectedError):
            #expect(throws: expectedError) {
                _ = try evaluator.evaluate(format: testCase.format, values: testCase.values)
            }
        }
    }

    struct EvaluateTestCase: CustomTestStringConvertible {
        let description: String
        let format: String
        let values: [String]
        let expected: Result

        var testDescription: String { description }

        enum Result {
            case success(String)
            case failure(ArrayFormatError)
        }

        static let allCases: [EvaluateTestCase] = [
            // 基本フォーマット
            EvaluateTestCase(
                description: "joins array with default separator",
                format: #"$elements.join(", ")"#,
                values: ["iOS", "macOS", "watchOS"],
                expected: .success("iOS, macOS, watchOS")
            ),
            EvaluateTestCase(
                description: "maps and joins with dot prefix",
                format: #"$elements.map(x => `.${x}`).join(", ")"#,
                values: ["iOS", "macOS"],
                expected: .success(".iOS, .macOS")
            ),
            EvaluateTestCase(
                description: "creates JSON array format",
                format: #""[" + $elements.map(x => `"${x}"`).join(", ") + "]""#,
                values: ["swift", "template"],
                expected: .success(#"["swift", "template"]"#)
            ),
            EvaluateTestCase(
                description: "joins with newline for import statements",
                format: #"$elements.map(x => `import ${x}`).join("\n")"#,
                values: ["Foundation", "UIKit"],
                expected: .success("import Foundation\nimport UIKit")
            ),
            EvaluateTestCase(
                description: "creates SPM package declarations",
                format: #"$elements.map(x => `.package(name: "${x}")`).join(",\n")"#,
                values: ["Alamofire", "SwiftyJSON"],
                expected: .success(".package(name: \"Alamofire\"),\n.package(name: \"SwiftyJSON\")")
            ),
            EvaluateTestCase(
                description: "transforms with regex to kebab-case",
                format: #"$elements.map(x => x.replace(/([A-Z])/g, "-$1").toLowerCase().slice(1)).join(", ")"#,
                values: ["MyModule", "NetworkClient"],
                expected: .success("my-module, network-client")
            ),

            // エッジケース
            EvaluateTestCase(
                description: "returns empty string for empty array",
                format: #"$elements.join(", ")"#,
                values: [],
                expected: .success("")
            ),
            EvaluateTestCase(
                description: "formats single element without separator",
                format: #"$elements.map(x => `.${x}`).join(", ")"#,
                values: ["iOS"],
                expected: .success(".iOS")
            ),
            EvaluateTestCase(
                description: "handles elements with special characters",
                format: #"$elements.join(", ")"#,
                values: ["Hello World", "Foo\"Bar"],
                expected: .success("Hello World, Foo\"Bar")
            ),

            // エラーケース
            EvaluateTestCase(
                description: "fails when format returns number",
                format: "$elements.length",
                values: ["iOS", "macOS"],
                expected: .failure(.nonStringResult(format: "$elements.length", actualType: "number"))
            ),
            EvaluateTestCase(
                description: "fails when format returns undefined",
                format: "$elements.find(x => x === 'notfound')",
                values: ["iOS"],
                expected: .failure(.evaluationFailed(format: "$elements.find(x => x === 'notfound')"))
            ),
        ]
    }
}
```

---

### ArrayInputParserTests

**File:** `Tests/EggKitTests/Internals/ArrayInputParserTests.swift`

```swift
@testable import EggKit
import Testing

struct ArrayInputParserTests {
    let parser = ArrayInputParser()

    @Test(arguments: CLITestCase.allCases)
    func parseFromCLI(_ testCase: CLITestCase) {
        let result = parser.parseFromCLI(testCase.input)
        #expect(result == testCase.expected)
    }

    struct CLITestCase: CustomTestStringConvertible {
        let description: String
        let input: [String]
        let expected: [String]

        var testDescription: String { description }

        static let allCases: [CLITestCase] = [
            CLITestCase(
                description: "parses space-separated values",
                input: ["iOS", "macOS", "watchOS"],
                expected: ["iOS", "macOS", "watchOS"]
            ),
            CLITestCase(
                description: "splits comma-separated single value",
                input: ["iOS,macOS,watchOS"],
                expected: ["iOS", "macOS", "watchOS"]
            ),
            CLITestCase(
                description: "normalizes mixed separators",
                input: ["iOS,macOS", "watchOS"],
                expected: ["iOS", "macOS", "watchOS"]
            ),
            CLITestCase(
                description: "returns empty array for empty input",
                input: [],
                expected: []
            ),
        ]
    }

    @Test(arguments: InteractiveTestCase.allCases)
    func parseFromInteractive(_ testCase: InteractiveTestCase) {
        let result = parser.parseFromInteractive(testCase.input)
        #expect(result == testCase.expected)
    }

    struct InteractiveTestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let expected: [String]

        var testDescription: String { description }

        static let allCases: [InteractiveTestCase] = [
            InteractiveTestCase(
                description: "parses comma-separated input",
                input: "iOS, macOS, watchOS",
                expected: ["iOS", "macOS", "watchOS"]
            ),
            InteractiveTestCase(
                description: "trims whitespace from values",
                input: "  iOS  ,  macOS  ",
                expected: ["iOS", "macOS"]
            ),
            InteractiveTestCase(
                description: "filters empty segments",
                input: "iOS,,macOS,",
                expected: ["iOS", "macOS"]
            ),
            InteractiveTestCase(
                description: "returns empty array for empty input",
                input: "",
                expected: []
            ),
        ]
    }
}
```

---

### VariableResolverArrayFormatTests

**File:** `Tests/EggKitTests/WorkflowRunner/VariableResolverArrayFormatTests.swift`

```swift
@testable import EggKit
import Foundation
import Testing

struct VariableResolverArrayFormatTests {
    @Test(arguments: TestCase.allCases)
    func resolve(_ testCase: TestCase) async throws {
        let resolver = VariableResolver(
            macros: testCase.macros,
            outputs: StepOutputsStorage(),
            builtInMacroContext: TestCase.defaultBuiltInMacroContext
        )
        let result = try await resolver.resolve(testCase.input)
        #expect(result == testCase.expected)
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let macros: [ResolvedMacro]
        let expected: String

        var testDescription: String { description }

        static let defaultBuiltInMacroContext = BuiltInMacroContext(
            outputDirectory: nil,
            workingDirectory: URL(filePath: "/tmp/work"),
            homeDirectory: URL(filePath: "/tmp/home"),
            currentDate: Date(timeIntervalSince1970: 0),
            environment: [:]
        )

        static let allCases: [TestCase] = [
            TestCase(
                description: "resolves array with dot prefix format",
                input: "platforms: [___PLATFORMS___]",
                macros: [
                    ResolvedMacro(
                        name: "___PLATFORMS___",
                        description: "Platforms",
                        value: .array(["iOS", "macOS"], format: #"$elements.map(x => `.${x}`).join(", ")"#)
                    ),
                ],
                expected: "platforms: [.iOS, .macOS]"
            ),
            TestCase(
                description: "resolves array with default join format",
                input: "tags: ___TAGS___",
                macros: [
                    ResolvedMacro(
                        name: "___TAGS___",
                        description: "Tags",
                        value: .array(["swift", "library"], format: #"$elements.join(", ")"#)
                    ),
                ],
                expected: "tags: swift, library"
            ),
            TestCase(
                description: "resolves array with JSON format",
                input: "keywords: ___KEYWORDS___",
                macros: [
                    ResolvedMacro(
                        name: "___KEYWORDS___",
                        description: "Keywords",
                        value: .array(["swift", "template"], format: #""[" + $elements.map(x => `"${x}"`).join(", ") + "]""#)
                    ),
                ],
                expected: #"keywords: ["swift", "template"]"#
            ),
            TestCase(
                description: "resolves empty array",
                input: "deps: ___DEPENDENCIES___",
                macros: [
                    ResolvedMacro(
                        name: "___DEPENDENCIES___",
                        description: "Dependencies",
                        value: .array([], format: #"$elements.join(", ")"#)
                    ),
                ],
                expected: "deps: "
            ),
        ]
    }
}
```

---

### ConfigValidatorArrayFormatTests

**File:** `Tests/EggKitTests/Config/ConfigValidatorArrayFormatTests.swift`

```swift
@testable import EggKit
import Testing

struct ConfigValidatorArrayFormatTests {
    let validator = ConfigValidator()

    @Test(arguments: TestCase.allCases)
    func validate(_ testCase: TestCase) async throws {
        do {
            try await validator.validate(testCase.config)
            if case let .failure(expectedErrors) = testCase.expected {
                #expect(Bool(false), "Expected errors \(expectedErrors)")
            }
        } catch {
            switch testCase.expected {
            case .success:
                throw error
            case let .failure(expectedErrors):
                guard let combinedError = error as? CombinedError else {
                    throw error
                }
                let actualErrors = combinedError.errors
                    .compactMap { $0 as? ConfigValidator.Error }
                #expect(actualErrors == expectedErrors)
            }
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let config: Config
        let expected: Result

        var testDescription: String { description }

        enum Result {
            case success
            case failure([ConfigValidator.Error])
        }

        static let allCases: [TestCase] = [
            TestCase(
                description: "passes with valid array format expression",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(
                            name: "___PLATFORMS___",
                            description: "Platforms",
                            type: .array,
                            default: #"["iOS", "macOS"]"#,
                            format: #"$elements.map(x => `.${x}`).join(", ")"#
                        ),
                    ],
                    preHatch: nil,
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil
                ),
                expected: .success
            ),
            TestCase(
                description: "passes with array without format (uses default)",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(
                            name: "___TAGS___",
                            description: "Tags",
                            type: .array,
                            default: #"["swift"]"#
                        ),
                    ],
                    preHatch: nil,
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil
                ),
                expected: .success
            ),
            TestCase(
                description: "passes with array without choices (free input)",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(
                            name: "___DEPENDENCIES___",
                            description: "Dependencies",
                            type: .array,
                            default: "[]"
                        ),
                    ],
                    preHatch: nil,
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil
                ),
                expected: .success
            ),
            TestCase(
                description: "fails with format on non-array type",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(
                            name: "___NAME___",
                            description: "Name",
                            type: .string,
                            format: #"$elements.join(", ")"#
                        ),
                    ],
                    preHatch: nil,
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil
                ),
                expected: .failure([
                    .formatOnlyValidForArrayType(context: "macros[0]", name: "___NAME___"),
                ])
            ),
            TestCase(
                description: "fails with invalid format syntax",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(
                            name: "___PLATFORMS___",
                            description: "Platforms",
                            type: .array,
                            default: #"["iOS"]"#,
                            format: "$elements.map(x =>"  // incomplete
                        ),
                    ],
                    preHatch: nil,
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil
                ),
                expected: .failure([
                    .invalidFormatExpression(context: "macros[0]", name: "___PLATFORMS___", format: "$elements.map(x =>"),
                ])
            ),
        ]
    }
}
```

---

## 実装順序

1. `Config.Macro` に `format` フィールド追加
2. `ArrayFormatError` 作成
3. `ArrayFormatEvaluating` プロトコル作成
4. `ArrayFormatEvaluator` 実装（既存の`JSEvaluator`を利用）
5. `ArrayInputParser` 作成
6. `ResolvedMacro.Value.array` に `format` 追加（非Optional）
7. `MacroResolver.promptForArray` 修正（自由入力対応）
8. `MacroStringConverter` 修正（フォーマット適用）
9. `VariableResolver` 修正（フォーマット評価使用）
10. `ConfigValidator.MacrosValidator` 修正（format検証）
11. `ConfigValidator.Error` に新しいエラーケース追加
12. テスト追加

---

## ファイル一覧

### 新規ファイル

| ファイル | 説明 |
|---------|------|
| `Sources/EggKit/WorkflowRunner/ArrayFormatEvaluating.swift` | プロトコル定義 |
| `Sources/EggKit/WorkflowRunner/ArrayFormatEvaluator.swift` | 実装 |
| `Sources/EggKit/WorkflowRunner/ArrayFormatError.swift` | エラー型 |
| `Sources/EggKit/Internals/ArrayInputParser.swift` | 入力パーサー |
| `Tests/EggKitTests/WorkflowRunner/ArrayFormatEvaluatorTests.swift` | テスト |
| `Tests/EggKitTests/Internals/ArrayInputParserTests.swift` | テスト |
| `Tests/EggKitTests/WorkflowRunner/VariableResolverArrayFormatTests.swift` | テスト |
| `Tests/EggKitTests/Config/ConfigValidatorArrayFormatTests.swift` | テスト |

### 修正ファイル

| ファイル | 修正内容 |
|---------|---------|
| `Sources/EggKit/Config/Config.swift` | `format`フィールド追加 |
| `Sources/EggKit/Models/ResolvedMacro.swift` | `array` caseに`format`追加 |
| `Sources/EggKit/Internals/MacroStringConverter.swift` | フォーマット対応 |
| `Sources/EggKit/Internals/MacroResolver.swift` | 自由入力対応 |
| `Sources/EggKit/WorkflowRunner/VariableResolver.swift` | フォーマット評価使用 |
| `Sources/EggKit/Config/ConfigValidator+MacrosValidator.swift` | format検証追加 |

---

## ConfigValidator.Error 追加ケース

```swift
/// array型以外でformatが指定された
case formatOnlyValidForArrayType(context: String, name: String)

/// format式の構文が不正
case invalidFormatExpression(context: String, name: String, format: String)
```
