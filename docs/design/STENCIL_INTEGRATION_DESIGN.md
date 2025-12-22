# Stencil Integration Design Document

## Overview

eggにStencilテンプレートエンジンを統合し、拡張子ベースでエンジンを選択できるようにする。これにより、`{% if %}` や `{% for %}` などの制御構文がテンプレートファイル内で利用可能になる。

## 設計方針

### エンジン選択ロジック

ファイル拡張子によってテンプレートエンジンを自動選択する：

| ファイル名 | エンジン | 出力ファイル名 |
|-----------|---------|---------------|
| `main.swift` | Native（現行の`___MACRO___`置換） | `main.swift` |
| `main.swift.stencil` | Stencil | `main.swift`（`.stencil`除去） |

### ファイル名とディレクトリ名

Stencilはファイル内容のレンダリングのみをサポートしており、ファイル名の動的生成機能は持たない。したがって：

- **ファイル名・ディレクトリ名**: 現行の `___MACRO___` 形式を維持
- **ファイル内容**: エンジンに応じて処理

```
___PROJECT_NAME___/
├── Sources/
│   └── ___MODULE_NAME___/
│       ├── main.swift              # Native
│       └── App.swift.stencil       # Stencil
```

## 変数の形式と共存

### 変数形式の整理

| 形式 | 用途 | 例 |
|------|------|-----|
| `___MACRO___` | eggユーザー定義マクロ | `___PROJECT_NAME___` |
| `${{ phase.step.outputs.key }}` | egg step outputs | `${{ pre_hatch.setup.outputs.version }}` |
| `{{ ___MACRO___ }}` | Stencil内でのマクロ出力 | `{{ ___PROJECT_NAME___ }}` |
| `{% tag %}` | Stencilタグ（if, for等） | `{% if ___USE_ASYNC___ %}` |

### 共存の仕組み

1. **`___MACRO___` と `{{ }}`**: 衝突しない（形式が異なる）
2. **`${{ }}` と `{{ }}`**: `$`プレフィックスで区別可能

### 処理順序

```
1. BuiltInMacros解決 (___DATE___, ___UUID___ など)
2. マクロ + Step outputs → Stencilコンテキストに変換
3. Stencilレンダリング ({{ }}, {% if %}, {% for %})
4. (Nativeファイルのみ) 従来の ___MACRO___ 置換 + ${{ }} 解決
```

**重要**: Stencilテンプレートでは、step outputsを先にStencilコンテキストに変換することで、`{% if %}` 内での条件評価が可能になる。

## Stencilコンテキストへの変換

### マクロの変換

マクロは `___MACRO___` 形式のみをStencilコンテキストに登録する：

```swift
// 変換例
___PROJECT_NAME___ (string: "MyApp")
  → { "___PROJECT_NAME___": "MyApp" }

___USE_ASYNC___ (boolean: true)
  → { "___USE_ASYNC___": true }

___MODULES___ (choices: ["Foundation", "UIKit"])
  → { "___MODULES___": ["Foundation", "UIKit"] }
```

**設計理由**: 選択肢を増やさないことで、Native/Stencil両方で同じ変数名を使えるようにする。

### Step Outputsの変換

Step outputsは `${{ phase.step.outputs.key }}` 形式から、Stencilで使いやすい形式に変換する：

```swift
// 変換例
${{ pre_hatch.setup.outputs.version }}
  → { "pre_hatch_setup_outputs_version": "1.0.0" }
```

**命名規則**: `.` を `_` に置換してフラットなキー名にする。

### Stencilテンプレートでの使用例

```swift
struct {{ ___PROJECT_NAME___ }}App { }

// Step outputsの使用
// Version: {{ pre_hatch_setup_outputs_version }}

// 条件分岐
{% if ___USE_ASYNC___ %}
@main
struct {{ ___PROJECT_NAME___ }}App {
    static func main() async { }
}
{% endif %}

// ループ
{% for module in ___MODULES___ %}
import {{ module }}
{% endfor %}

// Step outputsを条件で使用
{% if pre_hatch_check_outputs_enabled == "yes" %}
// Feature enabled
{% endif %}
```

## Stencilの条件式

Stencilでは `{% %}` タグ内で変数名をそのまま使用する（`{{ }}` は不要）：

