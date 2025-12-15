# Config.swift の Lint チェックリスト

CONFIG_YAML.mdの仕様に基づいて、Config.swiftに対してlintすべき項目を列挙します。

## 1. Config 構造体のバリデーション

### 1.1 必須フィールドのチェック
- [ ] `name`: 空文字列でないことを確認
- [ ] `description`: 空文字列でないことを確認

### 1.2 オプショナルフィールド
- [ ] `macros`: オプショナル（問題なし）
- [ ] `preHatch`: オプショナル（問題なし）
- [ ] `hatch`: オプショナル（問題なし）
- [ ] `postHatch`: オプショナル（問題なし）

## 2. Macro 構造体のバリデーション

### 2.1 必須フィールド
- [ ] `name`: 空文字列でないことを確認
- [ ] `description`: 空文字列でないことを確認

### 2.2 マクロ名の命名規則
- [ ] `name`が `___MACRO_NAME___` 形式（3つのアンダースコアで囲まれた大文字）であることを確認
- [ ] マクロ名に使用可能な文字のみが含まれていることを確認（英数字、アンダースコア）

### 2.3 型に応じたバリデーション

#### 2.3.1 choice型
- [ ] `type`が`.choice`の場合、`choices`が必須であることを確認
- [ ] `choices`が空配列でないことを確認
- [ ] `default`値が`choices`に含まれていることを確認（`default`が指定されている場合）

#### 2.3.2 array型
- [ ] `type`が`.array`の場合、`choices`が指定されている場合は、`default`値の各要素が`choices`に含まれていることを確認
- [ ] `default`値が配列形式の文字列として有効であることを確認（JSON配列形式: `[value1, value2]`）

#### 2.3.3 boolean型
- [ ] `type`が`.boolean`の場合、`default`値が`"true"`または`"false"`であることを確認（指定されている場合）

#### 2.3.4 path型
- [ ] `type`が`.path`の場合、`default`値が有効なパス形式であることを確認（指定されている場合）

#### 2.3.5 string型
- [ ] `type`が`.string`の場合、特に制約なし（デフォルト型）

### 2.4 バリデーション正規表現
- [ ] `validate`が指定されている場合、有効な正規表現であることを確認
- [ ] `validate`が指定されている場合、`default`値が正規表現にマッチすることを確認（`default`が指定されている場合）

### 2.5 デフォルト値の有無
- [ ] `default`が指定されていない場合、マクロは必須入力として扱われる（これは警告のみ、エラーではない）

## 3. LifecycleStep 構造体のバリデーション

### 3.1 必須フィールドの組み合わせ
- [ ] `run`と`hatch`のどちらか一方が必須であることを確認（両方指定されている場合はエラー）
- [ ] `run`も`hatch`も指定されていない場合はエラー

### 3.2 pre_hatch でのバリデーション
- [ ] `preHatch`の各ステップで、`run`が指定されていることを確認（`hatch`は使用不可）
- [ ] `id`が指定されている場合、空文字列でないことを確認
- [ ] `id`が指定されている場合、有効な識別子形式であることを確認（ハイフン、アンダースコア、英数字のみ）

### 3.3 post_hatch でのバリデーション
- [ ] `postHatch`の各ステップで、`run`または`hatch`のいずれかが指定されていることを確認
- [ ] `hatch`が指定されている場合、空文字列でないことを確認
- [ ] `hatch`が指定されている場合、`args`が指定されていることを確認（`args`フィールドがConfig.swiftに存在しない場合は実装が必要）
- [ ] `id`が指定されている場合、空文字列でないことを確認

### 3.4 条件式のバリデーション
- [ ] `if`が指定されている場合、空文字列でないことを確認
- [ ] `if`が指定されている場合、基本的なJavaScript式の構文チェック（オプション、完全な構文チェックは実行時に行う）

### 3.5 Step ID の一意性
- [ ] `preHatch`内で、同じ`id`が重複していないことを確認
- [ ] `postHatch`内で、同じ`id`が重複していないことを確認

### 3.6 実装上の問題
- [ ] `LifecycleStep`に`hatch`フィールドが存在しない（CONFIG_YAML.mdの仕様では`post_hatch`で使用可能）
- [ ] `LifecycleStep`に`args`フィールドが存在しない（CONFIG_YAML.mdの仕様では`post_hatch`で使用可能）

## 4. HatchConfig 構造体のバリデーション

### 4.1 必須フィールド
- [ ] `output`: 空文字列でないことを確認

### 4.2 オプショナルフィールド
- [ ] `exclude`: オプショナル（問題なし）

## 5. ExcludeRule のバリデーション

### 5.1 パス形式
- [ ] `.path(String)`の場合、空文字列でないことを確認
- [ ] `.path(String)`の場合、有効なglobパターン形式であることを確認（オプション）

### 5.2 条件付き除外
- [ ] `.conditional(ConditionalExclude)`の場合、`if`が空文字列でないことを確認
- [ ] `.conditional(ConditionalExclude)`の場合、`paths`が空配列でないことを確認
- [ ] `.conditional(ConditionalExclude)`の場合、`paths`の各要素が空文字列でないことを確認

## 6. ConditionalExclude 構造体のバリデーション

### 6.1 必須フィールド
- [ ] `if`: 空文字列でないことを確認
- [ ] `paths`: 空配列でないことを確認

### 6.2 paths のバリデーション
- [ ] `paths`の各要素が空文字列でないことを確認

## 7. マクロ参照の整合性チェック

### 7.1 マクロ定義の参照
- [ ] `preHatch`の`run`内で使用されているマクロ（`___MACRO_NAME___`形式）が`macros`で定義されていることを確認
- [ ] `postHatch`の`run`内で使用されているマクロが`macros`で定義されていることを確認
- [ ] `hatch.output`内で使用されているマクロが`macros`で定義されているか、またはstep outputs形式（`${{ ... }}`）であることを確認
- [ ] `hatch.exclude`の条件式（`if`）内で使用されているマクロが`macros`で定義されていることを確認
- [ ] `LifecycleStep.if`内で使用されているマクロが`macros`で定義されていることを確認

### 7.2 Step Outputs の参照
- [ ] `${{ pre_hatch.ID.outputs.KEY }}`形式の参照で、`ID`が`preHatch`内に存在することを確認
- [ ] `${{ pre_hatch.ID.outputs.KEY }}`形式の参照で、構文が正しいことを確認

## 8. 循環参照のチェック

### 8.1 ネストされたhatch
- [ ] `postHatch`内の`hatch`フィールドで指定されているテンプレート名が、現在のテンプレート名と異なることを確認（自己参照の防止、オプション）

## 9. データ型の整合性

### 9.1 Macro.default の型
- [ ] `type`が`.boolean`の場合、`default`は`"true"`または`"false"`の文字列であることを確認
- [ ] `type`が`.array`の場合、`default`は配列形式の文字列（`[value1, value2]`）であることを確認
- [ ] `type`が`.choice`の場合、`default`は`choices`に含まれる値であることを確認
- [ ] `type`が`.string`または`.path`の場合、`default`は文字列であることを確認

### 9.2 LifecycleStep.args の型
- [ ] `hatch`が指定されている場合、`args`が`[String: String]`形式であることを確認（実装が必要）

## 10. コーディング規約・ベストプラクティス

### 10.1 命名規則
- [ ] マクロ名が一意であることを確認（`macros`配列内で重複がない）
