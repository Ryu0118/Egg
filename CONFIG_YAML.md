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
    type: string | boolean | choice | path | array (オプション, デフォルト: string)
    default: Any (オプション, なければ必須入力)
    validate: String (オプション, 正規表現)
    choices: [String] (choice型で必須)

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
  - if: String (オプション)
    hatch: String (テンプレート名)
    args:
      ___MACRO___: value
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
--create-tests true
--create-tests false
# または
--create-tests
--no-create-tests
```

#### choice

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

#### array

```yaml
- name: ___PLATFORMS___
  description: "サポートするプラットフォーム"
  type: array
  choices:
    - iOS
    - macOS
    - watchOS
    - tvOS
  default: [iOS, macOS]
```

**CLI:**
```bash
--platforms iOS macOS
--platforms iOS,macOS
```

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

## ネストされた hatch

post_hatch から他のテンプレートを呼び出すことができます：

```yaml
post_hatch:
  - if: ___CREATE_TESTS___
    hatch: TestTemplate
    args:
      ___MODULE_NAME___: ___MODULE_NAME___
      ___OUTPUT___: ${{ pre_hatch.setup.outputs.test-dir }}
```

**フィールド:**
- `hatch`: 呼び出すテンプレート名
- `args`: ネストされたテンプレートに渡すマクロ値

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