```swift
// 正しい書き方
{% if ___USE_ASYNC___ %}
{% if ___PROJECT_TYPE___ == "app" %}
{% if ___COUNT___ > 0 %}

// 間違い（{{ }}は不要）
{% if {{ ___USE_ASYNC___ }} %}  // ❌
```

### サポートされる演算子

| 種類 | 演算子 |
|------|--------|
| 比較 | `==`, `!=`, `<`, `<=`, `>`, `>=` |
| 論理 | `and`, `or`, `not` |

```swift
{% if ___USE_ASYNC___ and ___MODULES___ %}
{% if not ___DEBUG_MODE___ %}
{% if ___COUNT___ > 0 or ___FORCE_ENABLE___ %}
```

## アーキテクチャ

### 新規コンポーネント

```
Sources/EggKit/
├── TemplateEngine/
│   ├── TemplateEngine.swift          # Protocol定義
│   ├── TemplateContext.swift         # コンテキスト構造体
│   ├── NativeTemplateEngine.swift    # 現行の___MACRO___置換
│   └── StencilTemplateEngine.swift   # Stencilレンダリング
├── WorkflowRunner/
│   ├── TemplateExpander.swift        # 修正: エンジン選択ロジック追加
│   └── VariableResolver.swift        # 変更なし
```

### Protocol定義

```swift
// TemplateEngine.swift
package protocol TemplateEngine {
    func render(_ content: String, with context: TemplateContext) async throws -> String
}

// TemplateContext.swift
package struct TemplateContext {
    let macros: [ResolvedMacro]
    let outputs: StepOutputsStorage
    let builtInMacroContext: BuiltInMacroContext
}
```

### NativeTemplateEngine

現行の `VariableResolver` ロジックをラップ：

```swift
// NativeTemplateEngine.swift
package struct NativeTemplateEngine: TemplateEngine {
    func render(_ content: String, with context: TemplateContext) async throws -> String {
        let resolver = VariableResolver(
            macros: context.macros,
            outputs: context.outputs,
            builtInMacroContext: context.builtInMacroContext
        )
        return try await resolver.resolve(content)
    }
}
```

### StencilTemplateEngine

```swift
// StencilTemplateEngine.swift
import Stencil

package struct StencilTemplateEngine: TemplateEngine {
    func render(_ content: String, with context: TemplateContext) async throws -> String {
        // 1. BuiltInMacros解決
        var result = BuiltInMacros.resolve(content, context: context.builtInMacroContext)

        // 2. Stencilコンテキスト構築（マクロ + step outputs）
        let stencilContext = buildStencilContext(from: context)

        // 3. Stencilレンダリング
        let environment = Environment()
        result = try environment.renderTemplate(string: result, context: stencilContext)

        return result
    }

    private func buildStencilContext(from context: TemplateContext) async -> [String: Any] {
        var dict: [String: Any] = [:]

        // マクロを変換（___MACRO___ 形式のみ）
        for macro in context.macros {
            let value = convertMacroValue(macro.value)
            dict[macro.name] = value   // ___PROJECT_NAME___
        }

        // Step outputsを変換
        let allOutputs = await context.outputs.getAll()
        for (phase, stepOutputs) in allOutputs {
            for (stepId, outputs) in stepOutputs {
                for (key, value) in outputs {
                    // ${{ pre_hatch.setup.outputs.version }} → pre_hatch_setup_outputs_version
                    let flatKey = "\(phase)_\(stepId)_outputs_\(key)"
                        .replacingOccurrences(of: "-", with: "_")
                    dict[flatKey] = value
                }
            }
        }

        return dict
    }

    private func convertMacroValue(_ value: ResolvedMacro.Value) -> Any {
        switch value {
        case .string(let s): return s
        case .boolean(let b): return b
        case .choice(let c): return c
        case .choices(let c): return c
        case .array(let a, _): return a
        case .path(let p): return p.path
        }
    }
}
```

### TemplateExpanderの修正

