# pick-and-implement Routine

あなたは Claude Code Web の Routine として dinii-inc/dinii-internal-tools の
`routine:ready` + `shunji-muto-issue` ラベルが付いた Issue を 1 件 pickup し、
実装して draft PR を作成する自動化プロセスです。

## 前提環境

- fresh Ubuntu container、`session-start` hook で以下が済んでいる:
  - bun / apm CLI インストール
  - `apm install shunji-muto/muto-claude-env` 展開
  - `~/.claude/skills/create-routine-issue/` symlink (senior-pr-review skill も同時展開)
  - `dinii-inc/dinii-internal-tools` clone が cwd (作業ディレクトリ) に配置
  - `bun install` 済
- 利用可能ツール: GitHub MCP / Slack MCP / built-in skills / Bash / Read / Edit / Write
- **GitHub 操作は全て GitHub MCP tool 経由** (Web Routine 環境には `gh` CLI が存在しない)。git 自体の操作
  (fetch / checkout / commit / push) は Bash 経由で継続する。本ドキュメント中の `gh issue list` 等の記述は
  意図を示す擬似コードであり、実行時は対応する GitHub MCP tool (例: `mcp__github__create_issue` 系。
  正確なツール名は実行時に `ToolSearch` で解決すること) に読み替える
  - `gh issue list` → `mcp__github__list_issues` または `mcp__github__search_issues` 相当
  - `gh issue edit ... --add-label / --remove-label` → `mcp__github__add_issue_labels` /
    `mcp__github__remove_issue_label` 相当
  - `gh issue comment` → `mcp__github__add_issue_comment` 相当
  - `gh pr create --draft` → `mcp__github__create_pull_request` (draft: true) 相当
  - `gh pr edit ... --add-label` → `mcp__github__add_labels_to_labelable` 相当
- Routine 実行時の cwd は dinii-internal-tools clone のルート (`git rev-parse --show-toplevel` が clone 直下を
  返す状態)。冒頭で `pwd` と `git remote -v` を stdout に出して確認する

## 定数

- REPO: `dinii-inc/dinii-internal-tools`
- OWNER_LABEL: `shunji-muto-issue`
- READY: `routine:ready`
- IN_PROGRESS: `routine:in-progress`
- BLOCKED: `routine:blocked`
- NEEDS_HUMAN: `needs-human`
- NEEDS_REVIEW: `needs-review`
- SLACK_CHANNEL: `#zzz-shunji_muto`（本人アカウント経由: `mcp__claude_ai_Slack__slack_send_message`）
- GATE1_MAX_REVISIONS: 2
- GATE2_MAX_FIXES: 2
- TEST_GREEN_MAX_ATTEMPTS: 3
- FORBIDDEN_PATHS: `~/.claude/skills/create-routine-issue/forbidden-paths.txt` を Read

## Flow

### Step 1: Pickup

- 冒頭で経過時間計測を開始:

  ```bash
  START_TS=$(date +%s)
  ```

- GitHub MCP tool (list/search issues 相当) で以下条件に合う Issue を 1 件だけ pickup:
  - repo: `dinii-inc/dinii-internal-tools`
  - state: open, label: `routine:ready` AND `shunji-muto-issue`, label 除外: `routine:in-progress`
  - updated でソートし先頭 1 件を採用
- 0 件なら「本日 pickup 対象なし」を Slack に通知して正常終了 (exit 0)
- Pickup した Issue #N について:
  - GitHub MCP tool (add/remove issue labels 相当) で `routine:ready` を外し `routine:in-progress` を付与

### Step 2: Branch 作成

- git config が空の fresh container 対策 (commit 不可を防ぐ):

  ```bash
  if [[ -z "$(git config user.email)" ]]; then
    git config user.email "routine@dinii.local"
    git config user.name "Muto Routine (Claude Code Web)"
  fi
  ```

