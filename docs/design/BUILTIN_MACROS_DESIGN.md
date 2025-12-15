# Built-in Macros 設計書

## 概要

本ドキュメントは、eggテンプレートエンジンにおけるBuilt-in Macros（組み込みマクロ）の設計を定義する。

Built-in Macrosは、config.yamlでの定義なしに自動的に利用可能なマクロであり、日付、システム情報、実行コンテキストなどの動的な値を提供する。

---

## 1. 対象となるBuilt-in Macros

| マクロ | 説明 | 出力例 |
|--------|------|--------|
| `___DATE___` | 現在日付（デフォルトフォーマット） | `2025-12-12` |
| `___DATE(format)___` | 現在日付（カスタムフォーマット） | `20251212` |
| `___YEAR___` | 現在年 | `2025` |
| `___SYSTEM_USER___` | システムユーザー名 | `ryu` |
| `___UUID___` | 生成されたUUID | `550e8400-e29b-41d4-a716-446655440000` |

### 将来の拡張候補

| マクロ | 説明 | 備考 |
|--------|------|------|
| `___OUTPUT___` | 出力ディレクトリ | コンテキスト依存、Phase 2で実装 |
| `___TEMPLATE_NAME___` | 使用中のテンプレート名 | - |
| `___WORKING_DIR___` | 作業ディレクトリ | - |

---

## 2. アーキテクチャ

### 2.1 設計方針

**ハイブリッドアプローチ**を採用：

1. **専用リゾルバー**: `BuiltInMacroRegistry` で組み込みマクロを一元管理
2. **Just-in-Time解決**: 変数置換時に動的に値を解決
3. **予約語保護**: ユーザー定義マクロとの名前衝突を防止

### 2.2 全体構成図

```
┌─────────────────────────────────────────────────────────┐
│                 BuiltInMacroRegistry                    │
│  - reservedNames: Set<String>                          │
│  - providers: [BuiltInMacroProvider]                   │
│  - isReserved(_:) -> Bool                              │
│  - resolve(_:context:) -> String                       │
└─────────────────────────────────────────────────────────┘
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
         ▼                  ▼                  ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│DateMacroProvider│ │SystemMacro-     │ │(将来拡張)       │
│ ___DATE___      │ │Provider         │ │ContextMacro-    │
│ ___DATE(fmt)___ │ │ ___SYSTEM_USER__│ │Provider         │
│ ___YEAR___      │ │ ___UUID___      │ │ ___OUTPUT___    │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

### 2.3 解決フローの変更

**変更前:**
```
resolveMacros(text) → resolveStepOutputs(result)
```

**変更後:**
```
resolveBuiltInMacros(text) → resolveMacros(result) → resolveStepOutputs(result)
       ↑ 新規追加
```

Built-in Macrosはユーザー定義マクロより**先に**解決される。

---

## 3. 型定義

### 3.1 `BuiltInMacroProvider` プロトコル

```swift
// File: Sources/EggKit/BuiltInMacros/BuiltInMacroProvider.swift

/// Built-in マクロの値を提供するプロトコル
protocol BuiltInMacroProvider: Sendable {
    /// このプロバイダーが処理するマクロ名（フォーマットパラメータなし）
    /// 例: `___DATE(format)___` の場合は `["___DATE___"]`
    var handledMacroNames: Set<String> { get }

    /// マクロにマッチする正規表現パターン（フォーマットバリアント含む）
    var pattern: Regex<AnyRegexOutput> { get }

    /// マッチしたマクロを値に解決する
    /// - Parameters:
    ///   - match: 正規表現マッチ結果
    ///   - context: 解決コンテキスト
    /// - Returns: 解決された値。このプロバイダーが処理しない場合はnil
    func resolve(match: Regex<AnyRegexOutput>.Match, context: BuiltInMacroContext) -> String?
}
```

### 3.2 `BuiltInMacroContext` 構造体

```swift
// File: Sources/EggKit/BuiltInMacros/BuiltInMacroContext.swift

/// Built-in マクロ解決時のコンテキスト
struct BuiltInMacroContext: Sendable {
    /// 出力ディレクトリ（hatch.output解決後に利用可能）
    let outputDirectory: AbsolutePath?

