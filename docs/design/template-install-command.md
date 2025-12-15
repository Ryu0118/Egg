# Template Install Command Design Document

## Overview

`egg template install` コマンドは、Git リポジトリからテンプレートをインストールする機能を提供する。GitHub, GitLab, Bitbucket, 自前の Git サーバーなど、Git 互換のあらゆるプラットフォームに対応する。

## Issue Reference

- GitHub Issue: https://github.com/Ryu0118/Egg/issues/7

## Requirements

### Functional Requirements

1. Git リポジトリ URL からテンプレートをインストールできる
2. SSH 形式と HTTPS 形式の両方をサポート
3. ブランチ、タグ、リビジョン（コミット SHA）を指定可能
4. デフォルトはリポジトリの既定ブランチ（ref 未指定時は Git に任せる）
5. インタラクティブモードとダイレクトモードの両方をサポート
6. グローバルまたはプロジェクトローカルにインストール可能
7. 特定のテンプレートのみをインストール、または除外できる

### Non-Functional Requirements

1. Git コマンドを使用し、特定のプラットフォーム API に依存しない
2. 既存の Runner/Validator パターンに従う
3. ユーザーの Git 認証設定（SSH 鍵、credential helper）をそのまま利用

## Template Repository Specification

### Repository Structure

テンプレートリポジトリは以下の構造に従う必要がある:

```
repository/
├── <template-name>/           # テンプレートディレクトリ（1つ以上）
│   ├── config.yml             # 必須: テンプレート設定ファイル
│   └── ...                    # テンプレートファイル群
├── <template-name-2>/         # 複数のテンプレートを定義可能
│   ├── config.yml
│   └── ...
├── README.md                  # 任意
└── ...                        # その他任意のファイル
```

### Template Discovery Rules

1. リポジトリのルートディレクトリをスキャン
2. 各サブディレクトリに対して `config.yml` の存在をチェック
3. `ConfigValidator` を使用して各テンプレートを検証
4. 有効なテンプレートのみをフィルタリングしてインストール対象とする
5. テンプレート名はディレクトリ名に依存する

### Example Repository

```
egg-swift-templates/
├── swift-module/
│   ├── config.yml
│   ├── ___MODULE_NAME___.swift
│   └── Tests/
├── swift-package/
│   ├── config.yml
│   ├── Package.swift
│   └── Sources/
├── swiftui-view/
│   ├── config.yml
│   └── ___VIEW_NAME___View.swift
├── README.md
└── LICENSE
```

この場合、`swift-module`, `swift-package`, `swiftui-view` の3つのテンプレートがインストール可能。

## Supported URL Formats

| Format | Example |
|--------|---------|
| HTTPS | `https://github.com/user/repo.git` |
| HTTPS (without .git) | `https://github.com/user/repo` |
| SSH | `git@github.com:user/repo.git` |
| Git Protocol | `git://github.com/user/repo.git` |

## CLI Interface

### Command Syntax

```bash
egg template install [URL] [OPTIONS]
```

### Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `URL` | No (interactive) | Git リポジトリ URL |

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--branch <name>` | `-b` | 特定のブランチからインストール |
| `--tag <name>` | `-t` | 特定のタグからインストール |
| `--revision <sha>` | `-r` | 特定のコミットからインストール |
| `--global` | `-g` | グローバルにインストール (デフォルト: プロジェクトローカル) |
| `--template <name>` | | 指定したテンプレートのみをインストール（複数指定可） |
| `--exclude <name>` | | 指定したテンプレートを除外（複数指定可） |
| `--project-directory <path>` | | プロジェクトディレクトリを指定 |

### Mutual Exclusivity

- `--branch`, `--tag`, `--revision` は相互排他。複数指定された場合はエラー。
- `--template` と `--exclude` は相互排他。複数指定された場合はエラー。

### Usage Examples

```bash
# インタラクティブモード
egg template install

# HTTPS URL からインストール
egg template install https://github.com/Ryu0118/egg-swift-templates.git

# SSH URL からインストール
egg template install git@github.com:Ryu0118/egg-swift-templates.git