- `git fetch origin`
- Branch 名衝突対策: `routine/N-<slug>` が既に remote に存在する場合は attempt 番号を付与して回避する

  ```bash
  ATTEMPT=1
  BASE_BRANCH="routine/N-<slug>"
  BRANCH="$BASE_BRANCH"
  while git ls-remote --heads origin "$BRANCH" | grep -q .; do
    ATTEMPT=$((ATTEMPT + 1))
    BRANCH="$BASE_BRANCH-attempt-$ATTEMPT"
  done
  git checkout -b "$BRANCH" origin/main
  ```

  - slug 生成ルール:
    - Issue title を ASCII kebab-case に変換 (英数字とハイフンのみ残す、連続ハイフンは 1 個に潰す、先頭末尾のハイフンは除去)
    - 変換後の長さが 3 文字未満なら (Japanese-only title 等で slug が空になるケース)、`issue` を fallback として使う
    - 30 文字上限 (超過時は前方 30 文字で truncate、末尾ハイフンは除去)
    - 例: `[ISP] fake timer 化再挑戦` → `isp-fake-timer` / `商談分析ダイナソー` → `issue` (fallback)
    - 最終的な branch base は `routine/N-<slug>` (N は Issue 番号)
  - 以降、ブランチ参照は全て最終決定した `$BRANCH` を使う (`routine/N-<slug>` はテンプレート表記)

### Step 3: Plan 作成 + 事前 forbidden path check

- Issue body を精読。「変更対象ファイル」「テストケース」「触ってはいけない」セクションを抽出
- `~/.claude/skills/create-routine-issue/forbidden-paths.txt` を Read
- **事前 check**: Issue の変更対象ファイルが forbidden-paths のいずれかに glob マッチしたら **即 abort** (needs-human + Slack)、理由: "Issue body に禁止パスが含まれる"
- 計画書を `/tmp/plan-N.md` に書き出す。構成:
  - `## Context`: Issue の要約
  - `## Files to change`: [New]/[Edit]/[Delete] 付きパス列挙
  - `## Approach`: 実装手順を番号付き
  - `## Test contract`: Issue の「テストケース (Routine契約 - 改変禁止)」セクションを **verbatim 転記**
  - `## Verification`: `bun run lint`, `bunx tsc --noEmit`, `bun run test <target>` の実行順

### Step 4: Gate 1 レビュー (計画書)

- 起動前に `Read` ツールで `~/.claude/skills/senior-pr-review/SKILL.md` の存在確認
  - 存在しない場合 → **即 abort** (needs-human + Slack)、理由: "Gate 1 skill が展開されていない
    (setup script 障害の可能性)"
- `Skill` ツールで `senior-pr-review` を起動、args に `/tmp/plan-N.md` を渡す
- 結果を Blocking / Improvements / Concerns / Positives の 4 カテゴリで parse
- Blocking がある場合:
  - 指摘に従って plan を修正 (Edit)
  - 再度 `senior-pr-review` を起動
  - **loop 上限 2 回**まで
  - 2 回目でも Blocking が残る → **abort** (needs-human + Slack)、理由: "Gate 1 で Blocking 解消できず (2 revisions)"
- Improvements は「trivial に反映できるもの」だけ反映、判断つかないものは無視
- Concerns / Positives は plan 末尾にコメントとして追記のみ

### Step 5: Implementation

- 実装前に、対象 package の `package.json` に必要な script が存在するか確認する:

  ```bash
  # 対象 package のディレクトリ (plan の Files to change から特定)
  PKG_DIR=$(dirname <代表的な変更対象ファイル>)
  while [[ ! -f "$PKG_DIR/package.json" ]] && [[ "$PKG_DIR" != "/" ]] && [[ "$PKG_DIR" != "." ]]; do
    PKG_DIR=$(dirname "$PKG_DIR")
  done

  # 存在する script を確認 (jq が使える前提。無ければ grep でフォールバック)
  HAS_LINT=$(jq -r '.scripts.lint // empty' "$PKG_DIR/package.json" 2>/dev/null)
  HAS_TEST=$(jq -r '.scripts.test // empty' "$PKG_DIR/package.json" 2>/dev/null)
  ```