    /// 現在の作業ディレクトリ
    let workingDirectory: AbsolutePath

    /// ホームディレクトリ
    let homeDirectory: AbsolutePath

    /// 現在日時（テスト用にインジェクション可能）
    let currentDate: Date

    /// システム環境変数（テスト用にインジェクション可能）
    let environment: [String: String]
}
```

### 3.3 `BuiltInMacroRegistry` 中央レジストリ

```swift
// File: Sources/EggKit/BuiltInMacros/BuiltInMacroRegistry.swift

/// Built-in マクロの中央レジストリ
struct BuiltInMacroRegistry: Sendable {
    /// シングルトンインスタンス
    static let shared = BuiltInMacroRegistry()

    /// 登録されたプロバイダー
    private let providers: [BuiltInMacroProvider]

    /// 予約されたマクロ名（ユーザー定義で使用不可）
    var reservedNames: Set<String> {
        providers.reduce(into: Set<String>()) { result, provider in
            result.formUnion(provider.handledMacroNames)
        }
    }

    private init() {
        providers = [
            DateMacroProvider(),
            SystemMacroProvider(),
        ]
    }

    /// 指定した名前が予約語（built-in）かどうかを判定
    func isReserved(_ name: String) -> Bool {
        reservedNames.contains(name)
    }

    /// テキスト内のすべてのbuilt-inマクロを解決
    func resolve(_ text: String, context: BuiltInMacroContext) -> String {
        var result = text
        for provider in providers {
            result = resolveProvider(provider, in: result, context: context)
        }
        return result
    }

    private func resolveProvider(
        _ provider: BuiltInMacroProvider,
        in text: String,
        context: BuiltInMacroContext
    ) -> String {
        var result = text
        for match in text.matches(of: provider.pattern) {
            if let resolved = provider.resolve(match: match, context: context) {
                result = result.replacingOccurrences(
                    of: String(match.output.0),
                    with: resolved
                )
            }
        }
        return result
    }
}
```

---

## 4. プロバイダー実装

### 4.1 `DateMacroProvider`

```swift
// File: Sources/EggKit/BuiltInMacros/DateMacroProvider.swift

struct DateMacroProvider: BuiltInMacroProvider {
    var handledMacroNames: Set<String> {
        ["___DATE___", "___YEAR___"]
    }

    // ___DATE___, ___DATE(format)___, ___YEAR___ にマッチ
    var pattern: Regex<AnyRegexOutput> {
        try! Regex(#"___DATE(?:\(([^)]+)\))?___|___YEAR___"#)
    }

    func resolve(match: Regex<AnyRegexOutput>.Match, context: BuiltInMacroContext) -> String? {
        let matched = String(match.output.0)

        if matched == "___DATE___" {
            return formatDate(context.currentDate, format: "yyyy-MM-dd")
        }

        if matched == "___YEAR___" {
            return formatDate(context.currentDate, format: "yyyy")
        }

        // ___DATE(format)___ の処理
        if matched.hasPrefix("___DATE(") && matched.hasSuffix(")___") {
            let format = extractFormat(from: matched)
            return formatDate(context.currentDate, format: format)
        }

        return nil
    }

    private func formatDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func extractFormat(from macro: String) -> String {
        // ___DATE(yyyyMMdd)___ → yyyyMMdd
        let start = macro.index(macro.startIndex, offsetBy: 8)  // "___DATE(" の長さ
        let end = macro.index(macro.endIndex, offsetBy: -4)     // ")___" の長さ
        return String(macro[start..<end])
    }
}
```

### 4.2 `SystemMacroProvider`

```swift
// File: Sources/EggKit/BuiltInMacros/SystemMacroProvider.swift

struct SystemMacroProvider: BuiltInMacroProvider {
    var handledMacroNames: Set<String> {
        ["___SYSTEM_USER___", "___UUID___"]
    }