# 特定のタグからインストール
egg template install https://github.com/Ryu0118/egg-swift-templates.git --tag v1.0.0

# 特定のブランチからインストール
egg template install https://github.com/Ryu0118/egg-swift-templates.git --branch develop

# グローバルにインストール
egg template install https://github.com/Ryu0118/egg-swift-templates.git --global

# 特定のテンプレートのみインストール
egg template install https://github.com/Ryu0118/egg-swift-templates.git --template swift-module

# 複数のテンプレートを指定してインストール
egg template install https://github.com/Ryu0118/egg-swift-templates.git --template swift-module --template swift-package

# 特定のテンプレートを除外してインストール
egg template install https://github.com/Ryu0118/egg-swift-templates.git --exclude swiftui-view

# 複数のテンプレートを除外
egg template install https://github.com/Ryu0118/egg-swift-templates.git --exclude swiftui-view --exclude swift-package
```

## Execution Flow

### Direct Mode

```
1. URL を解析・検証
2. Git ref (branch/tag/revision) を決定（デフォルト: リポジトリの既定ブランチ = ref を渡さない）
3. 一時ディレクトリにリポジトリをクローン
4. リポジトリ内のディレクトリをスキャン
5. 各ディレクトリに対して ConfigValidator を実行
6. 有効なテンプレートをフィルタリング
7. --template/--exclude オプションに基づいてテンプレートをフィルタリング
8. 既存テンプレートとの名前衝突をチェック
9. 有効なテンプレートをテンプレートディレクトリにコピー
10. 一時ディレクトリをクリーンアップ
11. 結果を表示し、インストール成功数が 0 の場合は `InstallError.allTemplatesSkippedOrFailed` を投げる
```

### Interactive Mode

```
1. URL の入力を促す（バリデーション付き）
2. Git ref の種類を選択（branch/tag/revision/default）
3. 選択に応じて ref 値の入力を促す
4. インストール先を選択（global/project）
5. リポジトリをクローンし、有効なテンプレートを発見
6. インストールするテンプレートを選択（複数選択可）
7. Direct Mode の手順 8-11 を実行
```

## Error Handling

### Error Cases

| Error | Description | Recovery |
|-------|-------------|----------|
| Invalid URL | URL 形式が不正 | エラーメッセージを表示 |
| Clone Failed | Git clone に失敗 | エラーメッセージを表示、認証情報の確認を促す |
| No Valid Templates | 有効なテンプレートが見つからない | エラーメッセージを表示、リポジトリ構造を確認するよう促す |
| Template Exists | 同名のテンプレートが既に存在 | スキップし、警告を表示 |
| Ref Not Found | 指定された branch/tag/revision が存在しない | エラーメッセージを表示 |
| Template Not Found | `--template` で指定されたテンプレートが存在しない | エラーメッセージを表示 |
| Filter Conflict | `--template` と `--exclude` が同時に指定された | エラーメッセージを表示 |

### Partial Success

複数テンプレートのうち一部のみ成功した場合:
- 成功したテンプレートはインストール
- 失敗/スキップしたテンプレートは理由付きで警告を表示（`--exclude` によるスキップも含む）
- 最終的なサマリーを表示。成功数が 0 の場合は `InstallError.allTemplatesSkippedOrFailed` を返し、非 0 の場合のみ成功扱いにする。

## Architecture

### New Components

```
Sources/EggKit/
├── InstallRunner.swift
├── InstallArgumentsValidator.swift
└── Internals/
    ├── GitCloner.swift
    ├── GitURLParser.swift
    └── TemplateDiscoverer.swift

