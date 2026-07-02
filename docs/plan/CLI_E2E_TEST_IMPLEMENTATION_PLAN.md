# CLI E2E Test Implementation Plan

## Overview

本ドキュメントは、`docs/design/CLI_E2E_TEST_DESIGN.md` の設計に基づいた CLI E2E テストの実装計画を記述する。

## Target Directory Structure

```
Tests/
├── EggKitTests/           # 既存のユニットテスト
└── CLITests/              # 新規E2Eテスト
    ├── Support/
    │   ├── BinaryBuildTrait.swift
    │   ├── BinaryBuildState.swift
    │   ├── BinaryBuildError.swift
    │   ├── CLIRunner.swift
    │   └── CLIResult.swift
    └── Commands/
        ├── EggCommandTests.swift
        ├── HatchCommandTests.swift
        ├── TemplateCreateCommandTests.swift
        ├── TemplateListCommandTests.swift
        ├── TemplateDeleteCommandTests.swift
        ├── TemplateDuplicateCommandTests.swift
        ├── TemplateMoveCommandTests.swift
        ├── TemplateOpenCommandTests.swift
        ├── TemplateValidateCommandTests.swift
        └── TemplateInstallCommandTests.swift
```

---

## Phase 1: Infrastructure Setup ✅

**Goal:** テストターゲット、ディレクトリ構造、バイナリビルドインフラの構築

### Tasks

1. **Package.swift の更新** ✅
   - [x] `CLITests` テストターゲットを追加
   - [x] 依存関係: `ProcessRunning`, `FileManagerProtocol`

2. **ディレクトリ構造の作成** ✅
   - [x] `Tests/CLITests/`
   - [x] `Tests/CLITests/Support/`
   - [x] `Tests/CLITests/Commands/`

3. **BinaryBuildError の実装** ✅
   - [x] `buildFailed(exitCode:output:)` ケース
   - [x] `binaryNotFound(path:)` ケース

4. **BinaryBuildState の実装** ✅
   - [x] `shared` シングルトン
   - [x] `getBinaryPath()` メソッド（キャッシュ機能付き）
   - [x] `buildBinary()` プライベートメソッド
   - [x] `findPackageRoot()` ヘルパー

5. **BinaryBuildTrait の実装** ✅
   - [x] `SuiteTrait`, `TestScoping` 準拠
   - [x] `provideScope(for:testCase:performing:)` メソッド
   - [x] `.buildBinary` 静的プロパティ

### Deliverables

- [x] `Package.swift` (更新)
- [x] `Tests/CLITests/Support/BinaryBuildError.swift`
- [x] `Tests/CLITests/Support/BinaryBuildState.swift`
- [x] `Tests/CLITests/Support/BinaryBuildTrait.swift`

---

## Phase 2: CLIRunner Implementation ✅

**Goal:** CLI実行ヘルパーと結果型の実装

### Tasks

1. **CLIResult の実装** ✅
   - [x] `exitCode`, `stdout`, `stderr` プロパティ
   - [x] `succeeded` 算出プロパティ
   - [x] `Sendable` 準拠

2. **CLIRunner の実装** ✅
   - [x] async イニシャライザ（バイナリパス取得）
   - [x] `run(_:workingDirectory:environment:)` 可変長引数メソッド
   - [x] `run(arguments:workingDirectory:environment:)` 配列メソッド
   - [x] `Sendable` 準拠

### Deliverables

- [x] `Tests/CLITests/Support/CLIResult.swift`
- [x] `Tests/CLITests/Support/CLIRunner.swift`

---

## Phase 3: Basic Command Tests ✅

**Goal:** ヘルプとバージョンコマンドのテスト実装

### Tasks

1. **EggCommandTests の実装** ✅
   - [x] `--help` フラグテスト
   - [x] `-h` フラグテスト
   - [x] 引数なし動作テスト
   - [x] 無効サブコマンドテスト
   - [x] `template --help` テスト
   - [x] `hatch --help` テスト

### Deliverables

- [x] `Tests/CLITests/Commands/EggCommandTests.swift`

---

## Phase 4: Template Command Tests ✅

**Goal:** テンプレート管理コマンドのテスト実装

### Tasks

1. **TemplateCreateCommandTests** ✅
   - [x] `--help` 出力テスト
   - [x] グローバルロケーションへの作成テスト
   - [x] プロジェクトロケーションへの作成テスト
   - [x] `--skip-config` フラグテスト
   - [x] テンプレート既存時のエラーテスト

