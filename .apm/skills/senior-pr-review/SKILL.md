---
name: senior-pr-review
description: "PR や計画書を senior reviewer 観点で 4 区分（Blocking / Improvements / Concerns / Positives）レビュー。Codex 代替として `code-reviewer` subagent で並列起動可能。「PRレビュー」「PRをレビュー」「PRをレビューして」「senior review」「コードレビュー」「コードレビューして」「計画書レビュー」「計画書をレビュー」「Codexの代わりに」「シニアレビュー」で起動。"
when_to_use: |
  PR (番号指定) や計画書 (ローカル md ファイル) を senior reviewer 観点で品質レビューしたい時、ユーザーから「PRレビュー」「コードレビュー」「計画書レビュー」「シニアレビュー」「Codexの代わりに」など明示的な指示があった場合に限り起動する。
  以下のケースでは本スキルを起動せず、対応スキル/ツールへ委譲する:
  - Codex が利用可能で軽量レビューで十分 → Codex を直接起動 (本スキルは Codex 代替経路)
  - レビューだけでなくコード修正もしたい → implement-agent (本スキルはレポートのみ、Edit/Write 禁止)
  - 計画書を新規執筆したい → Plan Mode / deep-plan
  - CI が落ちた原因の特定・修正 → ci-fix スキル
  - 単純な lint / 型エラー確認 → qa-check スキル
  以下のケースでは並列規模を絞って起動:
  - diff 200 行未満の small PR → 並列せず単独 subagent 1 つ (オーバーヘッド > メリット)
  - diff 200–800 行 → 2 並列まで
  - diff 800 行超 → 3〜5 並列、または `--parallel` でセクション分割指定
model: opus
context: fork
agent: code-reviewer
allowed-tools: Bash, Read, Glob, Grep, Agent
---

# Senior PR / Plan Review

PR や計画書を senior reviewer の目線でレビューする。Codex を観点違いで並列起動して 4 区分レポートを得る Phase 0–5 の流儀を、Claude Code の `code-reviewer` subagent で再現する。Codex がレート制限のときの代替経路でもある。

## 1. トリガー条件と入力

### 起動形式

```
/senior-pr-review <PR番号|file-path> [--parallel <preset1>,<preset2>,...] [--observ <preset>]
```

- `<PR番号>`: 対象 PR の番号 (e.g. `1339`)。`gh pr diff <番号>` でレビュー対象 diff を取得
- `<file-path>`: 計画書などローカルファイルの絶対パス (e.g. `~/.claude/plans/<slug>.md`)
- `--parallel <preset1>,<preset2>`: **観点別 subagent を 1 メッセージ内で並列起動**。preset は `observ-presets.md` 参照
- `--observ <preset>`: 単独レビュー。preset 1 つだけ
- どちらも未指定: **自動判定** (下記)

### 自動判定ルール

PR の場合、`gh pr diff` の内容から推論:

| 内容 | 採用 preset |
|------|-------------|
| `.sql` ファイル / BQ クエリ / Dataform 変更を含む | `data` |
| `.tsx` / `Component` / `app/`, `components/` 配下の変更を含む | `ui` |
| 上記両方を含む | `data` + `ui` の **2 並列** |
| 認証・入力検証・トークン処理を含む | `sec` を追加 |
| 純粋に型定義のみ (`*.types.ts` 等) | `types` |
| `.sql` 単独 (BQ コスト懸念) | `sql` |

計画書 (`*.md`) の場合、§ヘッダや「実装ファイル」セクションをスキャンして同じルールで推論。判別不能なら `data` + `ui` を default として並列起動する。

### 並列規模の制限 (リスク R1)

- **diff < 200 行 (small PR)**: 並列せず単独レビュー (`--observ` で 1 preset のみ)。並列オーバーヘッド > メリット
- **diff 200–800 行**: 2 並列まで
- **diff > 800 行**: 3〜5 並列まで OK。または `--parallel` でセクション分割指定

## 2. 観点プリセットの選択

実行前に必ず `Read` で `~/.claude/skills/senior-pr-review/observ-presets.md` を読み、選択した preset の「特に厳しく見るべき点」「典型 Blocking 例」を取得する。

選択した preset を 1 行宣言してから subagent 起動:

```
[senior-pr-review] preset: data, ui (2 並列)
```

## 3. PR diff or 計画書の取得

### PR の場合

```bash
mkdir -p /tmp/senior-pr-review
gh pr diff <番号> > /tmp/senior-pr-review/pr-<番号>.diff
gh pr view <番号> --json title,body,files > /tmp/senior-pr-review/pr-<番号>.meta.json
wc -l /tmp/senior-pr-review/pr-<番号>.diff
```

- `wc -l` の結果で並列規模を最終決定 (前章のルール)
- diff > 800 行で `--parallel` 未指定なら **セクション別分割**: `gh pr diff <番号> --name-only` でファイル一覧を取り、preset と相性のいいファイル群ごとに subagent を割り当てる

### 計画書の場合

- 直接 `<file-path>` を subagent に渡す (subagent が `Read` する)
- 巨大計画書 (> 1000 行) は section 単位 (`§4 PR-Xa` 等) で部分レビューを subagent に指示

