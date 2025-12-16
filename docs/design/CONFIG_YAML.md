# config.yaml 仕様書

## 概要

`config.yaml` は egg テンプレートエンジンのテンプレート動作を定義するファイルです。マクロ（ユーザー入力）、ライフサイクルフック（pre_hatch/hatch/post_hatch）、条件分岐ロジックを指定します。

## 基本構造

```yaml
# テンプレートのメタ情報
name: String
description: String

# マクロ定義（ユーザー入力）
macros:
  - name: ___MACRO_NAME___
    description: String
    type: string | boolean | choice | choices | path | array (オプション, デフォルト: string)
    default: Any (オプション, なければ必須入力)
    validate: String (string/array型, 正規表現。arrayの場合は各要素に適用)
    choices: [String] (choice/choices型では必須, その他の型では使用不可)
    format: String (array型のみ, JavaScript式, デフォルト: '$elements.join(", ")')

# pre_hatch ライフサイクル（テンプレート展開前）
pre_hatch:
  - id: String (オプション)
    if: String (オプション, 条件式)
    run: String (シェルコマンド)

# hatch 設定（テンプレート展開）
hatch:
  output: String (出力先ディレクトリ, step outputs対応)
  exclude:
    - String (globパターン)
    - if: String (条件)
      paths:
        - String (globパターン)

# post_hatch ライフサイクル（テンプレート展開後）
post_hatch:
  - id: String (オプション)
    if: String (オプション, 条件式)
    run: String (シェルコマンド)
```

## メタ情報

```yaml
name: Swift Module Generator
description: テストと適切なパッケージ構造を持つSwiftモジュールを作成
```

- `name`: テンプレートの表示名
- `description`: `egg template list` で表示される説明

## マクロ

マクロはユーザー入力で、以下のように扱われます：
1. CLI引数または対話プロンプトで収集
2. config.yaml内で `___MACRO_NAME___` として利用可能
3. テンプレートファイル（ファイル名、フォルダ名、ファイル内容）で置換

### マクロの型

#### string（デフォルト）

```yaml
- name: ___MODULE_NAME___
  description: "モジュール名"
  type: string
  validate: "^[A-Z][a-zA-Z0-9]*$"
  default: "MyModule"
```

**CLI:**
```bash
--module-name NetworkClient
```

#### boolean

```yaml
- name: ___CREATE_TESTS___
  description: "テストファイルを作成しますか？"
  type: boolean
  default: true
```

**CLI:**
```bash
--create-tests      # → true
--no-create-tests   # → false
# どちらも指定しない場合: default値（なければ false）
```

#### choice

単一選択型は、ユーザーが定義済みの選択肢から1つを選びます。

```yaml
- name: ___MODULE_TYPE___
  description: "モジュールタイプ"
  type: choice
  choices:
    - library
    - executable
    - plugin
  default: library
```

**CLI:**
```bash
--module-type library
```

#### choices

複数選択型は、ユーザーが定義済みの選択肢から複数を選べます。

```yaml
- name: ___PLATFORMS___
  description: "サポートするプラットフォーム"
  type: choices
  choices:
    - iOS
    - macOS
    - watchOS
    - tvOS
    - visionOS
  default: ["iOS", "macOS"]
```

**CLI:**
```bash
# スペース区切り
--platforms iOS macOS watchOS

# カンマ区切り
--platforms iOS,macOS,watchOS
```

**対話モード:**
チェックボックス形式でUI表示され、複数の選択肢を選べます。

**出力:**
カンマ区切りで出力されます（例: `iOS, macOS, watchOS`）。

#### array

配列型は、ユーザーが複数の値を自由に入力できます。`choices` フィールドは使用できず、入力値のホワイトリスト制約は設けられません。

```yaml
- name: ___DEPENDENCIES___
  description: "依存パッケージ"
  type: array
  default: []
  format: '$elements.map(x => `"${x}"`).join(", ")'  # JavaScript式（オプション）
```