    var pattern: Regex<AnyRegexOutput> {
        try! Regex(#"___SYSTEM_USER___|___UUID___"#)
    }

    func resolve(match: Regex<AnyRegexOutput>.Match, context: BuiltInMacroContext) -> String? {
        let matched = String(match.output.0)

        switch matched {
        case "___SYSTEM_USER___":
            return context.environment["USER"] ?? NSUserName()
        case "___UUID___":
            return UUID().uuidString
        default:
            return nil
        }
    }
}
```

---

## 5. 既存コードへの統合

### 5.1 バリデーション統合

#### `ConfigValidator+MacrosValidator.swift` の変更

```swift
// 予約名チェックを追加
private func validateMacroName(_ macro: Config.Macro, context: String) -> Error? {
    guard !macro.name.isEmpty else {
        return nil
    }

    // NEW: Built-in マクロ名との衝突をチェック
    if BuiltInMacroRegistry.shared.isReserved(macro.name) {
        return .reservedMacroName(context: context, name: macro.name)
    }

    // 既存のフォーマットチェック
    return !isValidMacroName(macro.name)
        ? .invalidMacroNameFormat(context: context, name: macro.name)
        : nil
}

// マクロ参照検証でbuilt-inをスキップ
private func validateMacroReferencesInText(
    _ text: String,
    definedMacroNames: Set<String>,
    context: String
) -> [Error] {
    let referencedMacros = extractMacroReferences(from: text)

    return referencedMacros.compactMap { macroName in
        // Built-in マクロは検証をスキップ
        if BuiltInMacroRegistry.shared.isReserved(macroName) {
            return nil
        }
        if isDateMacroWithFormat(macroName) {
            return nil  // ___DATE(format)___ もスキップ
        }
        return definedMacroNames.contains(macroName)
            ? nil
            : Error.undefinedMacroReferenced(context: context, macroName: macroName)
    }
}

// ___DATE(format)___ パターンの判定
private func isDateMacroWithFormat(_ name: String) -> Bool {
    name.hasPrefix("___DATE(") && name.hasSuffix(")___")
}
```

#### `Config+Error.swift` の変更

```swift
// 新しいエラーケースを追加
enum Error: Swift.Error, Equatable {
    // ... 既存のケース ...

    /// ユーザーがbuilt-inマクロと同名のマクロを定義しようとした
    case reservedMacroName(context: String, name: String)
}
```

### 5.2 変数解決への統合

#### `VariableResolver.swift` の変更

```swift
func resolve(_ text: String) async throws -> String {
    // NEW: Pass 0 - Built-in マクロを最初に解決
    var result = resolveBuiltInMacros(text)

    // Pass 1 - ユーザー定義マクロを解決
    result = resolveMacros(result)

    // Pass 2 - Step outputs を解決
    result = try await resolveStepOutputs(result)

    return result
}

private func resolveBuiltInMacros(_ text: String) -> String {
    let context = BuiltInMacroContext(
        outputDirectory: nil,  // この時点では未確定
        workingDirectory: workingDirectory,
        homeDirectory: homeDirectory,
        currentDate: Date(),
        environment: ProcessInfo.processInfo.environment
    )
    return BuiltInMacroRegistry.shared.resolve(text, context: context)
}
```

#### `ConditionEvaluator.swift` の変更

```swift
func evaluate(_ condition: String) async throws -> Bool {
    // NEW: Pass 0 - Built-in マクロを最初に解決
    var result = resolveBuiltInMacros(condition)

    // Pass 1: 型認識クォートでマクロ解決
    result = resolveMacros(result)

    // Pass 2: Step output参照を解決
    result = try await resolveStepOutputs(result)

    // Pass 3: JavaScript評価
    return try evaluateJavaScript(result)
}

private func resolveBuiltInMacros(_ text: String) -> String {
    let context = BuiltInMacroContext(
        outputDirectory: nil,
        workingDirectory: workingDirectory,
        homeDirectory: homeDirectory,
        currentDate: Date(),
        environment: ProcessInfo.processInfo.environment
    )
    return BuiltInMacroRegistry.shared.resolve(text, context: context)
}
```

### 5.3 正規表現パターンの追加

#### `Regexes.swift` の変更

```swift
// Built-in 日付マクロ（フォーマット付き）にマッチ
static var builtInDateMacro: Regex<(Substring, Substring?)> {
    Regex {
        "___DATE"
        Optionally {
            "("
            Capture { OneOrMore(.any.subtracting(.anyOf(")"))) }
            ")"
        }
        "___"
    }
}
```

---

## 6. ファイル構成

### 6.1 新規作成ファイル

```
Sources/EggKit/BuiltInMacros/
├── BuiltInMacroProvider.swift      # プロトコル定義
├── BuiltInMacroContext.swift       # コンテキスト構造体
├── BuiltInMacroRegistry.swift      # 中央レジストリ
├── DateMacroProvider.swift         # 日付プロバイダー
└── SystemMacroProvider.swift       # システムプロバイダー
```

### 6.2 変更が必要なファイル

| ファイル | 変更内容 |
|---------|---------|
| `Config/Regexes.swift` | `builtInDateMacro` パターン追加 |
| `Config/ConfigValidator+MacrosValidator.swift` | 予約名チェック、built-in参照スキップ |
| `Config/Config+Error.swift` | `reservedMacroName` エラーケース追加 |
| `WorkflowRunner/VariableResolver.swift` | built-in解決パス追加 |
| `WorkflowRunner/ConditionEvaluator.swift` | built-in解決パス追加 |

---

## 7. テスト計画

### 7.1 ユニットテスト

#### `BuiltInMacroRegistryTests.swift`

```swift
final class BuiltInMacroRegistryTests: XCTestCase {
    func test_isReserved_returnsTrue_forBuiltInNames() {
        XCTAssertTrue(BuiltInMacroRegistry.shared.isReserved("___DATE___"))
        XCTAssertTrue(BuiltInMacroRegistry.shared.isReserved("___YEAR___"))
        XCTAssertTrue(BuiltInMacroRegistry.shared.isReserved("___SYSTEM_USER___"))
        XCTAssertTrue(BuiltInMacroRegistry.shared.isReserved("___UUID___"))
    }