## 4. 並列レビューの起動

**1 メッセージ内に複数 `Agent` tool use を並置して同時発火** する (CLAUDE.md `並列実行` ルール準拠)。逐次起動は禁止。

各 subagent (`code-reviewer`) に渡す prompt の構造:

```
あなたは senior code reviewer です。観点 [preset 名] で以下の対象を厳しくレビューし、レポートのみ返してください。

## 対象
- PR diff: /tmp/senior-pr-review/pr-<番号>.diff
- PR メタデータ: /tmp/senior-pr-review/pr-<番号>.meta.json
- (計画書の場合) 計画書: <file-path> の §X.Y を中心に

## 観点
~/.claude/skills/senior-pr-review/observ-presets.md の `## [preset]` セクションを Read し、「特に厳しく見るべき点」のチェックリストを 1 項目ずつ確認すること。「典型的な Blocking 例」と類似のパターンを見つけたら必ず Blocking として挙げる。

## 出力
~/.claude/skills/senior-pr-review/output-template.md の形式に厳密に従う。各指摘には**必ず根拠 (file:line または plan §X.Y) を付ける**。根拠なしの指摘は禁止。

## 厳守事項
- **コード修正は禁止**。Edit / Write 系ツールは使わない
- 推測で書かず、diff / 計画書に明示されている事実だけを根拠にする
- 関連ファイル参照のため `Read` / `Grep` / `Glob` は OK
- レポートのみを返す
```

### 並列起動の例

PR #1339 を `data` + `types` で並列レビューする場合、**1 メッセージに 2 つの Agent tool use を置く**:

- Agent 1: prompt に `preset: data` 指定
- Agent 2: prompt に `preset: types` 指定

両方が同時に実行され、結果を待ってから集約に進む。

## 5. 小さい PR (< 200 行) の特例

`wc -l /tmp/senior-pr-review/pr-<番号>.diff` で 200 行未満の場合、並列せず **単独 subagent** を 1 つだけ起動 (`--observ` で指定された preset、未指定なら自動判定で 1 つ選ぶ)。

理由: subagent 起動オーバーヘッド (~10–20s × token 倍増) > 観点を分けることのメリット。

## 6. 結果の集約

各 subagent が返す `output-template.md` 形式のレポートを集めたあと、メインで以下を集約:

1. **Blocking 合計**: preset を跨いで重複排除して全件列挙
2. **重複の優先度**: 同じ箇所 (file:line) が複数 preset で Blocking なら最優先
3. **総合判断**:
   - Blocking 0 件 → **GO**
   - Blocking ≥ 1 件、すべて即修正可能 (1 ファイル数行レベル) → **修正後 GO**
   - Blocking に「設計やり直し」「方式変更」レベルが含まれる → **NO-GO**
4. **次アクション**:
   - 修正後 GO の場合、Blocking を実装エージェントに渡せる粒度 (file:line + 修正方針) で整理
   - NO-GO の場合、計画書のどこを直すかを示唆

集約レポートは PR コメントに貼れる Markdown 形式で出力する。

## 7. 使用例

### 例 1: Phase 5 PR-5a を data + types で並列レビュー

```
/senior-pr-review 1339 --parallel data,types
```

→ `gh pr diff 1339` を取得 → 600 行 → `data` + `types` の 2 並列起動 → 各レポートを集約 → 「修正後 GO」総合判断

### 例 2: 計画書を data + ui で並列レビュー

```
/senior-pr-review ~/.claude/plans/<slug>.md --parallel data,ui
```

→ 計画書を直接 subagent に渡す → §4–§5 を観点別にレビュー → 集約

### 例 3: 自動判定 (UI のみの PR)

```
/senior-pr-review 1340
```

→ `gh pr diff 1340` で `.tsx` のみ → 自動判定で `ui` 単独 → 1 subagent 起動

### 例 4: 単独レビュー

```
/senior-pr-review 1341 --observ a11y
```

→ a11y 観点のみで 1 subagent 起動 (例: dialog 追加 PR の a11y 確認)

## 8. dry-run (動作確認)

skill 導入直後の確認用:

```bash
# diff 取得確認
gh pr diff 1339 > /tmp/senior-pr-review/pr-1339.diff
wc -l /tmp/senior-pr-review/pr-1339.diff

# preset 内容確認
cat ~/.claude/skills/senior-pr-review/observ-presets.md | head -40

# template 確認
cat ~/.claude/skills/senior-pr-review/output-template.md
```

3 ファイルが揃って `gh` でも diff が引けるなら skill は起動可能な状態。

## 9. このスキルを使わないケース

| シーン | 使うべきもの |
|--------|--------------|
| Codex が利用可能で軽量レビューしたい | Codex を直接起動 (このスキルは Codex 代替) |
| コードを実際に修正したい | `implement-agent` (本 skill はレポートのみ) |
| 計画書そのものを書きたい | `deep-plan` / Plan Mode |
| CI が落ちている原因の特定 | `ci-fix` |
| 単純な lint / 型エラー確認 | `qa-check` |
