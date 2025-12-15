# Array Type Macro Feature Implementation Plan

## 概要

`DESIGN_ARRAY_MACRO.md`に基づく実装計画。JavaScript式による配列フォーマット機能を実装する。

---

## コードベース調査結果

### ディレクトリ構造

```
Sources/EggKit/
├── Config/                   # 設定管理
│   ├── Config.swift         # Config.Macro修正対象
│   └── ConfigValidator+MacrosValidator.swift  # 検証追加対象
├── Models/
│   └── ResolvedMacro.swift  # Value.array修正対象
├── Internals/
│   └── MacroStringConverter.swift  # フォーマット対応追加
└── WorkflowRunner/
    ├── JSEvaluator.swift    # 既存（再利用）
    └── VariableResolver.swift  # フォーマット評価追加

Tests/EggKitTests/
├── MacroStringConverterTests.swift
├── ConfigValidatorTests.swift
└── WorkflowRunner/
    └── VariableResolverTests.swift
```

### コーディング規約

| 項目 | 規約 |
|-----|------|
| アクセス修飾子 | `internal`（デフォルト、明示不要）。スコープは狭ければ狭いほど良い。モジュール外公開が必要な場合のみ`package`/`public` |
| 型 | `struct` 優先、エラーは `enum` |
| Sendable | スレッドセーフな型にのみ適用。必要な場合のみ付与 |
| エラー | `LocalizedError`, `Equatable` 準拠 |
| テスト | Swift Testing (`@Test(arguments:)`, `#expect`) |

### 設計原則