2. **TemplateListCommandTests** ✅
   - [x] `--help` 出力テスト
   - [x] テンプレートなしの表示テスト
   - [x] 既存テンプレートの表示テスト
   - [x] `--location` フィルターテスト
   - [x] `--hide-description` フラグテスト

3. **TemplateDeleteCommandTests** ✅
   - [x] `--help` 出力テスト
   - [x] `--force` フラグでの削除テスト
   - [x] 存在しないテンプレートのエラーテスト

4. **TemplateDuplicateCommandTests** ✅
   - [x] `--help` 出力テスト
   - [x] テンプレート複製テスト
   - [x] 新しい名前・説明での複製テスト
   - [x] 存在しないテンプレートのエラーテスト
   - [x] 重複名のエラーテスト

5. **TemplateMoveCommandTests** ✅
   - [x] `--help` 出力テスト
   - [x] ロケーション間の移動テスト
   - [x] `--force` フラグによる上書きテスト
   - [x] 存在しないテンプレートのエラーテスト
   - [x] 移動先に既存テンプレートがある場合のエラーテスト

6. **TemplateValidateCommandTests** ✅
   - [x] `--help` 出力テスト
   - [x] 有効なconfigの検証テスト
   - [x] 無効なconfigの検証テスト
   - [x] config.yml 欠落時のエラーテスト

7. **TemplateOpenCommandTests** ✅
   - [x] `--help` 出力テスト

### Deliverables

- [x] `Tests/CLITests/Commands/TemplateCreateCommandTests.swift`
- [x] `Tests/CLITests/Commands/TemplateListCommandTests.swift`
- [x] `Tests/CLITests/Commands/TemplateDeleteCommandTests.swift`
- [x] `Tests/CLITests/Commands/TemplateDuplicateCommandTests.swift`
- [x] `Tests/CLITests/Commands/TemplateMoveCommandTests.swift`
- [x] `Tests/CLITests/Commands/TemplateValidateCommandTests.swift`
- [x] `Tests/CLITests/Commands/TemplateOpenCommandTests.swift`

---

## Phase 5: Template Install Tests

**Goal:** リモートリポジトリからのテンプレートインストールテスト

### Test Repository

- **URL:** `https://github.com/Ryu0118/swift-egg-templates`

### Tasks

1. **TemplateInstallCommandTests**
   - `--help` 出力テスト
   - リポジトリからのインストールテスト
   - `--template` フィルターテスト
   - `--exclude` フィルターテスト
   - プロジェクトロケーションへのインストールテスト
   - `--force` フラグテスト
   - `--branch`, `--tag`, `--revision` オプションテスト
   - 無効なURLのエラーハンドリングテスト
   - 存在しないリポジトリのエラーハンドリングテスト

### Deliverables

- `Tests/CLITests/Commands/TemplateInstallCommandTests.swift`

---

## Phase 6: Hatch Command Tests

**Goal:** テンプレート実行コマンドのテスト

### Tasks

1. **HatchCommandTests**
   - `--help` 出力テスト
   - 基本的なテンプレート実行テスト
   - マクロ置換テスト
   - 存在しないテンプレートのエラーテスト
   - `--no-staging` フラグテスト
   - `--no-sandbox` フラグテスト
   - `--override-conflicts` フラグテスト
   - `--apply-changes` フラグテスト
   - `pre_hatch` / `post_hatch` ライフサイクルスクリプトテスト

### Deliverables

- `Tests/CLITests/Commands/HatchCommandTests.swift`

---

## Summary

| Phase | Deliverables | Description |
|-------|--------------|-------------|
| 1 | 4 files | インフラストラクチャ構築 |
| 2 | 2 files | CLI実行ヘルパー |
| 3 | 1 file | 基本コマンドテスト |
| 4 | 7 files | テンプレート管理テスト |
| 5 | 1 file | リモートインストールテスト |
| 6 | 1 file | テンプレート実行テスト |
| **Total** | **16 files** | |

---

## Notes

### 並列実行

- `.serialized` traitを使用してファイルシステム競合を防止

### 一時ディレクトリ管理

```swift
let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test")
defer { try? fileManager.removeItem(at: tempDir) }
```

### ネットワークテスト

- Phase 5 のテストはネットワークアクセスが必要
- git clone 操作により低速になる可能性あり

### タイムアウト

- 初回テスト実行はバイナリビルドにより低速
- 以降のテストはキャッシュされたバイナリを使用