**CLI:**
```bash
# スペース区切り
--dependencies Alamofire SwiftyJSON Kingfisher

# カンマ区切り
--dependencies Alamofire,SwiftyJSON,Kingfisher
```

**対話モード:**
```
依存パッケージ: Alamofire,SwiftyJSON,Kingfisher
```
カンマ(`,`)区切りで入力。

##### 出力フォーマット（JavaScript式）

`format` で配列の展開形式をJavaScript式で指定できます。`$elements` は入力された配列を参照します。
JavaScriptCoreで評価されるため、`map`, `join`, `filter`, テンプレートリテラルなど全て使用可能です。

| format | 入力 | 出力 |
|--------|------|------|
| `$elements.join(", ")` (デフォルト) | `[A, B, C]` | `A, B, C` |
| `$elements.map(x => \`.\${x}\`).join(", ")` | `[A, B, C]` | `.A, .B, .C` |
| `"[" + $elements.map(x => \`"\${x}"\`).join(", ") + "]"` | `[A, B]` | `["A", "B"]` |
| `$elements.map(x => \`import \${x}\`).join("\\n")` | `[Foundation, UIKit]` | `import Foundation`<br>`import UIKit` |
| `$elements.map(x => \`.package(name: "\${x}")\`).join(",\\n")` | `[A, B]` | `.package(name: "A"),`<br>`.package(name: "B")` |

##### 実用例

```yaml
# シンプルなカンマ区切り
- name: ___TAGS___
  type: array
  default: [swift, library]
  # format省略時: $elements.join(", ") → swift, library

# Swift Platform列挙
- name: ___PLATFORMS___
  type: array
  format: '$elements.map(x => `.${x}`).join(", ")'
  default: [iOS, macOS]
  # 出力: .iOS, .macOS

# JSON配列形式
- name: ___KEYWORDS___
  type: array
  format: '"[" + $elements.map(x => `"${x}"`).join(", ") + "]"'
  default: [swift, template]
  # 出力: ["swift", "template"]

# 改行区切りのimport文
- name: ___IMPORTS___
  type: array
  format: '$elements.map(x => `import ${x}`).join("\n")'
  default: [Foundation, UIKit]
  # 出力:
  # import Foundation
  # import UIKit

# SPM依存関係
- name: ___DEPENDENCIES___
  type: array
  format: '$elements.map(x => `.package(url: "https://github.com/xxx/${x}", from: "1.0.0")`).join(",\n        ")'
  default: []

# 正規表現も使用可能
- name: ___MODULES___
  type: array
  format: '$elements.map(x => x.replace(/([A-Z])/g, "-$1").toLowerCase().slice(1)).join(", ")'
  default: [MyModule, NetworkClient]
  # 出力: my-module, network-client

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

### マクロフィールドの互換性とバリデーション

`ConfigValidator` はフィールドの組み合わせを厳密にチェックします。以下の制約は `Tests/EggKitTests/Config/ConfigValidatorArrayFormatTests.swift` による仕様テストで保証されています。

| フィールド | 使用可能な型 | 備考 |
|-----------|--------------|------|
| `validate` | `string`, `array` | 正規表現。arrayの場合は各要素に対してバリデーション。Boolean/choice/choices/path では使用不可。 |
| `choices` | `choice`, `choices` | `choice`/`choices` では必須。それ以外の型（array を含む）では使用不可。 |
| `format` | `array` | JavaScript式。その他の型で指定するとエラー。 |

`format` フィールドに関する追加仕様:
- JavaScriptCore で評価される式は**必ず文字列を返す必要**があります。`undefined` や数値など非文字列を返す式は `invalidFormatExpression` エラーになります。
- 構文エラーを含む式も同様に `invalidFormatExpression` 扱いとなり、テンプレートは読み込まれません。
- `format`, `choices`, `validate` の違反はまとめて報告されるため、1つのマクロに複数の誤りがあってもすべてのエラーが表示されます。

#### array型の`validate`フィールドの動作

array型で`validate`フィールドを指定すると、**各配列要素に対して個別に**正規表現バリデーションが適用されます。

**バリデーションのタイミング:**
1. **Config読み込み時**: `validate`フィールドの正規表現構文が有効かチェック
2. **Interactive入力時**: ユーザーがカンマ区切りで入力した各要素をリアルタイムでバリデーション
3. **CLI引数解析時**: コマンドライン引数として渡された各要素をバリデーション
4. **テンプレート展開前**: 最終的な値の各要素を再度バリデーション

**エラーハンドリング:**
- 1つでも要素がパターンにマッチしない場合、エラーメッセージと共に処理が中断されます
- エラーメッセージには、マッチしなかった具体的な値と期待されるパターンが表示されます
- Interactive入力時は、正しい値を入力するまで再入力を求められます

**使用例:**

```yaml
# Swift モジュール名（PascalCase）
- name: ___MODULES___
  type: array
  description: "モジュール名"
  validate: "^[A-Z][a-zA-Z0-9]*$"
  format: '$elements.join(", ")'

  # ✅ 有効: NetworkClient, DataManager, APIClient
  # ❌ 無効: network-client, data_manager, 123Module