    func test_isReserved_returnsFalse_forUserDefinedNames() {
        XCTAssertFalse(BuiltInMacroRegistry.shared.isReserved("___MODULE_NAME___"))
        XCTAssertFalse(BuiltInMacroRegistry.shared.isReserved("___CUSTOM___"))
    }

    func test_resolve_replacesDateMacro() {
        let context = makeContext(date: Date(timeIntervalSince1970: 1733961600)) // 2024-12-12
        let result = BuiltInMacroRegistry.shared.resolve("Today is ___DATE___", context: context)
        XCTAssertEqual(result, "Today is 2024-12-12")
    }

    func test_resolve_replacesDateWithFormat() {
        let context = makeContext(date: Date(timeIntervalSince1970: 1733961600))
        let result = BuiltInMacroRegistry.shared.resolve("___DATE(yyyyMMdd)___", context: context)
        XCTAssertEqual(result, "20241212")
    }
}
```

#### `DateMacroProviderTests.swift`

```swift
final class DateMacroProviderTests: XCTestCase {
    func test_resolve_defaultFormat() { ... }
    func test_resolve_customFormat_yyyyMMdd() { ... }
    func test_resolve_customFormat_MMddyyyy() { ... }
    func test_resolve_yearMacro() { ... }
    func test_resolve_multipleMacrosInSameText() { ... }
}
```

#### `SystemMacroProviderTests.swift`

```swift
final class SystemMacroProviderTests: XCTestCase {
    func test_resolve_systemUser_fromEnvironment() { ... }
    func test_resolve_uuid_generatesValidUUID() { ... }
    func test_resolve_uuid_generatesUniqueValues() { ... }
}
```

### 7.2 バリデーションテスト

```swift
final class ConfigValidatorMacrosTests: XCTestCase {
    func test_validate_rejectsReservedMacroName___DATE___() {
        let config = Config(macros: [
            .init(name: "___DATE___", description: "conflict", type: .string)
        ])
        let errors = ConfigValidator().validate(config)
        XCTAssertTrue(errors.contains(.reservedMacroName(context: "macros[0]", name: "___DATE___")))
    }

