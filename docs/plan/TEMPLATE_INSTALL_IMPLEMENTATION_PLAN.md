# Template Install Command Implementation Plan

## Overview

`egg template install` コマンドの実装計画。Git リポジトリからテンプレートをインストールする機能を提供する。

**Reference Documents:**
- [template-install-command.md](../design/template-install-command.md) - 設計仕様

---

## Prerequisites

実装開始前に確認すべき事項:

- [ ] `template-install-command.md` の設計仕様を完全に理解
- [ ] 既存の Runner/Validator パターンを理解（`CreateRunner`, `CreateArgumentsValidator` 参照）
- [ ] `ProcessRunning` プロトコルの使用方法を理解（`GitRepositoryChecker` 参照）
- [ ] `DirectoryCloning` プロトコルの使用方法を理解
- [ ] `ConfigValidator` の使用方法を理解
- [ ] `TemplatesFinder` の実装を理解
- [ ] テストパターンを理解（`CreateValidatorTests` 参照）

---

## Implementation Phases

### Phase 1: Foundation - Models & Git URL Parser

**Goal:** 基本的な型と Git URL パーサーを実装する。

#### 1.1 GitRef enum

**File:** `Sources/EggKit/Models/GitRef.swift`

```swift
package enum GitRef: Equatable, Sendable, Codable {
    case branch(String)
    case tag(String)
    case revision(String)
}
```

> デフォルトブランチは `GitRef?` を `nil` にすることで表現し、Git が自動的に既定ブランチを選択する。

**Checklist:**
- [x] enum 定義
- [x] `Equatable`, `Sendable`, `Codable` conformance

**Test File:** `Tests/EggKitTests/Models/GitRefTests.swift`
- [x] Codable round-trip test
- [x] Equatable test

---

#### 1.2 GitURL struct

**File:** `Sources/EggKit/Models/GitURL.swift`

```swift
package struct GitURL: Equatable, Sendable {
    package let original: String
    package let normalized: String
}
```

**Checklist:**
- [x] struct 定義
- [x] `Equatable`, `Sendable` conformance

---

#### 1.3 TemplateFilter enum

**File:** `Sources/EggKit/Models/TemplateFilter.swift`

```swift
package enum TemplateFilter: Equatable, Sendable {
    case none
    case include([String])
    case exclude([String])

    func shouldInclude(_ templateName: String) -> Bool
}
```

**Checklist:**
- [x] enum 定義
- [x] `shouldInclude(_:)` メソッド実装
- [x] `Equatable`, `Sendable` conformance

**Test File:** `Tests/EggKitTests/Models/TemplateFilterTests.swift`
- [x] `none` は全てのテンプレートを含む
- [x] `include` は指定されたテンプレートのみを含む
- [x] `exclude` は指定されたテンプレートを除外

---

#### 1.4 GitURLParser

**File:** `Sources/EggKit/Internals/GitURLParser.swift`

**Pattern Conformance:**
- 既存の `Internals/` ディレクトリ内のパターンに従う
- Protocol + 実装の分離

```swift
package protocol GitURLParsing: Sendable {
    func parse(_ urlString: String) -> GitURL?
}

package struct GitURLParser: GitURLParsing {
    package init()
    package func parse(_ urlString: String) -> GitURL?
}
```

**Supported Formats:**
1. `https://github.com/user/repo.git`
2. `https://github.com/user/repo` (without .git)
3. `git@github.com:user/repo.git` (SSH)
4. `git://github.com/user/repo.git` (Git protocol)

**Implementation Notes:**
- 正規表現を使用してパターンマッチング
- SSH 形式は `git@host:path` → `git@host:path` のまま保持（git clone がそのまま受け付ける）
- HTTPS は `.git` サフィックスがなくても許容

**Checklist:**
- [x] Protocol 定義
- [x] 実装
- [x] 各 URL 形式のパース

**Test File:** `Tests/EggKitTests/Internals/GitURLParserTests.swift`
- [x] HTTPS URL with .git suffix
- [x] HTTPS URL without .git suffix
- [x] SSH URL
- [x] Git protocol URL
- [x] Invalid URL returns nil
- [x] Empty string returns nil
- [x] URL with special characters

