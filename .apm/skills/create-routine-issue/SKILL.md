---
name: create-routine-issue
description: "Claude Code Web の pick-and-implement Routine 用の Issue を対話的に作成する。ユーザーが明示的にこの skill を指定した時のみ起動する。通常の GitHub Issue 起票(人間が実装する用)には使わない。"
when_to_use: |
  ユーザーが `/create-routine-issue` で明示起動した時のみ。
  通常の Issue 起票・PR 作成には起動しない。
  以下のケースでは起動を断り、案内する:
  - DB スキーマ / migration / インフラ / secrets / dep 追加 / BQ 関連の変更が絡む → Routine 対象外
  - 複数パッケージに跨る変更 → 設計判断が残っている可能性が高いので拒否
model: sonnet
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, Grep, Agent
---

# create-routine-issue

Claude Code Web の pick-and-implement Routine が拾える Issue を、ユーザーとの対話を通じて Definition of Ready を満たす形で起票する Skill。

## 1. 役割と発動条件

- ユーザーが入力する「1〜2 行のやりたいこと」を受け取り、Routine が実装に着手できる水準まで具体化した Issue を作成する。
- 対象領域が Routine 対象外(インフラ・DB・secrets 等)の場合は起票を拒否し、「人間が実装してください」と案内して終了する。
- 対象リポジトリは現在の作業ディレクトリ(`git rev-parse --show-toplevel`)で決定する。

## 2. 対話フロー(順序固定・禁止判定を前倒しする)

以下の順序を必ず守ること。後段の禁止判定を先送りにしない。

1. **対象パッケージ確定**: ユーザー入力からキーワードを抽出し、`packages/*/package.json` の `name` / `description` を grep で走査する。候補を 1〜3 個提示し、ユーザーに選択させる。
2. **禁止パス早期チェック**: 選択された対象パッケージが禁止パス一覧(下記「禁止パスの解決」参照)のパターンに一致する場合、この時点で即座に起票を拒否する。
3. **既存パターン調査**: 対象パッケージ配下のみを対象に `Explore` サブエージェントへ委任し、触ることになりそうなファイル・参考にすべき既存テストパターンの候補を抽出する。
4. **触るファイル確定 → 禁止パス再チェック**: 手順3で抽出されたファイル候補が `forbidden-paths.txt` のいずれかのパターンに一致する場合、この時点で起票を拒否する。
5. **テンプレ穴埋め対話**: `issue-template.md` を Read し、各セクションの内容案を Claude が提示し、ユーザーに確認・修正してもらう。
6. **テストケース言語化**: 「should ... when ...」形式でテストケースを列挙する。UI 仮実装ケースについては、テストケースの代わりに手動確認手順を番号付きで列挙する。
7. **プレビュー**: 組み立てた Issue 本文を全文表示し、ユーザーの承認を待つ。承認が得られるまで起票しない。

## 3. 起票

- GitHub MCP(ツール名は `mcp__github__create_issue` 系。実環境で正確なツール名を確認してから使うこと)で Issue を作成する。
- **必要ラベルの付与を試みる。付与前に必ずラベルの存在を確認する:**
  - `mcp__github__list_labels` 相当のツールでラベル一覧を取得する。
  - 必要ラベル: `routine:ready` (Routine pickup 用) + `shunji-muto-issue` (オーナー識別用、pick-and-implement Routine が owner filter として使用)
  - 両方存在する場合 → 両方付与して起票する。
  - 片方だけ存在する場合 → 存在するラベルのみ付与し、欠けているラベル名を Issue 本文冒頭の警告に列挙する。
  - 両方存在しない場合 → labelless で起票し、Issue 本文冒頭に「以下のラベルが未作成のため後で手動付与してください: `routine:ready`, `shunji-muto-issue`」を追記する。ユーザーにも同じ警告を表示する。
- GitHub MCP が利用できない環境では、Issue 本文をコードブロックで出力し、ユーザーに手動起票を促す(fallback)。

## 4. 禁止・拒否ケース

以下に該当する場合は起票せず、理由を明示して終了する。

- 禁止パスにマッチする変更が含まれる(`forbidden-paths.txt` 参照)
- 複数パッケージに跨る変更が必要
- 対象パッケージの確定に失敗した(候補が見つからない、ユーザーが選択できない)

## 5. 調査範囲ルール

デフォルトでは対象リポジトリ内のみを調査対象とする。外部リポジトリ・submodule の参照が必要な場合は、その旨を Issue に明記する(Routine 側の環境で参照可能とは限らないため)。

## 6. 使わないケース

以下は本 Skill の対象外。他の Skill / 手作業に委譲する。

- 通常の GitHub Issue 起票(人間が実装する用途)
- PR 作成
- コードレビュー

## 補足: 禁止パスの解決

禁止パスは 2 層のマージで決まる:

1. **本スキル同梱の `forbidden-paths.txt`（汎用ベースライン）は常に有効**。.env / credentials / *.pem / .github/workflows/ 等、どの組織でも Routine に触らせるべきでないパターンを含む
2. 対象リポジトリに `.claude/routine-forbidden-paths.txt` があれば、その内容を**追加マージ**する（組織・リポジトリ固有の禁止パスはこちらに書く）

**置換ではなく追加マージである点が重要**: 利用側ファイルで同梱ベースラインを無効化することはできない（固有パスだけ書いた瞬間に汎用セキュリティガードが消える事故を防ぐ）。後続の `routine-guard.yml` CI 側も同じ 2 層マージを参照する設計とする。

## オーナー識別

本 Skill は現時点で **shunji-muto さん専用** の Routine 向けに Issue を起票する。オーナーラベルは `shunji-muto-issue` を hard-code している。他ユーザーが同じ運用を始める場合は、この Skill を fork するか、オーナーラベル名を引数化する改修が必要。