```swift
// TemplateExpander.swift 修正箇所

private func transformFile(
    at path: URL,
    substituting macros: [ResolvedMacro],
    with outputs: StepOutputsStorage
) async throws {
    let data = try fileManager.readFile(at: path)
    guard let text = String(data: data, encoding: .utf8) else { return }

    let context = TemplateContext(
        macros: macros,
        outputs: outputs,
        builtInMacroContext: builtInMacroContext
    )

    // 拡張子でエンジンを選択
    let isStencil = path.pathExtension == "stencil"
    let engine: any TemplateEngine = isStencil
        ? StencilTemplateEngine()
        : NativeTemplateEngine()

    let transformed = try await engine.render(text, with: context)

    // 内容が変わった場合のみ書き込み
    if transformed != text {
        try fileManager.writeText(transformed, at: path, encoding: .utf8)
    }

    // .stencil拡張子を除去してリネーム
    if isStencil {
        let newPath = path.deletingPathExtension()
        try fileManager.moveItem(at: path, to: newPath)
    }
}
```

### collectFilesToGenerateの修正

`.stencil`ファイルは変換後のファイル名（`.stencil`除去後）として扱う：

```swift
private func collectFilesToGenerate(...) async throws -> [String] {
    // ...
    for (absolutePath, relativePath) in allPaths {
        // ...
        let transformedPath = try await resolvingMacros(in: relativePath, ...)

        // .stencil拡張子を除去した最終パス
        let finalPath: String
        if transformedPath.hasSuffix(".stencil") {
            finalPath = String(transformedPath.dropLast(8))  // ".stencil" = 8文字
        } else {
            finalPath = transformedPath
        }

        result.append(finalPath)
    }
    // ...
}
```

## Package.swift修正

```swift
dependencies: [
    // 既存の依存関係...
    .package(url: "https://github.com/stencilproject/Stencil", from: "0.15.1"),
],
targets: [
    .target(
        name: "EggKit",
        dependencies: [
            // 既存の依存関係...
            .product(name: "Stencil", package: "Stencil"),
        ]
    ),
]
```

## 使用例

### テンプレート構造

```
my-template/
├── config.yml
├── ___PROJECT_NAME___/
│   ├── main.swift                  # Native
│   └── App.swift.stencil           # Stencil
```

### config.yml

```yaml
name: Swift App Template
description: Create a Swift application with optional async support

macros:
  - name: ___PROJECT_NAME___
    type: string
    description: "Project name"

  - name: ___MODULES___
    type: choices
    description: "Select modules"
    choices: [Foundation, UIKit, SwiftUI, Combine]
    default: [Foundation]

  - name: ___USE_ASYNC___
    type: boolean
    description: "Use async/await?"
    default: false

pre_hatch:
  - id: setup
    run: |
      echo "version=1.0.0"
      echo "feature_enabled=yes"

hatch:
  output: ./
```

### main.swift (Native)

```swift
// Project: ___PROJECT_NAME___
// Created: ___DATE___

import Foundation

print("Hello from ___PROJECT_NAME___!")
```

### App.swift.stencil (Stencil)

```swift
// Project: {{ PROJECT_NAME }}
// Version: {{ pre_hatch_setup_outputs_version }}

import Foundation
{% for module in MODULES %}
import {{ module }}
{% endfor %}

{% if USE_ASYNC %}
@main
struct {{ PROJECT_NAME }}App {
    static func main() async {
        print("Hello from {{ PROJECT_NAME }} (async)")
        {% if pre_hatch_setup_outputs_feature_enabled == "yes" %}
        print("Feature is enabled!")
        {% endif %}
    }
}
{% else %}
@main
struct {{ PROJECT_NAME }}App {
    static func main() {
        print("Hello from {{ PROJECT_NAME }}")
    }
}
{% endif %}
```

### 出力結果（例）

`PROJECT_NAME=MyApp`, `MODULES=[Foundation, UIKit]`, `USE_ASYNC=true` の場合：

**App.swift:**
```swift
// Project: MyApp
// Version: 1.0.0

import Foundation
import Foundation
import UIKit

@main
struct MyAppApp {
    static func main() async {
        print("Hello from MyApp (async)")
        print("Feature is enabled!")
    }
}
```

## 処理フロー図