---

### Phase 2: Git Operations

**Goal:** Git リポジトリのクローン機能を実装する。

#### 2.1 GitCloner

**File:** `Sources/EggKit/Internals/GitCloner.swift`

**Pattern Conformance:**
- `GitRepositoryChecker` のパターンに従う
- `ProcessRunning` を依存性注入

```swift
package protocol GitCloning: Sendable {
    func clone(url: GitURL, to destination: URL, ref: GitRef?) async throws
}

package struct GitCloner: GitCloning {
    private let processRunner: any ProcessRunning

    package init(processRunner: some ProcessRunning = ProcessRunner())

    package func clone(url: GitURL, to destination: URL, ref: GitRef?) async throws
}
```

**Implementation Notes:**

1. **Clone コマンド:**
   ```bash
   # branch/tag の場合
   git clone --branch <ref> <url> <destination>

   # revision の場合
   git clone <url> <destination>
   git -C <destination> checkout <sha>

   # default（ref = nil）の場合
   git clone <url> <destination>  # Git が既定ブランチを自動選択
   ```

2. **エラーハンドリング:**
   - exit code != 0 の場合は stderr を含めてエラーを投げる
   - ref が見つからない場合は専用のエラー

3. **ProcessRunner 使用パターン:**
   ```swift
   let result = try await processRunner.run(
       .path("/usr/bin/git"),
       arguments: Arguments(["clone", "--branch", ref, url, destination]),
       environment: .inherit,
       workingDirectory: nil,
       platformOptions: PlatformOptions(),
       input: .none,
       output: .bytes(limit: 1024 * 1024),  // 1MB
       error: .bytes(limit: 1024 * 1024)
   )
   ```
   ref が `nil` の場合は `--branch` オプションを付与せず、Git のデフォルト挙動に任せる。単純なテンプレートクローン用途のため `--depth` などの最適化フラグは付けない。

**Checklist:**
- [ ] Protocol 定義
- [ ] 実装
- [ ] branch/tag でのクローン
- [ ] revision でのクローン
- [ ] default branch でのクローン
- [ ] エラーハンドリング

**Test File:** `Tests/EggKitTests/Internals/GitClonerTests.swift`

**Unit Tests (Mock ProcessRunner):**
- [ ] 正常なクローン（branch）
- [ ] 正常なクローン（tag）
- [ ] 正常なクローン（revision）
- [ ] 正常なクローン（default）
- [ ] clone 失敗時のエラー
- [ ] checkout 失敗時のエラー

**Integration Tests:**
- [ ] 実際のリポジトリをクローン（テスト用の public リポジトリ使用）

---

#### 2.2 GitCloner.Error

**File:** `Sources/EggKit/Internals/GitCloner.swift`

```swift
extension GitCloner {
    package enum Error: LocalizedError, Equatable {
        case cloneFailed(url: String, exitCode: Int32, stderr: String)
        case checkoutFailed(ref: GitRef, exitCode: Int32, stderr: String)
        case refNotFound(ref: GitRef)
    }
}
```

**Checklist:**
- [ ] Error enum 定義
- [ ] `LocalizedError` conformance（ユーザーフレンドリーなメッセージ）
- [ ] `Equatable` conformance（テスト用）
- [ ] `refNotFound` を `InstallError.refNotFound` と連携

---

### Phase 3: Template Discovery

**Goal:** クローンしたリポジトリからテンプレートを発見する機能を実装する。

#### 3.1 DiscoveredTemplate

**File:** `Sources/EggKit/Models/DiscoveredTemplate.swift`

```swift
package struct DiscoveredTemplate: Sendable {
    package let name: String
    package let sourceDirectory: URL
    package let config: Config
}
```

**Checklist:**
- [x] struct 定義

---

#### 3.2 TemplateDiscoverer

**File:** `Sources/EggKit/Internals/TemplateDiscoverer.swift`

**Pattern Conformance:**
- `TemplatesFinder` のパターンを参考にする
- `ConfigValidator` を使用