Sources/EggCLI/Commands/
└── InstallCommand.swift
```

### Component Interfaces

#### GitRef

Git の参照（ブランチ、タグ、コミット SHA）を表す。

```swift
package enum GitRef: Equatable, Sendable {
    case branch(String)
    case tag(String)
    case revision(String)
}
```

> `InstallRunnerMode.direct` の `ref` は `nil` を許可し、`nil` の場合は Git にデフォルトブランチ選択を委ねる。

#### GitURL

パースされた Git URL を表す。

```swift
package struct GitURL: Equatable, Sendable {
    let original: String
    let normalized: String  // git clone に渡す正規化された URL
}
```

#### GitURLParsing

Git URL をパースするプロトコル。

```swift
package protocol GitURLParsing: Sendable {
    /// URL 文字列をパースして GitURL を返す
    /// - Parameter urlString: Git リポジトリ URL
    /// - Returns: パースされた GitURL、無効な場合は nil
    func parse(_ urlString: String) -> GitURL?
}
```

#### GitCloning

Git リポジトリをクローンするプロトコル。

```swift
package protocol GitCloning: Sendable {
    /// Git リポジトリを指定されたディレクトリにクローンする
    /// - Parameters:
    ///   - url: Git URL
    ///   - destination: クローン先ディレクトリ
    ///   - ref: Git 参照（branch/tag/revision）、nil の場合はデフォルトブランチ
    /// - Throws: クローンに失敗した場合
    func clone(url: GitURL, to destination: URL, ref: GitRef?) async throws
}
```

#### DiscoveredTemplate

発見されたテンプレートの情報。

```swift
package struct DiscoveredTemplate: Sendable {
    let name: String
    let sourceDirectory: URL
    let config: Config
}
```

#### TemplateDiscovering

リポジトリからテンプレートを発見するプロトコル。

```swift
package protocol TemplateDiscovering: Sendable {
    /// リポジトリディレクトリ内の有効なテンプレートを発見する
    /// - Parameter repositoryDirectory: クローンされたリポジトリのルートディレクトリ
    /// - Returns: 有効なテンプレートのリスト
    func discoverTemplates(in repositoryDirectory: URL) async throws -> [DiscoveredTemplate]
}
```

#### TemplateFilter

インストール対象のテンプレートをフィルタリングする条件を表す。

```swift
package enum TemplateFilter: Equatable, Sendable {
    /// フィルタリングなし（全てのテンプレートをインストール）
    case none
    /// 指定されたテンプレートのみをインストール
    case include([String])
    /// 指定されたテンプレートを除外
    case exclude([String])
}
```

#### InstallRunnerMode

```swift
package enum InstallRunnerMode: Sendable {
    case interactive
    case direct(url: GitURL, ref: GitRef?, location: TemplateLocationType, filter: TemplateFilter)
}
```

#### InstallArgumentsValidator

```swift
package struct InstallArgumentsValidator {
    init(
        url: String?,
        branch: String?,
        tag: String?,
        revision: String?,
        templates: [String],
        excludeTemplates: [String],
        global: Bool,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol
    )

    /// 引数を検証し、RunnerMode を返す
    func validate() async throws -> InstallRunnerMode
}
```

#### InstallRunner

```swift
package struct InstallRunner {
    init(
        mode: InstallRunnerMode,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol,
        gitCloner: some GitCloning,
        templateDiscoverer: some TemplateDiscovering,
        noora: some Noorable
    )

    /// テンプレートのインストールを実行する
    func run() async throws
}
```

#### InstallResult

インストール結果を表す。

```swift
package struct InstallResult: Sendable {
    let installed: [String]           // インストールに成功したテンプレート名
    let skipped: [SkippedTemplate]    // スキップされたテンプレート
    let failed: [FailedTemplate]      // 失敗したテンプレート
}

package struct SkippedTemplate: Sendable {
    let name: String
    let reason: SkipReason
}

package enum SkipReason: Sendable {
    case alreadyExists
    case excludedByFilter
}