# パッケージ名（小文字、ハイフン、数字）
- name: ___PACKAGES___
  type: array
  description: "パッケージ名"
  validate: "^[a-z][a-z0-9-]*$"

  # ✅ 有効: swift-tools, package-1, mylib
  # ❌ 無効: Swift-Tools, Package_1, 123-start

# メールアドレス
- name: ___EMAILS___
  type: array
  description: "通知先メールアドレス"
  validate: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"

  # ✅ 有効: user@example.com, test.user@domain.co.jp
  # ❌ 無効: invalid-email, @example.com, user@
```

**空配列の扱い:**
- 空配列（要素数0）はバリデーションを**パス**します
- バリデーションは存在する要素に対してのみ適用されます
- 空配列を禁止したい場合は、別途defaultを設定するか、CLIレベルで制御してください

### マクロの命名規則

- **config.yaml内**: `___MODULE_NAME___`
- **テンプレートファイル内**: `___MODULE_NAME___`
- **CLI**: `--module-name`

変換: `___MODULE_NAME___` → `--module-name` (ケバブケース)

## 変数

### 利用可能な変数

| 変数の種類 | 構文 | 定義場所 | スコープ |
|-----------|------|---------|---------|
| **マクロ** | `___NAME___` | `macros:` セクション | config.yaml + テンプレートファイル |
| **環境変数** | `$VAR` または `${VAR}` | システム | `run:` コマンド内のみ |
| **Step Outputs** | `${{ pre_hatch.id.outputs.key }}` | `run:` 内で `echo "key=value"` | 後続のステップ |

### Step Outputs（GitHub Actions風）

ステップは `key=value` ペアをechoすることで出力を生成できます：

```yaml
pre_hatch:
  - id: setup-dirs
    run: |
      SRC="___PACKAGE_PATH___/Sources/___MODULE_NAME___"
      TESTS="___PACKAGE_PATH___/Tests/___MODULE_NAME___Tests"
      echo "src-dir=$SRC"
      echo "test-dir=$TESTS"

  - run: mkdir -p ${{ pre_hatch.setup-dirs.outputs.src-dir }}

hatch:
  output: ${{ pre_hatch.setup-dirs.outputs.src-dir }}

post_hatch:
  - run: echo "ソース: ${{ pre_hatch.setup-dirs.outputs.src-dir }}"
```

## ライフサイクルフック

### pre_hatch

テンプレート展開**前**に実行されます。用途：
- ディレクトリの作成
- セットアップコマンドの実行
- 動的な値の計算
- 環境の準備

```yaml
pre_hatch:
  - run: |
      cd ___PACKAGE_PATH___
      swift package add-target ___MODULE_NAME___ --type ___MODULE_TYPE___

  - id: compute-paths
    run: |
      echo "src=___PACKAGE_PATH___/Sources/___MODULE_NAME___"
      echo "tests=___PACKAGE_PATH___/Tests/___MODULE_NAME___Tests"