```swift
package protocol TemplateDiscovering: Sendable {
    func discoverTemplates(in repositoryDirectory: URL) async throws -> [DiscoveredTemplate]
}

package struct TemplateDiscoverer: TemplateDiscovering {
    private let fileManager: any FileManagerProtocol
    private let validator: ConfigValidator
    private let decoder: YAMLDecoder

    package init(fileManager: some FileManagerProtocol)

    package func discoverTemplates(in repositoryDirectory: URL) async throws -> [DiscoveredTemplate]
}
```

**Implementation Notes:**

1. **Discovery Logic:**
   ```
   1. repositoryDirectory 内のサブディレクトリを列挙
   2. 各サブディレクトリに対して:
      a. config.yml が存在するかチェック
      b. 存在する場合、YAMLDecoder でデコード
      c. ConfigValidator で検証
      d. 有効な場合、DiscoveredTemplate を作成
   3. 有効なテンプレートのリストを返す
   ```

2. **除外するディレクトリ:**
   - `.git`
   - `.github`
   - `node_modules`
   - その他隠しディレクトリ（`.` で始まる）

3. **エラーハンドリング:**
   - 無効なテンプレートは警告をログに出力し、スキップ
   - 全て無効な場合でも空のリストを返す（エラーは投げない）

**Checklist:**
- [x] Protocol 定義
- [x] 実装
- [x] サブディレクトリの列挙
- [x] config.yml の存在チェック
- [x] YAML デコード
- [x] バリデーション
- [x] 隠しディレクトリの除外

**Test File:** `Tests/EggKitTests/Internals/TemplateDiscovererTests.swift`
- [x] 有効なテンプレートを発見
- [x] 複数のテンプレートを発見
- [x] config.yml がないディレクトリはスキップ
- [x] 無効な config.yml はスキップ
- [x] 隠しディレクトリはスキップ
- [x] 空のリポジトリは空のリストを返す

---

### Phase 4: Arguments Validator

**Goal:** コマンドライン引数を検証し、RunnerMode を決定する。

#### 4.1 InstallRunnerMode

**File:** `Sources/EggKit/Models/InstallRunnerMode.swift`

```swift
package enum InstallRunnerMode: Sendable {
    case interactive
    case direct(url: GitURL, ref: GitRef?, location: TemplateLocationType, filter: TemplateFilter)
}
```

**Checklist:**
- [x] enum 定義

---

#### 4.2 InstallArgumentsValidator

**File:** `Sources/EggKit/InstallArgumentsValidator.swift`

**Pattern Conformance:**
- `CreateArgumentsValidator` のパターンに従う
- 既存の Validator と同じ構造

```swift
package struct InstallArgumentsValidator {
    private let url: String?
    private let branch: String?
    private let tag: String?
    private let revision: String?
    private let templates: [String]
    private let excludeTemplates: [String]
    private let global: Bool
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let homeDirectory: URL
    private let gitURLParser: any GitURLParsing

    package init(
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
        fileManager: some FileManagerProtocol,
        gitURLParser: some GitURLParsing = GitURLParser()
    )

    package func validate() async throws -> InstallRunnerMode

    enum Error: LocalizedError { ... }
}
```

**Validation Rules:**

1. **Interactive Mode:**
   - `url` が `nil` の場合

2. **Direct Mode:**
   - `url` が指定されている場合
   - URL を `GitURLParser` でパース
   - `--branch`, `--tag`, `--revision` の相互排他チェック
   - `--template` と `--exclude` の相互排他チェック
   - `TemplateFilter` を構築
   - `TemplateLocationType` を決定

3. **エラーケース:**
   - 無効な URL
   - `--branch`, `--tag`, `--revision` の複数指定
   - `--template` と `--exclude` の同時指定

**Checklist:**
- [x] struct 定義
- [x] `validate()` メソッド実装
- [x] Interactive mode 判定
- [x] URL パース
- [x] Ref 相互排他チェック
- [x] Filter 相互排他チェック
- [x] Error enum 定義

**Test File:** `Tests/EggKitTests/InstallArgumentsValidatorTests.swift`