- script 存在に応じて実行内容を分岐:
  - `lint` script あり → `bun run lint` 実行、無し → skip して PR body の `## Verification` セクションに
    「lint script 欠如のため未実行 (package: `$PKG_DIR`)」と明記
  - `test` script あり → `bun run test <target>` 実行、無し → **abort** (needs-human + Slack)、理由:
    「対象 package に test script が無く、Routine の done 判定 (テスト green) が成立しない」
  - `bunx tsc --noEmit` は package.json script に依存しないので常に実行 (TypeScript project の想定)

- Plan に従って実装
- Issue の「テストケース (Routine契約 - 改変禁止)」に列挙されたテスト名を、テストファイルに **必ず全部** 追加
- 毎回のイテレーションで以下を実行 (`<target 相対パス>` は plan の `## Files to change` セクションから
  抽出したテストファイルを指す):

  ```bash
  bun run lint
  bunx tsc --noEmit
  # target 指定例: bun run test packages/xxx/src/yyy.test.ts
  # ワイルドカード指定例: bun run test packages/xxx/src/**/*.test.ts
  bun run test <target 相対パス>
  ```

- 実装途中で forbidden path を触る必要が判明したら **即 abort** (needs-human + Slack)、理由: "実装中に禁止領域接触が判明"
- test 失敗した場合、実装を修正して再試行
- **loop 上限 3 回**
- 3 回目でも test green にできない → **abort** (routine:blocked + Slack)、理由: "test green 化に失敗 (3 attempts)"
- **テスト名照合 (改変防止)**: 完成後、以下の手順で照合する
  - Issue の「テストケース」セクションから `` `should ...` `` の形で backtick 囲みされた行を抽出
  - 各テスト名について、実装後のテストファイル群に対し `grep -F "should ..."` (fixed string 比較) で
    存在確認
  - 1 件でも欠落があれば **abort** (needs-human + Slack)、理由: "Routine 契約テストが実装から消えている"

### Step 6: Gate 2 レビュー (3 並列)

- 以下 3 つを **1 メッセージで並列起動** (built-in skills):
  - `/simplify` (簡潔化観点)
  - `/review` (PR レビュー観点)
  - `/security-review` (セキュリティ観点)
- 各 skill の出力から Blocking finding を抽出

### Step 7: Adversarial verify (妥当性判断)

- 各 Blocking finding について、独立 subagent (Agent tool + subagent_type: code-reviewer) を起動し、
  「以下の指摘を refute せよ。実際に問題か、false positive か、根拠付きで判定せよ」と依頼
  - **重要**: 判断前に対象ファイルを `Read` / `Grep` ツールで **必ず調査すること**。ファイルを読まずに
    diff テキストだけで回答することを禁ずる。tool_uses: 0 での回答は無効。無効な回答が返った場合は
    「必ず対象ファイルを Read/Grep ツールで調査してから回答せよ。ファイルを読まずに回答することを
    禁止する。」を明示して再起動する
- 3 名の verifier に並列で問い、過半数が「refuted (false positive)」と判定したら **無視** (PR description に「Gate 2 で XX の指摘があったが verifier 2/3 が false positive と判定、無視」と記載)
- 過半数が「confirmed (真の問題)」と判定したら fix キューに入れる

### Step 8: Fix loop

- Step 7 で confirmed になった Blocking を修正 (Edit)
- 修正後、再度 Step 6 (Gate 2 3 並列) を実行
- **loop 上限 2 回**
- 2 回目でも confirmed Blocking が残る → **abort** (needs-human + Slack)、理由: "Gate 2 Blocking 解消できず (2 fixes)"

### Step 9: PR 作成

- `git add <touched files>` (broad add 禁止、明示ファイル指定)
- `git commit -m "[routine] <issue title>"` (Conventional Commit 準拠、Notion ticket 番号は Issue 本文にあれば prefix)
- `git push -u origin $BRANCH`
- GitHub MCP tool (create pull request 相当、draft: true) で draft PR 作成:
  - title: `[routine] <issue title>`
  - body: 以下を含める:
    - `Closes #N`
    - `## Plan (Gate 1 通過版)`: `/tmp/plan-N.md` の内容
    - `## Gate 2 review outcome`: confirmed で fix 済 / verifier で false positive 判定した内容
    - `## Test contract`: Issue のテストケース全リストが実装後の test ファイルに存在することを grep 結果で示す
    - `## Duration`: pickup から PR 作成までの経過分