```

### hatch

テンプレートファイルの展開方法を定義します。

```yaml
hatch:
  output: ${{ pre_hatch.compute-paths.outputs.src }}

  exclude:
    # 常に除外
    - "*.md"
    - ".DS_Store"

    # 条件付き除外
    - if: !___CREATE_TESTS___
      paths:
        - "Tests/**"

    - if: ___MODULE_TYPE___ === "library"
      paths:
        - "main.swift"
```

**フィールド:**
- `output`: 出力先ディレクトリ（マクロとstep outputsに対応）
- `exclude`: 除外するファイル/ディレクトリ（globパターン）

### post_hatch

テンプレート展開**後**に実行されます。用途：
- テストの実行
- プロジェクトのビルド
- コードのフォーマット
- ドキュメント生成

```yaml
post_hatch:
  - if: ___CREATE_TESTS___
    run: swift test --package-path ___PACKAGE_PATH___

  - if: ___MODULE_TYPE___ === "executable"
    run: swift build --package-path ___PACKAGE_PATH___

  - run: swift-format format -i -r ${{ pre_hatch.compute-paths.outputs.src }}
```

## 条件分岐

`if:` 条件は **JavaScript式** として評価されます（JavaScriptCoreを使用）。

### 条件構文

#### Boolean マクロ
```yaml
- if: ___CREATE_TESTS___           # true
- if: !___CREATE_TESTS___           # false
```

#### 比較演算子
```yaml
- if: ___MODULE_TYPE___ === "library"
- if: ___MODULE_TYPE___ !== "executable"
- if: ___MIN_VERSION___ >= "5.9"
```

#### 論理演算子
```yaml
- if: ___CREATE_TESTS___ && ___INCLUDE_DOCS___
- if: ___CREATE_TESTS___ || ___INCLUDE_DOCS___
- if: (___A___ || ___B___) && ___C___
```

#### 配列のメンバーシップ
```yaml
- if: ___PLATFORMS___.includes("iOS")
- if: !___PLATFORMS___.includes("macOS")
```

#### Step outputs
```yaml
- if: pre_hatch.setup.outputs.ready === "true"
- if: pre_hatch.setup.outputs.path !== ""
```

### 条件付きステップ

```yaml
pre_hatch:
  - if: ___CREATE_TESTS___
    run: mkdir -p ___PACKAGE_PATH___/Tests

  - if: ___MODULE_TYPE___ === "executable"
    id: setup-executable
    run: |
      echo "entry-point=___PACKAGE_PATH___/Sources/___MODULE_NAME___/main.swift"
```

### hatch での条件付き除外

```yaml
hatch:
  output: ___OUTPUT___

  exclude:
    # 無条件
    - "*.md"
    - ".DS_Store"

    # 条件付き
    - if: !___CREATE_TESTS___
      paths:
        - "Tests/**"
        - "**/*Tests.swift"

    - if: !___INCLUDE_DOCS___
      paths:
        - "Documentation/**"
        - "**/*.docc"

    - if: ___MODULE_TYPE___ !== "executable"
      paths:
        - "main.swift"
```

## 完全な例

```yaml
name: Swift Module Generator
description: オプションでテストとドキュメントを含むSwiftモジュールを作成
version: 1.0.0

