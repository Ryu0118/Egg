# CLI E2E Test Design Document

## Overview

本ドキュメントは、`egg` CLIツールのEnd-to-End (E2E) テストの設計を記述する。E2Eテストでは、実際のバイナリを直接実行し、入力と出力を検証することで、CLIの動作を包括的にテストする。

## Goals

1. 実際のバイナリ (`egg`) を実行してCLIの動作をテストする
2. 各コマンド・サブコマンドの入出力を検証する
3. Swift Testingフレームワークを使用し、カスタムTraitでビルドを一度だけ実行する
4. テストコードの依存関係を最小限に抑える（`ProcessRunning`, `FileManagerProtocol`のみ）

## Architecture

### Directory Structure

```
Tests/
├── EggKitTests/           # 既存のユニットテスト
└── CLITests/              # 新規E2Eテスト
    ├── Support/
    │   ├── BinaryBuildTrait.swift
    │   └── CLIRunner.swift
    └── Commands/
        ├── HatchCommandTests.swift
        ├── TemplateCreateCommandTests.swift
        ├── TemplateListCommandTests.swift
        └── ...
```

### Package.swift

```swift
.testTarget(
    name: "CLITests",
    dependencies: [
        .product(name: "ProcessRunning", package: "ProcessRunning"),
        .product(name: "FileManagerProtocol", package: "FileManagerProtocol"),
    ]
)
```

## Interfaces

### BinaryBuildTrait

```swift
/// Suite全体に適用するビルドTrait
/// テスト実行前に `xcrun swift build --product egg` を実行し、バイナリパスをキャッシュする
struct BinaryBuildTrait: SuiteTrait, TestScoping {
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws
}

extension Trait where Self == BinaryBuildTrait {
    static var buildBinary: Self { get }
}
```

### BinaryBuildState

```swift
/// ビルド結果を保持するグローバルアクター
/// 複数のTest Suite間でビルド結果を共有する
actor BinaryBuildState {
    static let shared: BinaryBuildState

    /// ビルド済みバイナリのパスを取得
    /// 初回呼び出し時にビルドを実行し、以降はキャッシュを返す
    func getBinaryPath() async throws -> URL
}
```

### BinaryBuildError

```swift
/// ビルドエラー
enum BinaryBuildError: Error {
    case buildFailed(exitCode: Int32, output: String)
    case binaryNotFound(path: String)
}
```

### CLIResult

```swift
/// CLI実行結果
struct CLIResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { get }
}
```

### CLIRunner

```swift
/// CLIテストヘルパー
/// ProcessRunningを使用してバイナリを実行し、結果を取得する
struct CLIRunner: Sendable {
    init() async throws

    /// CLIコマンドを実行
    func run(
        _ arguments: String...,
        workingDirectory: URL?,
        environment: [String: String]?
    ) async throws -> CLIResult

    /// CLIコマンドを実行（配列版）
    func run(
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?
    ) async throws -> CLIResult
}
```

## Temporary Directory Management

テスト用一時ディレクトリは `FileManagerProtocol` の既存APIを使用する。

### runInTemporaryDirectory

自動クリーンアップが必要な場合:

```swift
try await fileManager.runInTemporaryDirectory { tempDir in
    // テスト実行
    // クロージャ終了後に自動で削除される
}
```

### makeTemporaryDirectory

手動クリーンアップが必要な場合:

```swift
let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test")
defer { try? fileManager.removeItem(at: tempDir) }
```

## Test Execution Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Test Suite Execution                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. @Suite(.buildBinary) トリガー                                │
│     │                                                            │
│     ▼                                                            │
│  2. BinaryBuildTrait.provideScope() 呼び出し                     │
│     │                                                            │
│     ▼                                                            │
│  3. BinaryBuildState.shared.getBinaryPath()                      │
│     │                                                            │
│     ├─ [初回] xcrun swift build --product egg 実行               │
│     │         └─ ビルド成功 → バイナリパスをキャッシュ            │
│     │                                                            │
│     └─ [2回目以降] キャッシュからバイナリパスを返却               │
│                                                                  │
│  4. テスト関数を実行                                             │
│     │                                                            │
│     ├─ CLIRunner を作成                                          │
│     ├─ runInTemporaryDirectory で一時ディレクトリを作成          │
│     ├─ ProcessRunner でバイナリを実行                            │
│     ├─ 出力・終了コードを検証                                    │
│     └─ 一時ディレクトリは自動クリーンアップ                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Test Target Commands

| Command | Subcommand | Test Scope |
|---------|------------|------------|
| `egg` | - | ヘルプ表示、バージョン表示 |
| `egg hatch` | - | テンプレート適用、マクロ展開、ワークフロー実行 |
| `egg template` | `create` | テンプレート作成 |
| `egg template` | `list` | テンプレート一覧表示 |
| `egg template` | `delete` | テンプレート削除 |
| `egg template` | `duplicate` | テンプレート複製 |
| `egg template` | `move` | テンプレート移動 |
| `egg template` | `open` | テンプレートディレクトリを開く |
| `egg template` | `validate` | config.yaml検証 |
| `egg template` | `install` | テンプレートインストール（テスト用リポジトリ使用） |

## Test Fixtures

### Template Install テスト用リポジトリ

`template install` コマンドのテストには以下のリポジトリを使用する:

- **Repository:** `https://github.com/Ryu0118/swift-egg-templates`
- **用途:** Git URLからのテンプレートインストールテスト

## Environment Variables

| 変数名 | 説明 |
|--------|------|
| `EGG_HOME` | テンプレートディレクトリのルート（テスト用一時ディレクトリを指定） |

## Considerations

### 並列実行

- `.serialized` traitを使用してテストを直列実行する
- 理由：ファイルシステム操作の競合を避けるため

### タイムアウト

- ビルドを含む初回実行は時間がかかるため、適切なタイムアウトを設定

### CI/CD

- `swift test --filter CLITests` でE2Eテストのみ実行可能
- ビルド失敗時はすべてのテストがスキップされる

## References

- [Swift Testing Documentation](https://github.com/swiftlang/swift-testing)
- [New in Swift 6.1: Test Scoping Traits](https://www.pointfree.co/blog/posts/169-new-in-swift-6-1-test-scoping-traits)
- [ProcessRunning](https://github.com/Ryu0118/ProcessRunning)
- [FileManagerProtocol](https://github.com/Ryu0118/FileManagerProtocol)