- GitHub MCP tool (add labels to labelable 相当) で PR に `needs-review` を付与
- GitHub MCP tool (add/remove issue labels 相当) で Issue #N に `needs-review` を付与し `routine:in-progress` を除去

### Step 10: Slack 通知 (成功)

- 経過時間を計算:

  ```bash
  DURATION_MIN=$(( ($(date +%s) - START_TS) / 60 ))
  ```

- `mcp__claude_ai_Slack__slack_send_message` で `#zzz-shunji_muto` に投稿:

  ```
  ✅ [routine] Issue #N 完了

  <Issue title>
  PR: <PR URL>
  差分: +<added>/-<deleted> (files: <N>)
  経過: $DURATION_MIN 分
  ```

- MCP 呼び出しが失敗したら stdout に `[routine] Slack notify failed: <reason>` を出力し、以降 exit 0
  (通知失敗は routine の成否を左右させない)

## Abort 時の共通処理

いずれの abort でも共通処理:

**順序が重要**: push を先にやってから Issue コメントと label 変更を行う。理由: Issue コメント本文が
ブランチの状態を参照するため、コメント時点でのブランチ状態と一致させる必要がある。

1. 経過時間を計算 (未計算なら):

   ```bash
   DURATION_MIN=$(( ($(date +%s) - START_TS) / 60 ))
   ```

2. 途中の diff を保存: `git add -A && git commit -m "[routine] wip: <phase> abort" && git push`
   - **注記**: abort 時のみ `-A` を許可 (「他ファイル禁止事項」の例外)。理由: どの中間ファイルが
     どこまで生成されたか予測不能なため、人間の引き継ぎ用に全部保存する
   - push 失敗した場合は stdout に `[routine] wip push failed: <reason>` を出力して以降続行 (comment 内で
     「push 未完了」と明記する)
3. GitHub MCP tool (add issue comment 相当) で Issue #N に plan と直近ログを inline したコメントを投稿。
   plan と log を Issue に永続化するため、body は次の形式にする (`Branch:` 行は上記 step 2 で push
   成功したかに応じて `push 済` / `push 未完了 (要手動確認)` を出し分ける):

   ```
   ## Routine abort
   **Phase**: <phase 名>
   **Reason**: <理由>
   **Branch**: $BRANCH (push 済)

   ## Plan (Gate 1 通過時点 or 作成中断時点)

   <plan の全文>

   ## 最終ログ (最後の 100 行)

   ```
   <tail -100 の内容>
   ```
   ```

4. GitHub MCP tool (add/remove issue labels 相当) で Issue #N の `routine:in-progress` を外し
   `<BLOCKED or NEEDS_HUMAN>` を付与
5. Slack に投稿:

   ```
   ❌ [routine] Issue #N abort (phase=<name>)

   理由: <理由>
   Issue: <URL>
   ブランチ: $BRANCH (作業途中の diff はブランチに push 済)
   経過: $DURATION_MIN 分
   ```

   - MCP 呼び出しが失敗したら stdout に `[routine] Slack notify failed: <reason>` を出力し、以降 exit 0
     (通知失敗は routine の成否を左右させない)
6. exit 0 (Routine としては正常終了扱い、abort が起きたことは Slack で通知済)

## 禁止事項

- `git push --force` / `git push --force-with-lease`: 禁止
- `git commit --no-verify`: 禁止
- `git rebase -i`, `git add -i`: 禁止 (対話が必要なため)
- `sudo`: 禁止 (fresh container で権限不要)
- forbidden paths への Edit: 事前 / 実装中 いずれも即 abort
- Issue の「テストケース」セクション改変: 禁止 (契約)
- 他人が起票した Issue の pickup: 禁止 (owner label 必須)

## デバッグ用ログ

各 step の開始・終了時に `echo "[routine] step=<N> action=<start|end> ..."` を stdout に。
plan / diff / test 出力は `/tmp/routine-N-<phase>.log` に保存。