    func test_validate_allowsBuiltInMacroReferences_inRunCommands() {
        let config = Config(
            macros: [],
            preHatch: [.init(run: "echo ___DATE___")]
        )
        let errors = ConfigValidator().validate(config)
        XCTAssertTrue(errors.isEmpty)
    }
}
```

### 7.3 統合テスト

```swift
final class BuiltInMacrosIntegrationTests: XCTestCase {
    func test_hatch_expandsBuiltInMacrosInFileContent() { ... }
    func test_hatch_expandsBuiltInMacrosInFileName() { ... }
    func test_hatch_combinesBuiltInAndUserMacros() { ... }
    func test_preHatch_runCommand_usesBuiltInMacros() { ... }
    func test_ifCondition_evaluatesWithBuiltInMacros() { ... }
}
```

---

## 8. 実装順序

### Phase 1: 基盤構築
1. `BuiltInMacros/` ディレクトリ作成
2. `BuiltInMacroProvider` プロトコル定義
3. `BuiltInMacroContext` 構造体作成
4. `BuiltInMacroRegistry` 基本実装

### Phase 2: プロバイダー実装
1. `DateMacroProvider` 実装（`___DATE___`, `___DATE(format)___`, `___YEAR___`）
2. `SystemMacroProvider` 実装（`___SYSTEM_USER___`, `___UUID___`）
3. 各プロバイダーのユニットテスト

### Phase 3: バリデーション統合
1. `Regexes.swift` に `builtInDateMacro` パターン追加
2. `Config+Error.swift` に `reservedMacroName` エラー追加
3. `ConfigValidator+MacrosValidator.swift` 変更
4. バリデーションテスト

### Phase 4: 解決フロー統合
1. `VariableResolver.swift` に built-in 解決パス追加
2. `ConditionEvaluator.swift` に built-in 解決パス追加
3. 統合テスト

### Phase 5: ドキュメント・仕上げ
1. `CONFIG_YAML.md` の Built-in Macros セクション更新
2. `TemplateCreator.swift` のコメント更新（実装済みに変更）

---

## 9. 設計上の決定事項

### 9.1 なぜハイブリッドアプローチか

| アプローチ | 採用 | 理由 |
|-----------|------|------|
| 合成マクロ注入 | ❌ | `___DATE(format)___` が標準パターンに適合しない |
| 専用リゾルバー | ✅ | 予約語管理、拡張性に優れる |
| 解決時特別処理 | ✅ | Just-in-Time評価でコンテキスト依存に対応 |

### 9.2 解決順序の根拠

Built-in → User-defined → Step outputs の順序を採用：

1. **Built-in は常に利用可能**: ユーザー定義に依存しない
2. **ユーザー定義がBuilt-inを参照可能**: `default: "___DATE___-module"` のようなケース
3. **Step outputs は実行時に確定**: 前フェーズの結果に依存

### 9.3 `___DATE(format)___` の特別扱い

標準の `___[A-Z_]+___` パターンに適合しないため：

1. 専用の正規表現パターンを追加
2. バリデーション時に特別にスキップ
3. `DateMacroProvider` で専用処理

---

## 10. 将来の拡張

### 10.1 コンテキスト依存マクロ（Phase 2）

```swift
struct ContextMacroProvider: BuiltInMacroProvider {
    var handledMacroNames: Set<String> {
        ["___OUTPUT___", "___TEMPLATE_NAME___", "___WORKING_DIR___"]
    }

    func resolve(match: Regex<AnyRegexOutput>.Match, context: BuiltInMacroContext) -> String? {
        switch String(match.output.0) {
        case "___OUTPUT___":
            return context.outputDirectory?.pathString
        case "___WORKING_DIR___":
            return context.workingDirectory.pathString
        default:
            return nil
        }
    }
}
```

### 10.2 カスタムプロバイダー登録

将来的にユーザーがカスタムプロバイダーを登録できる仕組み：

```swift
extension BuiltInMacroRegistry {
    mutating func register(_ provider: BuiltInMacroProvider) {
        providers.append(provider)
    }
}
```

---

## 参考資料

- [CONFIG_YAML.md](./CONFIG_YAML.md) - config.yaml仕様
- [SPECS.md](./SPECS.md) - eggテンプレートエンジン仕様
- [LIFECYCLE_STEP_RUNNER_DESIGN.md](./LIFECYCLE_STEP_RUNNER_DESIGN.md) - ライフサイクル設計
