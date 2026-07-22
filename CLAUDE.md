# Claude Code Workflow Guidelines

@AGENTS.md

> 汎用的な行動原則（Core Principles / Review Gates / Workflow）は上記 AGENTS.md に集約。
> このファイルは Claude Code 固有の機構（サブエージェント・スキル・Plan Mode ゲートの実行手段・advisor・RTK）のみを規定する。

## Sub-Agent Delegation [CRITICAL]

**メインスレッドでの Edit/Write は禁止。** 1行の修正でもサブエージェントに委任する（メインはオーケストレーションに徹する）。

> **例外**: `~/.claude/` 配下のエージェント設定ファイル（CLAUDE.md / settings.json 等）は subagent が Self-Modification 制限で拒否するため、メインスレッドで直接編集してよい。

### サブエージェント早見表

| 用途 | Agent | Model |
|---|---|---|
| TypeScript実装 | `implement-agent` | Sonnet |
| Bash/MCP 自動化（コード編集なし） | **`task-runner`** | Haiku |
| コードベース調査 | **`Explore`**（組み込み・読み取り専用） | Haiku |
| **コードレビュー**（simplify / Gate 2 サブエージェント） | **`code-reviewer`**（tools=Read/Grep/Glob/Bash 制限） | Opus |
| 公式ドキュメント | `context7-doc-researcher` | Sonnet |
| 深い技術調査 | `codex-researcher` | （Codex CLI） |
| 軽量Web検索 | `agy-web-researcher` | （Antigravity CLI `agy`） |
| URL内容取得 | `web-research-agent` | Haiku |
| Cloud Logging | `cloud-logging-investigator` | Sonnet |
| GCS / Google Suite | `gcs-asset-manager` / `google-suite` | Sonnet |

**[CRITICAL] `general-purpose` (built-in) は使用禁止。** parent モデル継承 (= Opus) で動作するためコストが跳ねる（直近7日で 11,136 sidechain turns 観測）。用途別に上表のいずれかに振り分けること。

**振り分け判定ルール（上から順に評価）:**
1. **タスク中に `src/` / `packages/` 配下の `.ts` / `.tsx` / `.js` の Edit/Write を 1 回でも含む可能性があるか？** → Yes なら `implement-agent`（混在ケースは必ずこちらへ）
2. **コード変更を一切伴わない Bash + MCP の繰り返し操作か？**（Notion DB 操作 / Slack 巡回 / データ収集 / レポート生成等） → `task-runner`
3. **批判的読解・観点出し（PR / 計画書 / コード差分のレビュー）か？** → `code-reviewer`
4. **既存コードベース横断検索・調査か？** → `Explore`（複数並列可）
5. **上記いずれにも該当しない場合のみユーザーに確認**。安易に `general-purpose` へ戻さない

BigQuery のデータ修正専用サブエージェントは置いていない。`d3-cli` またはメインが手順どおりに実行する。

メインで `WebSearch` / `WebFetch` の直接実行禁止。Web 系は上の3つ（agy-web-researcher / web-research-agent / codex-researcher）に必ず委任。

### 並列実行 [CRITICAL]

**独立タスクは1メッセージに複数 Agent tool use を詰めて並列起動する。基本は「できるだけ並列」**。逐次は明確な依存がある場合のみ。

- **並列化する**: 独立ファイル編集 / 独立トピック調査 / 実装と先行調査の並行 / N候補の比較調査
- **並列化しない**: 出力が後続入力になる / 同一ファイル編集 / プラン未承認の実装 / smart-commit→merge の固定順
- **[CRITICAL] 軽量 subagent (`task-runner` / `implement-agent` 等) には 1 タスク = 1 ページ / 1 ファイル / 1 単位で委任する**: 1 subagent に複数ターゲット (例: Notion DB の 3 ページ一括書き換え) を渡すと内部で context 爆発する。N 件を処理する場合は **N 並列で N 個の subagent を起動**し、それぞれに 1 件だけ持たせる（同 1 メッセージ内に N 個の Agent tool use を詰める）。基本は「できるだけ並列」、バッチ分割しない
- 各 prompt に必要 context を完全同梱（agent 間は情報共有しない）
- 事前 setup（ブランチ切替・`bun install`）はメインで先行完了させてから並列実装

