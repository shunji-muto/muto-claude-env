# muto-claude-env

shunji-muto の Claude Code 環境（skills / agents / instructions / MCP 設定）を apm で配布するためのパッケージ。

## インストール

```bash
apm install shunji-muto/muto-claude-env
```

## 構成

- `apm.yml` — マニフェスト（`includes` 明示リストが配布対象の正）
- `AGENTS.md` — エージェント非依存の行動原則（Core Principles / Review Gates / Workflow）
- `CLAUDE.md` — Claude Code 固有機構（`@AGENTS.md` import + Gate 2 = my-* 参照）
- `agents/` — サブエージェント定義 10 個（rai 系はローカル専用のため含めない）
- `skills/` — 個人スキル 8 個（smart-commit / branch / merge / senior-pr-review / compact-prompt / visual-qa / ui-tips / grill-me）+ my-* 3 個（配布除外）
- `docs/` — メンテナンス手順

## MCP セットアップ

`apm install` で MCP サーバー設定が `.mcp.json`（Claude Code のプロジェクト設定）に展開される。
**トークンは apm.yml に含めていない**ため、install 先マシンで以下の環境変数を設定すること
（`~/.zshrc` に export。Dock 起動のデスクトップアプリで使う場合は `~/.zshenv` に置く）:

| 環境変数 | 対象 MCP | 内容 |
|---|---|---|
| `CONTEXT7_API_KEY` | context7 | Context7 の API キー（`ctx7sk-...`） |

stitch / n8n-mcp / slack-mcp-for-ai-ops は棚卸しで対象外と判断（2026-07-22）。必要になったら
`transport: http` + `url` + `headers: {${ENV_VAR}}` 形式で宣言を足す。

対象外（宣言しない）:

- **claude.ai コネクタ**（Slack / Notion / Figma / Gmail / Salesforce MCP 等 14 個）— アカウント設定に紐づき自動で付いてくる
- **rai** — マシン固有パス（`~/.config/review-agent-integrator`）依存
- **pencil** — Pencil.app 同梱（アプリを入れれば付く）
- **retool / notion / search-console** — 利用側リポジトリの `.mcp.json` 管轄

## Claude Code Web での利用

リモート Ubuntu コンテナで動く Claude Code Web の Routine 環境向けに、
`bin/claude-code-web-setup.sh` を用意している。冪等スクリプトで、
セッション開始時のフックから呼ぶ想定。

やること:

1. `bun` を導入（未インストール時）
2. Microsoft の apm CLI を導入（`curl -sSL https://aka.ms/apm-unix | sh`）
3. `apm install shunji-muto/muto-claude-env` で本パッケージを展開
4. `~/.claude/skills/create-routine-issue` を展開先へ symlink 貼り直し
5. 必要 env の存在確認（未設定なら警告のみ、続行）

Routine 側で以下を実行（public リポの raw URL から直接取得する — apm 導入前の新品コンテナでも動く bootstrap）:

```bash
curl -fsSL https://raw.githubusercontent.com/shunji-muto/muto-claude-env/main/bin/claude-code-web-setup.sh | bash
```

環境変数（任意）:

| 環境変数 | 用途 |
|---|---|
| `CONTEXT7_API_KEY` | Context7 MCP（任意） |

> ⚠️ Claude Code Web の環境変数欄は**ワークスペース全員に見える**ためトークンを置かないこと。
> `CONTEXT7_API_KEY` 未設定時は context7 が無効になるだけで setup は続行する（スクリプトは警告のみ）。

やらないこと:

- d3-cli install（Web Routine 環境に BQ SA なし）
- gh CLI 認証（GitHub MCP で代替）
- 対象リポジトリの clone / 依存インストール（Web Routine 側の GitHub 連携が担う）

## Routines

dinii-internal-tools の Definition of Ready を満たした Issue を自動実装し、draft PR まで作るための routine 群。

現行の routine: `routines/pick-and-implement.md`

- 想定 cron: 平日 6:00 / 9:00 / 12:00 JST
- pickup 条件: `label:"routine:ready" AND label:"shunji-muto-issue" AND -label:"routine:in-progress"`
- flow: Pickup → Branch → Plan → Gate 1 (senior-pr-review) → Implementation → Gate 2 (simplify/review/security-review) → Adversarial verify → Fix loop → draft PR → Slack notify

Web Routine への登録方法:

1. `routines/pick-and-implement.md` の内容をコピー
2. Claude Code Web の Routine 設定画面に貼り付け
3. cron を設定（上記想定スケジュール）

関連 skill:

- `create-routine-issue` — Issue を対話的に起票し、Definition of Ready を保証する
- `senior-pr-review` — routine 内から Gate 1 で呼ばれる

制約:

- dinii-internal-tools 専用（owner label `shunji-muto-issue` を hard-code）
- Web Routine の secret 機構が未実装のため、対象リポは public のみ（本パッケージ自体も public 化済）

## 注意

- **public リポジトリ**。シークレット・トークン・社内固有情報（バケット名 / プロジェクト ID / 社内リポ名 / 実在メール）はコミット禁止。
- 資産の追加は `~/.claude/` から棚卸しの上でコピーする。
- `skills/my-*` は Claude Code v2.1.217 built-in の書き起こし（gitignore 済み・apm 配布除外・private 利用限定）。本家更新への追従手順はローカル保管の非公開ドキュメント（docs/maintenance-my-skills.md、gitignore 済み）を参照。
