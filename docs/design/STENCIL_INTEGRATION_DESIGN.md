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

## 変数の形式

### 変数形式の整理

| 形式 | 用途 | 例 |
|------|------|-----|
| `___MACRO___` | eggユーザー定義マクロ | `___PROJECT_NAME___` |
| `${{ phase.step.outputs.key }}` | egg step outputs | `${{ pre_hatch.setup.outputs.version }}` |
| `{{ ___MACRO___ }}` | Stencil内でのマクロ出力 | `{{ ___PROJECT_NAME___ }}` |
| `{% tag %}` | Stencilタグ（if, for等） | `{% if ___USE_ASYNC___ %}` |

### エンジン別の利用可否

| 形式 | Native / config.yml | Stencil (`.stencil`) |
|------|:-------------------:|:--------------------:|
| `___MACRO___` | ✅ | ❌ |
| `${{ outputs }}` | ✅ | ❌ |
| `{{ ___MACRO___ }}` | ❌ | ✅ |
| `{{ phase.step.outputs.key }}` | ❌ | ✅ |
| `{% if %}` / `{% for %}` | ❌ | ✅ |

**注意**:
- Nativeファイルで`{{ }}`や`{% %}`を書いても**処理されない**（そのまま出力）
- Stencilファイルで`___MACRO___`や`${{ }}`を書いても**処理されない**

## Stencilコンテキストへの変換

### マクロの変換

マクロは `___MACRO___` 形式のみをStencilコンテキストに登録する：

```
___PROJECT_NAME___ (string: "MyApp")
  → { "___PROJECT_NAME___": "MyApp" }

___USE_ASYNC___ (boolean: true)
  → { "___USE_ASYNC___": true }

___MODULES___ (choices: ["Foundation", "UIKit"])
  → { "___MODULES___": ["Foundation", "UIKit"] }
```

**設計理由**: 選択肢を増やさないことで、Native/Stencil両方で同じ変数名を使えるようにする。

### Step Outputsの変換

Step outputsはネストしたdictとしてStencilコンテキストに渡す：

```yaml
# config.yml
pre_hatch:
  - id: setup
    run: |
      echo "version=1.0.0"
      echo "enabled=yes"
```

```
→ {
    "pre_hatch": {
        "setup": {
            "outputs": {
                "version": "1.0.0",
                "enabled": "yes"
            }
        }
    }
}
```

これによりStencil内で `{{ pre_hatch.setup.outputs.version }}` のようにアクセスできる。

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

## アーキテクチャ

### ファイル構成

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

### インターフェース

```swift
package protocol TemplateEngine {
    func render(_ content: String, with context: TemplateContext) async throws -> String
}

package struct TemplateContext {
    let macros: [ResolvedMacro]
    let outputs: StepOutputsStorage
    let builtInMacroContext: BuiltInMacroContext
}
```

## 処理フロー

### TemplateExpander.transformFile

```
1. ファイル読み込み
   └─ Data → String (UTF-8)

2. 拡張子チェック
   ├─ .stencil → StencilTemplateEngine
   └─ other   → NativeTemplateEngine

3. engine.render() 実行

4. ファイル書き込み（変更があれば）

5. リネーム（.stencilの場合）
   └─ App.swift.stencil → App.swift
```

### StencilTemplateEngine.render

```
1. BuiltInMacros解決
   └─ ___DATE___ → "2025-12-24"

2. Stencilコンテキスト構築
   ├─ マクロ → { ___PROJECT_NAME___: "MyApp" }
   └─ outputs → { pre_hatch: { setup: { outputs: { ... } } } }

3. Stencilレンダリング
   ├─ {{ variable }} → 値展開
   ├─ {% if %} → 条件評価
   └─ {% for %} → ループ展開
```

### NativeTemplateEngine.render

```
1. BuiltInMacros解決
2. ___MACRO___ 置換
3. ${{ outputs }} 解決
```

## 依存関係

```swift
// Package.swift
.package(url: "https://github.com/stencilproject/Stencil", from: "0.15.1")
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

### main.swift (Native)

```swift
// Project: ___PROJECT_NAME___
// Created: ___DATE___

import Foundation

print("Hello from ___PROJECT_NAME___!")
```

### App.swift.stencil (Stencil)

```swift
// Project: {{ ___PROJECT_NAME___ }}
// Version: {{ pre_hatch.setup.outputs.version }}

import Foundation
{% for module in ___MODULES___ %}
import {{ module }}
{% endfor %}

{% if ___USE_ASYNC___ %}
@main
struct {{ ___PROJECT_NAME___ }}App {
    static func main() async {
        print("Hello from {{ ___PROJECT_NAME___ }} (async)")
    }
}
{% else %}
@main
struct {{ ___PROJECT_NAME___ }}App {
    static func main() {
        print("Hello from {{ ___PROJECT_NAME___ }}")
    }
}
{% endif %}
```

## テストへの影響

### 既存テスト

| ファイル | 変更内容 |
|---------|---------|
| `TemplateExpanderTests.swift` | Stencil用テストケース追加 |
| `ArrayFormatEvaluatorTests.swift` | `format`廃止後、削除 |
| `VariableResolverArrayFormatTests.swift` | `format`廃止後、削除 |
| `ConfigValidatorArrayFormatTests.swift` | `format`関連テスト削除 |

### 新規テスト

| ファイル | 内容 |
|---------|------|
| `StencilTemplateEngineTests.swift` | Stencilエンジンのユニットテスト |
| `NativeTemplateEngineTests.swift` | Nativeエンジンのユニットテスト |

### E2Eテスト (E2ETestsPackage/)

- **変更不要**: CLIコマンドレベルのテストであり、テンプレートエンジン内部変更に影響されない
- **推奨**: Stencil統合後、`.stencil`ファイルを含むテンプレートのE2Eテスト追加

---

## `format`フィールドの廃止

Stencil導入に伴い、`array`型の`format`フィールドは廃止する。

### 現状（Native）

```yaml
- name: ___MODULES___
  type: array
  format: '$elements.map(x => `import ${x}`).join("\n")'
```

### Stencilでの代替

```swift
// template.swift.stencil
{% for module in ___MODULES___ %}
import {{ module }}
{% endfor %}
```

### Stencilの利点

- 条件分岐も入れられる（`{% if %}`）
- インデント調整も自由
- JavaScript式を覚える必要がない
- 可読性が高い

### 結論

`format`フィールドは廃止。配列を整形して出力したい場合は`.stencil`ファイルを使用すること。

## 参考資料

- [Stencil Documentation](https://stencil.fuller.li/en/latest/)
- [Stencil GitHub](https://github.com/stencilproject/Stencil)
