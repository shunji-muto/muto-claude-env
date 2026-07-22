---
name: branch
description: ブランチを作成し、変更を適切な粒度でコミット後、ドラフトPRを作成します。「ブランチ作成」「PRを作って」「branch」などのトリガーで起動。
when_to_use: |
  新規ブランチを切り、変更をコミットしてドラフトPRを作るところまでを一括で行いたいとき、ユーザーから「ブランチ作成」「branch」「PRを作って」など明示的な指示があった場合に限り起動する。
  以下のケースでは本スキルを起動せず、対応スキルへ委譲する:
  - 既に作業ブランチ上にいて、コミット・プッシュのみ行いたい → smart-commit スキル
  - 「マージ」「merge」「PRをマージして」 → merge スキル
  - 「CI修正」「CIが落ちてる」 → ci-fix スキル
  - 「QAチェック」「lint」「型チェック」 → qa-check スキル
  以下のケースでは起動せずユーザーに確認:
  - 未コミット変更が無い状態で「ブランチ切って」のみ言われた場合（空PRになるため意図確認）
  - 現在ブランチが既に feature ブランチで、新規ブランチを作るとコンフリクト/取り違えリスクがある場合
  - 「PR作って」が「既存ブランチでPR作る」意味の場合（→ 既存ブランチで `gh pr create` のみ実行）
model: sonnet
context: fork
allowed-tools: Bash, Read, Glob, Grep
---

# ブランチ作成とドラフトPR作成

ユーザの指示または現在の変更内容から適切なブランチを作成し、変更を適切な粒度でコミットした後、GitHub上にドラフトプルリクエストを作成します。

## 実行手順

### 1. ブランチ名の決定

ユーザの指示または現在の変更内容から、適切なブランチ名を生成します。

**ブランチ命名規則:**
- 形式: `<type>/<optional-scope>-<summary-kebab>`
- `type`: `feat` | `fix` | `chore` | `docs` | `refactor` | `test` | `perf` | `ci`
- `optional-scope`: 対象モジュールやサブシステム（必要に応じて短く）
- `summary-kebab`: 指示/変更内容から3〜6語で要約しkebab-case化（記号除去、ASCIIのみ、50文字以内）
- チケットIDがある場合は先頭に付与（例: `ABC-123/feat/user-auth-login`）

**例:**
- `feat/api-add-export-endpoint`
- `fix/ui-button-disabled-state`
- `refactor/database-query-optimization`

### 2. ベースブランチの確認とブランチ作成

```bash
# リポジトリルートへ移動
cd "$(git rev-parse --show-toplevel)"

# ベースブランチを解決（main または master）
git fetch origin --prune

# origin/HEAD から自動検出、なければ main を使用
# 新規ブランチを作成（例: feat/add-export-endpoint）
git checkout -b "$BRANCH_NAME" origin/main
```

### 3. 品質チェック（コミット前必須）

プロジェクトで定義されている品質チェックを実行：

- **Linter/Formatter**: プロジェクトのlintスクリプトを実行（例: `bun run lint`, `npm run lint`）
- **型チェック**: TypeScriptプロジェクトの場合、型チェックを実行（例: `bunx tsc --noEmit`）

エラーがあれば修正してから次のステップへ進みます。

### 4. 変更内容の分析とグループ化

```bash
# 変更されたファイルをリスト
git status

# 変更の統計情報を確認
git diff --stat

# 具体的な変更内容を分析
git diff
```

変更内容を論理的にグループ化：
- **機能追加** (feat): 新機能、新エンドポイント、新コンポーネント
- **バグ修正** (fix): バグ修正、エラー修正
- **リファクタリング** (refactor): 機能変更を伴わないコード改善
- **スタイル修正** (style): フォーマット、空白、コードスタイル
- **ドキュメント** (docs): ドキュメント、コメントの変更
- **テスト** (test): テストコードの追加・修正
- **その他** (chore): ビルド設定、依存関係更新など

### 5. 適切な粒度でコミット

各グループごとに独立したコミットを作成します。

**コミットメッセージ形式（Conventional Commits）:**
```
<type>(<scope>): <subject>

<body>

Co-Authored-By: Claude <noreply@anthropic.com>
```

**コミット作成の原則:**
- 1コミット = 1つの論理的変更
- 各コミットは独立してビルド・テスト可能な状態にする
- 不要なデバッグコード・コメントは削除してからコミット
- `git add -A` は使用禁止（関係ないファイルを含めないため）

### 6. リモートへPush

```bash
# リモートへpush
git push -u origin "$BRANCH_NAME"
```

### 7. ドラフトPR作成

`gh` CLIを使用してドラフトPRを作成：

```bash
# ドラフトPR作成
gh pr create \
  --draft \
  --title "<適切なタイトル>" \
  --body "## Summary
- [変更内容のサマリー]

## Test plan
- [ ] テスト項目

Generated with Claude Code" \
  --base main \
  --head "$BRANCH_NAME"

# 作成されたPRのURLを表示
gh pr view --json url -q .url
```

## 出力

以下の情報を表示：
- 品質チェック結果
- 作成したコミット一覧
- ブランチ名
- ドラフトPRのURL

## 注意事項

- **必ず品質チェックを実施**してからコミット
- 各コミットは論理的に独立した変更単位にする
- コミットメッセージは明確で理解しやすく
- `gh` CLIが未認証の場合は事前に `gh auth login` を実行
- 変更がない場合は、ユーザに確認してからブランチ作成

## 前提条件

- リポジトリがGitHub上の `origin` に設定されていること
- `gh` CLI がインストール・認証済みであること
- 既定のベースブランチは `main`（または `origin/HEAD` から解決）