```
┌─────────────────────────────────────────────────────────────┐
│ TemplateExpander.transformFile(at: path)                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. ファイル読み込み                                         │
│     └─ Data → String (UTF-8)                                │
│                                                             │
│  2. 拡張子チェック                                          │
│     ├─ .stencil → StencilTemplateEngine                     │
│     └─ other   → NativeTemplateEngine                       │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ StencilTemplateEngine.render()                      │   │
│  │                                                      │   │
│  │  a. BuiltInMacros解決                               │   │
│  │     ___DATE___ → "2025-12-22"                       │   │
│  │                                                      │   │
│  │  b. Stencilコンテキスト構築                          │   │
│  │     ├─ マクロ → { PROJECT_NAME: "MyApp", ... }     │   │
│  │     └─ outputs → { pre_hatch_setup_outputs_...: }  │   │
│  │                                                      │   │
│  │  c. Stencilレンダリング                              │   │
│  │     ├─ {{ variable }} → 値展開                      │   │
│  │     ├─ {% if %} → 条件評価                          │   │
│  │     └─ {% for %} → ループ展開                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ NativeTemplateEngine.render()                       │   │
│  │                                                      │   │
│  │  a. BuiltInMacros解決                               │   │
│  │  b. ___MACRO___ 置換                                │   │
│  │  c. ${{ outputs }} 解決                             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  3. ファイル書き込み（変更があれば）                         │
│                                                             │
│  4. リネーム（.stencilの場合）                              │
│     App.swift.stencil → App.swift                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## エラーハンドリング

### Stencilエラー

```swift
enum StencilTemplateError: LocalizedError {
    case renderingFailed(file: String, underlying: Error)
    case invalidSyntax(file: String, line: Int?, message: String)

    var errorDescription: String? {
        switch self {
        case .renderingFailed(let file, let underlying):
            return "Failed to render Stencil template '\(file)': \(underlying.localizedDescription)"
        case .invalidSyntax(let file, let line, let message):
            if let line {
                return "Stencil syntax error in '\(file)' at line \(line): \(message)"
            }
            return "Stencil syntax error in '\(file)': \(message)"
        }
    }
}
```

## テスト計画

### 1. NativeTemplateEngine

既存の `VariableResolver` テストで担保済み。

### 2. StencilTemplateEngine

```swift
// 基本的な変数展開
func testBasicVariableExpansion() async throws {
    let engine = StencilTemplateEngine()
    let context = TemplateContext(
        macros: [ResolvedMacro(name: "___NAME___", value: .string("MyApp"))],
        outputs: StepOutputsStorage(),
        builtInMacroContext: .test
    )

    let result = try await engine.render("Hello {{ NAME }}", with: context)
    XCTAssertEqual(result, "Hello MyApp")
}

// if条件分岐
func testIfCondition() async throws {
    let template = """
    {% if USE_ASYNC %}async{% else %}sync{% endif %}
    """
    // USE_ASYNC = true → "async"
    // USE_ASYNC = false → "sync"
}

// forループ
func testForLoop() async throws {
    let template = """
    {% for m in MODULES %}import {{ m }}
    {% endfor %}
    """
    // MODULES = ["Foundation", "UIKit"]
    // → "import Foundation\nimport UIKit\n"
}

// Step outputs
func testStepOutputsInCondition() async throws {
    let template = """
    {% if pre_hatch_setup_outputs_enabled == "yes" %}enabled{% endif %}
    """
    // outputs: pre_hatch.setup.outputs.enabled = "yes"
    // → "enabled"
}
```

### 3. 拡張子除去

```swift
func testStencilExtensionRemoval() async throws {
    // Input: App.swift.stencil
    // Output: App.swift (content rendered, extension removed)
}
```

### 4. 混在テンプレート

```swift
func testMixedTemplates() async throws {
    // Template directory contains:
    // - main.swift (Native)
    // - App.swift.stencil (Stencil)
    // Both should be processed correctly
}
```

## 将来の拡張

### カスタムフィルター

```swift
// 例: camelCase → snake_case フィルター
environment.registerFilter("snake_case") { value in
    // MyProjectName → my_project_name
}

// テンプレートでの使用
// {{ PROJECT_NAME|snake_case }}
```

### カスタムタグ

```swift
// 例: インデントタグ
{% indent 4 %}
code here
{% endindent %}
```

## 参考資料

- [Stencil Documentation](https://stencil.fuller.li/en/latest/)
- [Stencil GitHub](https://github.com/stencilproject/Stencil)
- [StencilSwiftKit](https://github.com/SwiftGen/StencilSwiftKit) - 追加フィルター/タグ