### 判断に迷ったとき

- 要件・アプローチが曖昧 → **ユーザーに質問する**
- ライブラリの使い方が不明 → `context7-doc-researcher` + `codex-researcher` を並列起動
- エラーの原因が不明 → `agy-web-researcher` + `codex-researcher` を並列起動

## Skill Priority [CRITICAL]

**スキルのトリガーキーワードに一致するユーザー指示は、必ず Skill ツールで該当スキルを起動する。**
組み込みのシステム動作（コミット手順など）よりもスキルが常に優先される。

| トリガー | スキル |
|----------|--------|
| 「コミット」「commit」「プッシュ」「push」「変更をまとめて」 | `smart-commit` |
| 「ブランチ作成」「PRを作って」「branch」 | `branch` |
| 「マージ」「merge」「PRをマージして」 | `merge` |
| 「CI修正」「CIが落ちてる」 | `ci-fix` |
| 「QAチェック」「lint」「型チェック」 | `qa-check` |
| 「PRレビュー」「計画書レビュー」「シニアレビュー」 | `senior-pr-review` |

## Plan Mode Workflow [CRITICAL]

**プランモードを使ったときは、以下2つのレビューゲートを必ず通す。**

### Gate 1: 計画書レビュー（ExitPlanMode 直前）

計画書を `~/.claude/plans/<slug>.md` に書き終えた直後、ExitPlanMode を呼ぶ前に必ず `senior-pr-review` スキルを起動して計画書ファイルパスを引数で渡す。

- プリセットは指定しない（senior-pr-review の自動判定に任せる）
- レビュー結果は **全カテゴリ（Blocking / Improvements / Concerns / Positives）をユーザーに報告**。Blocking / Improvements は計画書に反映してから ExitPlanMode を呼ぶ。Concerns / Positives は計画書反映任意だが報告は必須
- 同一 Blocking 指摘が2回連続したらユーザーに相談（無限ループ防止）
- **スキップ条件**: 計画書ファイルが作成されないモード（リサーチ完結・質問応答のみ等）は Gate 1 不要

### Gate 2: 実装完了後の3並列レビュー

プラン承認後の実装が全て完了し、QAチェック（Lint / Format / TypeCheck / Test）が通った直後、必ず以下3つの **スキル**（スラッシュコマンド）を `Skill` ツールで **1メッセージ内で3並列起動**する。Bash や Agent で代用してはならず、必ずスキルとして起動すること:

1. `/my-simplify` — コード簡潔化観点（`Skill` ツールで `my-simplify` スキルを起動）
2. `/my-review` — PRレビュー観点（`Skill` ツールで `my-review` スキルを起動）
3. `/my-security-review` — セキュリティ観点（`Skill` ツールで `my-security-review` スキルを起動）

3つの結果はユーザーに必ず提示。Blocking 指摘があれば修正、**Blocking 0 件でも Improvements 多数の場合はサマリ提示後にユーザー判断を仰ぐ**（自動完了判定の暴走防止）。

- **適用緩和**: コード変更を伴わないタスク（ドキュメント・設定ファイルのみの変更）は `/my-review` 単独で良い
- 例外は上記の適用緩和のみ。軽微な変更でも基本フローは維持