macros:
  - name: ___MODULE_NAME___
    description: "モジュール名"
    type: string
    validate: "^[A-Z][a-zA-Z0-9]*$"

  - name: ___PACKAGE_PATH___
    description: "パッケージパス"
    type: path

  - name: ___MODULE_TYPE___
    description: "モジュールタイプ"
    type: choice
    choices: [library, executable]
    default: library

  - name: ___CREATE_TESTS___
    description: "テストファイルを作成しますか？"
    type: boolean
    default: true

  - name: ___INCLUDE_DOCS___
    description: "ドキュメントを含めますか？"
    type: boolean
    default: false

  - name: ___AUTHOR_NAME___
    description: "著者名"
    type: string
    default: "Unknown"

  - name: ___PLATFORMS___
    description: "サポートするプラットフォーム"
    type: choices
    choices: [iOS, macOS, watchOS, tvOS, visionOS]
    default: ["iOS", "macOS"]

  - name: ___DEPENDENCIES___
    description: "依存パッケージ"
    type: array
    format: '$elements.map(x => `"${x}"`).join(", ")'
    default: []

pre_hatch:
  - run: |
      cd ___PACKAGE_PATH___
      swift package add-target ___MODULE_NAME___ --type ___MODULE_TYPE___
      rm -f Sources/___MODULE_NAME___/___MODULE_NAME___.swift

  - id: setup-dirs
    run: |
      SRC="___PACKAGE_PATH___/Sources/___MODULE_NAME___"
      TESTS="___PACKAGE_PATH___/Tests/___MODULE_NAME___Tests"
      DOCS="___PACKAGE_PATH___/Documentation"
      echo "src-dir=$SRC"
      echo "test-dir=$TESTS"
      echo "docs-dir=$DOCS"

  - run: mkdir -p ${{ pre_hatch.setup-dirs.outputs.src-dir }}

  - if: ___CREATE_TESTS___
    run: mkdir -p ${{ pre_hatch.setup-dirs.outputs.test-dir }}

  - if: ___INCLUDE_DOCS___
    run: mkdir -p ${{ pre_hatch.setup-dirs.outputs.docs-dir }}

hatch:
  output: ${{ pre_hatch.setup-dirs.outputs.src-dir }}

  exclude:
    - "*.md"
    - ".DS_Store"

    - if: !___CREATE_TESTS___
      paths:
        - "Tests/**"

    - if: !___INCLUDE_DOCS___
      paths:
        - "Documentation/**"
        - "**/*.docc"

    - if: ___MODULE_TYPE___ !== "executable"
      paths:
        - "main.swift"

post_hatch:
  - run: swift package resolve --package-path ___PACKAGE_PATH___

  - if: ___CREATE_TESTS___
    run: swift test --package-path ___PACKAGE_PATH___

  - if: ___INCLUDE_DOCS___
    run: |
      swift package --package-path ___PACKAGE_PATH___ \
        generate-documentation --target ___MODULE_NAME___

  - if: ___MODULE_TYPE___ === "executable"
    run: swift build --package-path ___PACKAGE_PATH___

  - run: |
      echo "✅ モジュールを作成しました: ${{ pre_hatch.setup-dirs.outputs.src-dir }}"
```

## テンプレートファイルの例

```swift
// ファイル: ___MODULE_NAME___.swift
// 作成者: ___AUTHOR_NAME___ on ___DATE___

/// モジュール: ___MODULE_NAME___
public struct ___MODULE_NAME___ {
    public init() {}
}
```

## システムマクロ

自動的に利用可能な組み込みマクロ：

| マクロ | 説明 | 例 |
|-------|------|-----|
| `___DATE___` | 現在の日付 | `2025-12-05` |
| `___DATE(yyyyMMdd)___` | フォーマット済み日付 | `20251205` |
| `___YEAR___` | 現在の年 | `2025` |
| `___SYSTEM_USER___` | システムユーザー名 | `ryu` |
| `___UUID___` | 生成されたUUID | `550e8400-e29b-41d4-a716-446655440000` |

使用例:
```swift
// 作成日: ___DATE___
// Copyright ___YEAR___ ___SYSTEM_USER___
// ID: ___UUID___
```

## CLI 使用方法

### hatch コマンド

```bash
# 対話モード
egg hatch SwiftModule