**Pattern:** `CreateValidatorTests` に従う（`TestCase` struct + `@Test(arguments:)` パターン）

- [x] URL が nil → interactive mode
- [x] URL のみ指定 → direct mode (default branch, no filter)
- [x] URL + branch → direct mode with branch
- [x] URL + tag → direct mode with tag
- [x] URL + revision → direct mode with revision
- [x] URL + branch + tag → error (mutually exclusive)
- [x] URL + template → direct mode with include filter
- [x] URL + exclude → direct mode with exclude filter
- [x] URL + template + exclude → error (mutually exclusive)
- [x] Invalid URL → error
- [x] URL + global → direct mode with global location

---

### Phase 5: Install Runner

**Goal:** インストールのビジネスロジックを実装する。

#### 5.1 InstallResult

**File:** `Sources/EggKit/Models/InstallResult.swift`

```swift
package struct InstallResult: Sendable {
    package let installed: [String]
    package let skipped: [SkippedTemplate]
    package let failed: [FailedTemplate]
}

package struct SkippedTemplate: Sendable {
    package let name: String
    package let reason: SkipReason
}

package enum SkipReason: Sendable {
    case alreadyExists
    case excludedByFilter
}

package struct FailedTemplate: Sendable {
    package let name: String
    package let error: any Error
}
```

**Checklist:**
- [x] struct 定義

---

#### 5.2 InstallRunner

**File:** `Sources/EggKit/InstallRunner.swift`

**Pattern Conformance:**
- `CreateRunner` のパターンに従う
- Interactive/Direct mode の分岐
- Noora を使用した UI

```swift
package struct InstallRunner {
    private let mode: InstallRunnerMode
    private let templatesFinder: TemplatesFinder
    private let templateLocation: any TemplateLocating
    private let gitCloner: any GitCloning
    private let templateDiscoverer: any TemplateDiscovering
    private let directoryCloner: any DirectoryCloning
    private let fileManager: any FileManagerProtocol
    private let noora: any Noorable

    package init(
        mode: InstallRunnerMode,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol,
        gitCloner: some GitCloning = GitCloner(),
        templateDiscoverer: some TemplateDiscovering = TemplateDiscoverer(),
        directoryCloner: some DirectoryCloning = APFSDirectoryCloner(),
        noora: some Noorable = Noora()
    )

    package func run() async throws

    enum Error: LocalizedError { ... }
}
```

**Execution Flow (Direct Mode):**

```
1. 一時ディレクトリを作成
2. GitCloner でリポジトリをクローン
3. TemplateDiscoverer でテンプレートを発見
4. TemplateFilter でフィルタリング
5. --template 指定時、存在しないテンプレートがあればエラー
6. 各テンプレートに対して:
   a. 同名のテンプレートが存在するかチェック
   b. 存在する場合や `TemplateFilter` で除外された場合は理由付きでスキップ
   c. 存在しない場合、DirectoryCloning でコピー
7. 一時ディレクトリを削除
8. 結果を Noora で表示し、`installed` が空なら `InstallError.allTemplatesSkippedOrFailed` を投げる
```

**Execution Flow (Interactive Mode):**

```
1. URL を入力 (noora.textInput)
2. Ref 種類を選択 (noora.singleChoice)
3. Ref 値を入力 (選択に応じて)
4. Location を選択 (noora.singleChoice)
5. 一時ディレクトリを作成
6. GitCloner でリポジトリをクローン
7. TemplateDiscoverer でテンプレートを発見
8. インストールするテンプレートを選択 (noora.multipleChoice)
9. 以降は Direct Mode と同じ（最終サマリーで成功数が 0 の場合はエラー）
```

**Implementation Notes:**

1. **一時ディレクトリ:**
   ```swift
   let tempDir = try fileManager.makeTemporaryDirectory(prefix: "egg-install-")
   defer { try? fileManager.removeItem(at: tempDir) }
   ```

2. **テンプレートのコピー:**
   ```swift
   let destination = templateLocation.template(name, type: locationType)
   try await directoryCloner.clone(from: sourceDir, to: destination)
   ```