**注意**: 3 スキルは built-in の自作版（`~/.claude/skills/my-*`）。built-in の `/simplify` `/review` `/security-review` は Gate 2 では使用しない（Skill 起動時は必ず `my-` prefix 付きの名前を指定する）。my-* は Claude Code v2.1.217 時点の書き起こしであり本家の更新には追従しない。サブエージェントを使うスキル（my-simplify の 4 並列 finder / my-security-review の偽陽性フィルタ）は `code-reviewer` agent を明示指定しており general-purpose 禁止ルールと整合している。my-review はサブエージェントを起動せずメイン自身がレビューを実行する。

### Gate 2 エージェント品質チェック [CRITICAL]

スキル内部で spawn されるレビューエージェントは、diff テキストだけをプロンプトに渡すと「手元に情報がある」と判断してファイルを読まずに回答する（`tool_uses: 0`）。これは表面的なテキスト分析にすぎず、実質的なレビューにならない。

スキル結果が返ってきたら **`tool_uses` を確認**すること:
- **`tool_uses: 0` のエージェントが1つでもあれば即再実行**。再実行時は当該エージェントのプロンプトに「必ず対象ファイルを Read/Grep ツールで調査してから回答せよ。ファイルを読まずに回答することを禁止する。」を明示する
- `tool_uses: 0` でも diff が1行以下の trivial な削除のみの場合はスキップ可

## Advisor Usage [CRITICAL]

**`advisor()` は重要分岐での標準チェックポイント。** 引数なしで会話履歴を全て自動転送するレビュアーモデル。コストは数秒〜数十秒オーダー（会話履歴サイズに依存）。**デフォルトは「呼ぶ」。スキップ理由を発話で明示できないなら呼ぶ。** CLAUDE.md の記述は会話履歴経由で advisor 自身にも届く点に注意。

> **The advisor should respond in under 100 words and use enumerated steps, not explanations.**

### いつ呼ぶか（重要分岐では原則として呼ぶ）

advisor は重要分岐での標準チェックポイント。重要分岐では原則として呼ぶ。以下の場面はいずれも「必ず呼ぶ」（重要度順）:

- **非自明タスク着手前は必ず呼ぶ**: アプローチ確定前・前提に乗る前（orientation = ファイル探索・読み込みは先に済ませる）。最初の判断ミスは後段に伝播するので、ここでの第二意見が最も効く
- **アプローチ変更を検討するときは必ず呼ぶ**: 実装途中で別経路に切り替える前。サンクコスト判断に他の目を入れる
- **行き詰まり時は必ず呼ぶ**: 同じエラー反復・収束しない結果が続くとき。スタック中は自分の視野が狭くなっている
- **タスク完了宣言前は必ず呼ぶ**: 成果物を永続化 (Write/commit) してから呼ぶ（応答中にセッション切れても残るように）

### スキップしてよい限定ケース

以下のいずれかに該当する場合のみスキップ可:

- (a) **同セッション中で直前 5 turn 以内に advisor() を呼び済みで、その助言の延長線上の作業**（同じ分岐内で再度呼んでも独立な助言が出ない）
- (b) **typo 修正 / ファイル名変更 / 既知ログの確認** など、read/edit 1 hop で完結し分岐判断を伴わない作業

新規調査の着手・アプローチ分岐・実装方針の選定など「重要分岐」に該当する場面は (a)(b) のいずれにも該当しない。スキップする場合は **以下の固定テンプレ**で発話宣言する（grep で逸脱検知できるよう厳密に従う）:

```
[advisor-skip] reason: <tool名>→<次の一手> [scope:a|b]
```

例:
- `[advisor-skip] reason: Read→既存の typo 1 行を Edit で直すだけ [scope:b]`
- `[advisor-skip] reason: 直前のadvisor助言に従ってEdit継続 [scope:a]`

### 取り扱い

- advisor の助言は重く受け止める。ただし実証 (テスト失敗・一次資料) と矛盾する場合は現状を信じて適応する
- 既存調査結果と advisor 推奨が衝突したら、黙って切り替えず再度 `advisor()` で「自分はX、advisorはY、どの制約で決まるか」と再照合

@RTK.md