| 原則 | 説明 |
|-----|------|
| **SSoT** (Single Source of Truth) | 情報は一箇所で定義。重複した定義を避ける |
| **DRY** (Don't Repeat Yourself) | 同じロジックを繰り返さない。共通化できるコードは関数/型に抽出 |
| **最小スコープ** | 変数・関数・型のスコープは必要最小限に |
| **意味のある分割** | 複雑な処理は関数に分け、処理に名前（意味）を与える |
| **1ファイル1責務** | 1つのファイルに1つの重要な型。関連するヘルパーは同ファイル可 |

---

## 実装フェーズ

### Phase 1: 基盤型の作成

**目的**: 新規ファイルの作成（既存コードへの影響なし）

#### 1.1 ArrayFormatError

**File**: `Sources/EggKit/WorkflowRunner/ArrayFormatError.swift`

```swift
enum ArrayFormatError: LocalizedError, Equatable {
    case evaluationFailed(format: String)
    case nonStringResult(format: String, actualType: String)

    var errorDescription: String? { ... }
}
```

**依存**: なし

---

#### 1.2 ArrayFormatEvaluating

**File**: `Sources/EggKit/WorkflowRunner/ArrayFormatEvaluating.swift`

```swift
protocol ArrayFormatEvaluating {
    func evaluate(format: String, values: [String]) throws -> String
}
```

**依存**: `ArrayFormatError`

---

#### 1.3 ArrayFormatEvaluator

**File**: `Sources/EggKit/WorkflowRunner/ArrayFormatEvaluator.swift`

```swift
struct ArrayFormatEvaluator: ArrayFormatEvaluating {
    static let defaultFormat: String = #"$elements.join(", ")"#

    private let jsEvaluator: JSEvaluator

    init(jsEvaluator: JSEvaluator = JSEvaluator())
    func evaluate(format: String, values: [String]) throws -> String
}
```

**依存**: `JSEvaluator`, `ArrayFormatEvaluating`, `ArrayFormatError`

**実装詳細**:
1. `values`をJSON配列文字列に変換
2. `$e = [values]` をJSコンテキストに設定
3. `format`式を評価
4. 結果が文字列であることを検証

---

#### 1.4 ArrayInputParser

**File**: `Sources/EggKit/Internals/ArrayInputParser.swift`

```swift
struct ArrayInputParser {
    func parseFromCLI(_ values: [String]) -> [String]
    func parseFromInteractive(_ input: String) -> [String]
}
```

**依存**: なし

**実装詳細**:
- `parseFromCLI`: 各要素をカンマで分割してフラット化
- `parseFromInteractive`: カンマ区切り、空白トリム、空要素除外

---

#### 1.5 Phase 1 テスト

**Files**:
- `Tests/EggKitTests/WorkflowRunner/ArrayFormatEvaluatorTests.swift`
- `Tests/EggKitTests/Internals/ArrayInputParserTests.swift`

**テストケース**: `DESIGN_ARRAY_MACRO.md`参照

---

### Phase 2: モデル層の修正

**目的**: データ構造の拡張

#### 2.1 Config.Macro

**File**: `Sources/EggKit/Config/Config.swift`

**変更内容**:
```swift
// 既存フィールドに追加

/// array型専用のJavaScriptフォーマット式。
/// `$elements`で入力配列を参照。デフォルト: `$elements.join(", ")`
let format: String?
```

**影響範囲**:
- `Codable`により自動的にYAMLパースに対応
- 既存のconfig.yamlは`format`がnilとしてパースされる（後方互換）

---

#### 2.2 ResolvedMacro.Value

**File**: `Sources/EggKit/Models/ResolvedMacro.swift`

**変更内容**:
```swift
enum Value: Equatable, Sendable {
    case string(String)
    case boolean(Bool)
    case choice(String)
    case array([String], format: String)  // format追加
    case path(URL)
}
```

**影響範囲**:
- `MacroResolver` - `ResolvedMacro`生成箇所
- `MacroStringConverter` - 文字列変換箇所
- `VariableResolver` - マクロ解決箇所
- テストファイル - `ResolvedMacro`を使用する箇所

---

### Phase 3: 変換・解決層の修正

**目的**: フォーマット機能の統合

#### 3.1 MacroStringConverter

**File**: `Sources/EggKit/Internals/MacroStringConverter.swift`

**変更内容**:

`.array`ケースに`format`パラメータを追加:

```swift
case let .array(a, format):
    return try ArrayFormatEvaluator().evaluate(format: format, values: a)
```

**注意**: `toShellString`がthrowsに変更される

---

#### 3.2 VariableResolver

**File**: `Sources/EggKit/WorkflowRunner/VariableResolver.swift`

**変更内容**:

`resolveMacros`メソッドを高階関数で書き直し:

```swift
/// Replaces all `___MACRO_NAME___` patterns with their resolved values.
private func resolveMacros(_ text: String) throws -> String {
    try macros.reduce(text) { result, macro in
        let stringValue = try MacroStringConverter.toShellString(
            macro.value,
            workingDirectory: builtInMacroContext.workingDirectory,
            homeDirectory: builtInMacroContext.homeDirectory
        )
        return result.replacingOccurrences(of: macro.name, with: stringValue)
    }
}
```

**変更点**:
- `for`ループ → `reduce`に変更
- `throws`追加（`MacroStringConverter.toShellString`がthrowsになるため）
- `resolve`メソッドも`try resolveMacros`に変更

---

#### 3.3 Phase 3 テスト

**File**: `Tests/EggKitTests/WorkflowRunner/VariableResolverArrayFormatTests.swift`

**テストケース**: `DESIGN_ARRAY_MACRO.md`参照

---

### Phase 4: バリデーション層の修正

**目的**: 設定ファイルの検証強化

#### 4.1 ConfigValidator.Error

**File**: `Sources/EggKit/Config/ConfigValidator.swift` または `Config+Error.swift`

**追加エラーケース**:
```swift
case formatOnlyValidForArrayType(context: String, name: String)
case invalidFormatExpression(context: String, name: String, format: String)
```

---

#### 4.2 ConfigValidator+MacrosValidator

**File**: `Sources/EggKit/Config/ConfigValidator+MacrosValidator.swift`

**追加メソッド**:
```swift
private func validateFormatField(
    _ macro: Config.Macro,
    context: String
) -> [Error] {
    var errors: [Error] = []

    // array型以外でformatが指定されている
    if macro.format != nil && macro.type != .array {
        errors.append(Error.formatOnlyValidForArrayType(
            context: context,
            name: macro.name
        ))
    }

    // format式の構文検証（指定時のみ）
    if let format = macro.format, macro.type == .array {
        let evaluator = ArrayFormatEvaluator()
        do {
            _ = try evaluator.evaluate(format: format, values: ["test"])
        } catch {
            errors.append(Error.invalidFormatExpression(
                context: context,
                name: macro.name,
                format: format
            ))
        }
    }

    return errors
}
```

**呼び出し箇所**: `validateMacro`メソッド内で追加呼び出し

---

#### 4.3 Phase 4 テスト

**File**: `Tests/EggKitTests/Config/ConfigValidatorArrayFormatTests.swift`

**テストケース**: `DESIGN_ARRAY_MACRO.md`参照

---

### Phase 5: 既存テストの修正

**目的**: `ResolvedMacro.Value.array`のシグネチャ変更に伴うテスト修正

#### 5.1 影響を受けるテストファイル

| ファイル | 修正内容 |
|---------|---------|
| `MacroStringConverterTests.swift` | `.array(values)` → `.array(values, format: defaultFormat)` |
| `VariableResolverTests.swift` | 同上 |

**修正パターン**:
```swift
// Before
ResolvedMacro(
    name: "___PLATFORMS___",
    description: "Platforms",
    value: .array(["iOS", "macOS", "watchOS"])
)

// After
ResolvedMacro(
    name: "___PLATFORMS___",
    description: "Platforms",
    value: .array(["iOS", "macOS", "watchOS"], format: ArrayFormatEvaluator.defaultFormat)
)
```

---

## 実装順序チェックリスト

### Phase 1: 基盤型の作成
- [x] `ArrayFormatError.swift` 作成
- [x] `ArrayFormatEvaluating.swift` 作成
- [x] `ArrayFormatEvaluator.swift` 作成
- [x] `ArrayInputParser.swift` 作成
- [x] `ArrayFormatEvaluatorTests.swift` 作成・実行
- [x] `ArrayInputParserTests.swift` 作成・実行

### Phase 2: モデル層の修正
- [x] `Config.Macro`に`format`フィールド追加
- [x] `ResolvedMacro.Value.array`に`format`パラメータ追加
- [x] コンパイルエラー箇所の特定

### Phase 3: 変換・解決層の修正
- [x] `MacroStringConverter.toShellString`を`throws`に変更、`.array`ケース修正
- [x] `VariableResolver.resolveMacros`を`reduce`で書き直し
- [x] `VariableResolverArrayFormatTests.swift` 作成・実行

### Phase 4: バリデーション層の修正
- [x] `ConfigValidator.Error`にケース追加
- [x] `ConfigValidator+MacrosValidator`に検証追加
- [x] `ConfigValidatorArrayFormatTests.swift` 作成・実行

### Phase 5: 既存テストの修正
- [x] `MacroStringConverterTests.swift` 修正
- [x] `VariableResolverTests.swift` 修正
- [x] 全テスト実行・通過確認

---

## リスクと対策

### リスク1: `ResolvedMacro.Value`の変更による広範な影響

**対策**: Phase 2完了後、即座にPhase 3と5を並行して進める

### リスク2: 既存テストの大量修正

**対策**: デフォルトformat値を使用し、最小限の変更で対応

### リスク3: JavaScript評価のパフォーマンス

**対策**: `JSEvaluator`インスタンスの再利用（既存パターン踏襲）

---

## 完了条件

1. 全テストが通過すること
2. `config.yaml`で`format`フィールドが使用可能なこと
3. `choices`なしの配列入力が動作すること
4. カスタムフォーマット式が正しく評価されること
5. 不正なformat式に対してバリデーションエラーが発生すること

---

## ファイル一覧（最終）

### 新規作成（6ファイル）

| ファイル | Phase |
|---------|-------|
| `Sources/EggKit/WorkflowRunner/ArrayFormatError.swift` | 1 |
| `Sources/EggKit/WorkflowRunner/ArrayFormatEvaluating.swift` | 1 |
| `Sources/EggKit/WorkflowRunner/ArrayFormatEvaluator.swift` | 1 |
| `Sources/EggKit/Internals/ArrayInputParser.swift` | 1 |
| `Tests/EggKitTests/WorkflowRunner/ArrayFormatEvaluatorTests.swift` | 1 |
| `Tests/EggKitTests/Internals/ArrayInputParserTests.swift` | 1 |

### 修正（7ファイル）

| ファイル | Phase |
|---------|-------|
| `Sources/EggKit/Config/Config.swift` | 2 |
| `Sources/EggKit/Models/ResolvedMacro.swift` | 2 |
| `Sources/EggKit/Internals/MacroStringConverter.swift` | 3 |
| `Sources/EggKit/WorkflowRunner/VariableResolver.swift` | 3 |
| `Sources/EggKit/Config/ConfigValidator+MacrosValidator.swift` | 4 |
| `Tests/EggKitTests/MacroStringConverterTests.swift` | 5 |
| `Tests/EggKitTests/WorkflowRunner/VariableResolverTests.swift` | 5 |

### 新規テスト（2ファイル）

| ファイル | Phase |
|---------|-------|
| `Tests/EggKitTests/WorkflowRunner/VariableResolverArrayFormatTests.swift` | 3 |
| `Tests/EggKitTests/Config/ConfigValidatorArrayFormatTests.swift` | 4 |