3. **進捗表示:**
   - `noora.progressStep` を使用

4. **結果表示:**
   - 成功: `noora.success`
   - 警告（スキップ）: `noora.warning`
   - エラー: `noora.error`

**Checklist:**
- [x] struct 定義
- [x] Direct mode 実装
- [x] Interactive mode 実装
- [x] 一時ディレクトリ管理
- [x] フィルタリングロジック
- [x] 既存テンプレートチェック
- [x] テンプレートコピー
- [x] 結果表示
- [x] Error enum 定義

**Test File:** `Tests/EggKitTests/InstallRunnerTests.swift`

**Unit Tests (Mock dependencies):**
- [x] Direct mode: 全テンプレートインストール成功
- [x] Direct mode: 一部スキップ（既存）
- [x] Direct mode: include filter
- [x] Direct mode: exclude filter
- [x] Direct mode: 存在しないテンプレート指定でエラー
- [x] Direct mode: 有効なテンプレートなしでエラー
- [x] Direct mode: すべてスキップ or 失敗で `InstallError.allTemplatesSkippedOrFailed`
- [x] Interactive mode: 全プロンプト正常
- [x] エラー時のクリーンアップ

---

### Phase 6: CLI Command

**Goal:** ArgumentParser を使用した CLI コマンドを実装する。

#### 6.1 InstallCommand

**File:** `Sources/EggCLI/Commands/InstallCommand.swift`

**Pattern Conformance:**
- `CreateCommand` のパターンに従う
- `HasProjectDirectory` protocol
- ArgumentParser の使用方法

```swift
package extension EggCommand.TemplateCommand {
    struct InstallCommand: AsyncParsableCommand, HasProjectDirectory {
        package static let configuration = CommandConfiguration(
            commandName: "install",
            abstract: "Install templates from a Git repository.",
            discussion: """
            This command supports two modes:

            Interactive Mode:
              When no URL is provided, you will be prompted to enter:
              - Git repository URL
              - Branch, tag, or commit (optional)
              - Installation location (global or project)
              - Templates to install

            Direct Mode:
              Provide the URL and options via command-line arguments.
              Example: egg template install https://github.com/user/repo.git --tag v1.0.0 --global
            """
        )

        @Argument(help: "Git repository URL")
        package var url: String?

        @Option(name: [.short, .long], help: "Install from specific branch")
        package var branch: String?

        @Option(name: [.short, .long], help: "Install from specific tag")
        package var tag: String?

        @Option(name: [.short, .long], help: "Install from specific commit")
        package var revision: String?

        @Option(name: .long, parsing: .upToNextOption, help: "Install only specified templates (can be repeated)")
        package var template: [String] = []

        @Option(name: .long, parsing: .upToNextOption, help: "Exclude specified templates (can be repeated)")
        package var exclude: [String] = []

        @Flag(name: [.short, .long], help: "Install globally")
        package var global: Bool = false

        @Option(name: .long, help: "Project directory")
        package var projectDirectory: String?

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws
        func validate() async throws -> InstallRunnerMode
    }
}
```

**Implementation Notes:**

1. **TemplateCommand への登録:**
   - `EggCommand.TemplateCommand` の `subcommands` に追加

2. **複数値オプション:**
   - `--template` と `--exclude` は `[String]` として受け取る
   - `parsing: .upToNextOption` で複数指定を許可

**Checklist:**
- [x] Command 定義
- [x] ArgumentParser decorators
- [x] `run()` メソッド
- [x] `validate()` メソッド
- [x] TemplateCommand への登録

---

### Phase 7: Integration & Testing

**Goal:** 統合テストとドキュメント整備。

#### 7.1 Integration Tests

**File:** `Tests/EggKitTests/InstallRunnerIntegrationTests.swift`

- [ ] 実際の Git リポジトリからインストール
- [ ] SSH URL でのインストール（環境依存のためスキップ可能）
- [ ] 複数テンプレートのインストール
- [ ] フィルタリング動作

#### 7.2 TemplateCommand 更新

**File:** `Sources/EggCLI/EggCommand.swift`

- [ ] `InstallCommand` を subcommands に追加