package struct FailedTemplate: Sendable {
    let name: String
    let error: Error
}
```

### Error Types

#### GitCloner.Error

```swift
extension GitCloner {
    package enum Error: LocalizedError {
        case cloneFailed(url: String, exitCode: Int32, stderr: String)
        case checkoutFailed(ref: GitRef, exitCode: Int32, stderr: String)
        case refNotFound(ref: GitRef)
    }
}
```

#### GitURLParserError

```swift
package enum GitURLParserError: LocalizedError {
    case invalidURL(String)
}
```

#### InstallError

```swift
package enum InstallError: LocalizedError {
    case noValidTemplatesFound(repositoryURL: String)
    case mutuallyExclusiveRefOptions      // --branch, --tag, --revision の複数指定
    case mutuallyExclusiveFilterOptions   // --template と --exclude の同時指定
    case templateNotFound(names: [String])  // --template で指定されたテンプレートが存在しない
    case allTemplatesSkippedOrFailed
}
```

## Dependencies

### Existing Dependencies (No Changes)

- `ProcessRunning` - Git コマンドの実行
- `Noora` - UI/UX（プロンプト、進捗表示、結果表示）
- `FileManagerProtocol` - ファイル操作
- `ConfigValidator` - テンプレート設定の検証
- `YAMLDecoder` - config.yml のパース

### New Internal Dependencies

- `GitCloner` uses `ProcessRunning`
- `TemplateDiscoverer` uses `ConfigValidator`, `YAMLDecoder`, `FileManagerProtocol`
- `InstallRunner` uses `GitCloner`, `TemplateDiscoverer`, `DirectoryCloning`

## UI/UX

### Interactive Mode Prompts

1. **URL Input**
   ```
   ? Enter the Git repository URL:
   > https://github.com/Ryu0118/egg-swift-templates.git
   ```

2. **Ref Selection**
   ```
   ? How would you like to specify the version?
   > Default (main branch)
     Specific branch
     Specific tag
     Specific commit
   ```

3. **Ref Value Input** (if not default)
   ```
   ? Enter the branch name:
   > develop
   ```

4. **Location Selection**
   ```
   ? Where would you like to install the templates?
   > Project (.egg/templates)
     Global (~/.egg/templates)
   ```

5. **Template Selection** (複数選択)
   ```
   ? Select templates to install:
   > [x] swift-module
     [x] swift-package
     [ ] swiftui-view
   ```

### Progress Display

```
Cloning repository...
Discovering templates...
Found 3 valid templates: swift-module, swift-package, swiftui-view

Installing templates:
  ✓ swift-module
  ✓ swift-package
  ⚠ swiftui-view (skipped: already exists)

Successfully installed 2 templates.
```

### Error Display

```
✗ Failed to clone repository
  URL: https://github.com/Ryu0118/egg-swift-templates.git
  Error: Authentication failed. Please check your credentials.
```

## Testing Strategy

### Unit Tests

1. `GitURLParser` - 各 URL 形式のパース
2. `InstallArgumentsValidator` - 引数バリデーション、相互排他チェック
3. `TemplateDiscoverer` - テンプレート発見ロジック（モック FileManager 使用）

### Integration Tests

1. `GitCloner` - 実際の Git クローン操作（テスト用リポジトリ使用）
2. `InstallRunner` - エンドツーエンドのインストールフロー

### Test Fixtures

- 有効なテンプレートを含むテストリポジトリ
- 無効な config.yml を含むテストケース
- 空のリポジトリ

## Future Considerations

### Potential Enhancements (Out of Scope)

1. **Template Update Command** - インストール済みテンプレートの更新
2. **Template List Sources** - インストール元の表示
3. **Template Pinning** - 特定バージョンへの固定
4. **Private Repository Support Documentation** - SSH 鍵設定のガイド

## Checklist

- [ ] `GitRef` enum の実装
- [ ] `GitURL` struct の実装
- [ ] `GitURLParsing` protocol と `GitURLParser` の実装
- [ ] `GitCloning` protocol と `GitCloner` の実装
- [ ] `DiscoveredTemplate` struct の実装
- [ ] `TemplateDiscovering` protocol と `TemplateDiscoverer` の実装
- [ ] `TemplateFilter` enum の実装
- [ ] `InstallRunnerMode` enum の実装
- [ ] `InstallArgumentsValidator` の実装
- [ ] `InstallRunner` の実装
- [ ] `InstallCommand` の実装
- [ ] エラー型の実装
- [ ] Unit Tests
- [ ] Integration Tests
- [ ] Documentation