# ワンライナー
egg hatch SwiftModule \
  --module-name NetworkClient \
  --package-path ~/MyProject \
  --module-type library \
  --create-tests true \
  --include-docs false \
  --author-name "John Doe"

# 一部指定（不足分は対話で質問される）
egg hatch SwiftModule --module-name NetworkClient
```

### template duplicate コマンド

既存のテンプレートを複製して新しいテンプレートを作成します。

#### 基本構文

```bash
egg template duplicate <template-name> [options]
```

#### オプション

- `--name <name>`: 新しいテンプレート名（デフォルト: `<元の名前>1`）
- `--description <description>`: 新しいテンプレートの説明（デフォルト: 元の説明）
- `--project-directory <path>`: プロジェクトディレクトリ（デフォルト: 現在のディレクトリまたは設定値）

#### 使用例

```bash
# 対話モード（すべてのオプションを対話で入力）
egg template duplicate SwiftModule

# すべてのオプションを指定
egg template duplicate SwiftModule \
  --name SwiftModuleV2 \
  --description "Swift Module Generator (Version 2)" \
  --project-directory ~/MyProject

# 一部指定（不足分は対話で質問される）
egg template duplicate SwiftModule --name SwiftModuleV2

# デフォルト値の使用例
# 元のテンプレート名が "SwiftModule" の場合
egg template duplicate SwiftModule
# → 新しいテンプレート名: "SwiftModule1"
# → 新しい説明: 元の説明と同じ
```

#### 動作

1. 元のテンプレート（`<template-name>`）を検索
2. 新しいテンプレート名を決定:
   - `--name` が指定されている場合: その値を使用
   - 指定されていない場合: `<元の名前>1` をデフォルト値として使用（対話モードでは確認可能）
3. 新しいテンプレートの説明を決定:
   - `--description` が指定されている場合: その値を使用
   - 指定されていない場合: 元の説明をデフォルト値として使用（対話モードでは確認可能）
4. 元のテンプレートディレクトリ全体を新しい名前でコピー
5. 新しいテンプレートの `config.yaml` 内の `name` と `description` を更新

#### デフォルト値の動作

- **`--name` のデフォルト値**: 元のテンプレート名に利用可能な最小の番号を付加
  - 既存のテンプレート名を確認し、重複しない最小の番号を自動的に決定
  - 例:
    - `SwiftModule` を duplicate → `SwiftModule1`（`SwiftModule1` が存在しない場合）
    - 再度 `SwiftModule` を duplicate → `SwiftModule2`（`SwiftModule1` が既に存在する場合）
    - さらに duplicate → `SwiftModule3`（`SwiftModule1` と `SwiftModule2` が既に存在する場合）
  - 番号は連続している必要はなく、利用可能な最小の番号が選択される
    - 例: `SwiftModule1` と `SwiftModule3` が存在する場合、次は `SwiftModule2` が選択される
- **`--description` のデフォルト値**: 元のテンプレートの `description` をそのまま使用

#### 対話モード

オプションが指定されていない場合、対話的に入力が求められます：

```bash
$ egg template duplicate SwiftModule
テンプレート名 [SwiftModule1]: SwiftModuleV2
説明 [元の説明]: Swift Module Generator (Version 2)
プロジェクトディレクトリ [./]: ~/MyProject
✅ テンプレートを複製しました: SwiftModuleV2
```

対話モードでは、各項目に対してデフォルト値が表示され、Enter キーを押すとデフォルト値が使用されます。

## テンプレートディレクトリ構造

```
Templates/SwiftModule/
├── config.yaml
├── ___MODULE_NAME___.swift
├── ___MODULE_NAME___+Extensions.swift
├── Tests/
│   └── ___MODULE_NAME___Tests.swift
└── Documentation/
    └── ___MODULE_NAME___.md
```

以下の箇所にある `___MODULE_NAME___`, `___AUTHOR_NAME___` などは全てユーザーが指定した実際の値に置換されます：
- ファイル名
- フォルダ名
- ファイル内容