---

## Conventions & Patterns

### Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Runner | `{Action}Runner` | `InstallRunner` |
| Validator | `{Action}ArgumentsValidator` | `InstallArgumentsValidator` |
| RunnerMode | `{Action}RunnerMode` | `InstallRunnerMode` |
| Command | `{Action}Command` | `InstallCommand` |
| Protocol | `{Noun}ing` | `GitCloning`, `TemplateDiscovering` |

### File Organization

```
Sources/EggKit/
├── InstallRunner.swift
├── InstallArgumentsValidator.swift
├── Models/
│   ├── GitRef.swift
│   ├── GitURL.swift
│   ├── TemplateFilter.swift
│   ├── DiscoveredTemplate.swift
│   ├── InstallRunnerMode.swift
│   └── InstallResult.swift
└── Internals/
    ├── GitURLParser.swift
    ├── GitCloner.swift
    └── TemplateDiscoverer.swift

Sources/EggCLI/Commands/
└── InstallCommand.swift

Tests/EggKitTests/
├── InstallArgumentsValidatorTests.swift
├── InstallRunnerTests.swift
├── Models/
│   ├── GitRefTests.swift
│   └── TemplateFilterTests.swift
└── Internals/
    ├── GitURLParserTests.swift
    ├── GitClonerTests.swift
    └── TemplateDiscovererTests.swift
```

### Error Handling Pattern

```swift
extension SomeStruct {
    enum Error: LocalizedError, Equatable {
        case someError(context: String)

        var errorDescription: String? {
            switch self {
            case let .someError(context):
                "Description with \(context)"
            }
        }
    }
}
```

### Test Pattern

```swift
struct SomeTests {
    @Test(arguments: TestCase.allCases)
    func validate(_ testCase: TestCase) async throws {
        // Setup
        // Execute
        // Assert
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        // ... other properties
        var testDescription: String { description }
        static let allCases: [TestCase] = [...]
    }
}
```

### Dependency Injection Pattern

```swift
package struct SomeRunner {
    private let dependency: any SomeProtocol

    package init(
        dependency: some SomeProtocol = DefaultImplementation()
    ) {
        self.dependency = dependency
    }
}
```

---

## Test Matrix

### Unit Tests

| Component | Test Cases | Priority |
|-----------|------------|----------|
| `GitURLParser` | 7 | High |
| `GitCloner` | 6 | High |
| `TemplateDiscoverer` | 6 | High |
| `TemplateFilter` | 3 | Medium |
| `InstallArgumentsValidator` | 11 | High |
| `InstallRunner` | 8 | High |

### Integration Tests

| Scenario | Priority |
|----------|----------|
| Clone public repository | High |
| Install single template | High |
| Install multiple templates | Medium |
| Filter with --template | Medium |
| Filter with --exclude | Medium |
| Handle existing template | Medium |

---

## Risk & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Git コマンドが存在しない | High | 事前チェックとユーザーフレンドリーなエラーメッセージ |
| ネットワークエラー | Medium | タイムアウト設定とリトライガイダンス |
| 大きなリポジトリ | Medium | 進捗表示、将来的に `--depth 1` オプション追加検討 |
| 認証エラー | Medium | 明確なエラーメッセージと認証設定のガイダンス |

---

## Checklist Summary

### Phase 1: Foundation
- [x] `GitRef` enum
- [x] `GitURL` struct
- [x] `TemplateFilter` enum
- [x] `GitURLParser` + Tests

### Phase 2: Git Operations
- [x] `GitCloner` + Tests

### Phase 3: Template Discovery
- [x] `DiscoveredTemplate` struct
- [x] `TemplateDiscoverer` + Tests

### Phase 4: Arguments Validator
- [x] `InstallRunnerMode` enum
- [x] `InstallArgumentsValidator` + Tests

### Phase 5: Install Runner
- [x] `InstallResult` structs
- [x] `InstallRunner` + Tests

### Phase 6: CLI Command
- [x] `InstallCommand`
- [x] TemplateCommand への登録

### Phase 7: Integration
- [ ] Integration Tests
- [ ] 動作確認
