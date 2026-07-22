# Agent Workflow Guidelines

## Core Principles

- **Simplicity & Minimal Impact**: 必要最小限のみ変更。装飾的修正・余計な触り禁止
- **Root Cause**: 一時しのぎ禁止。シニア開発者基準で根本原因を直す
- **No Guessing**: 推測実装禁止。必ず調査してから実装

## Review Gates

非自明タスク（3ステップ以上）は、以下 2 つのレビューゲートを通す:

- **Gate 1（計画レビュー）**: 実装計画を確定する前に、計画書をシニアレビュアー観点
  （Blocking / Improvements / Concerns / Positives の 4 区分）でレビューし、
  Blocking / Improvements を計画に反映してからユーザーの承認を得る
- **Gate 2（実装後レビュー）**: 実装完了・検証パス後に、以下 3 観点のレビューを通す:
  1. **簡潔化**: reuse / simplification / efficiency の観点（挙動を変えない品質改善）
  2. **PR レビュー**: コード品質・correctness・規約準拠・パフォーマンス・リスクの観点
  3. **セキュリティ**: 高確信の脆弱性検出（偽陽性を最小化し HIGH/MEDIUM のみ報告）

  Blocking 指摘は修正。ドキュメント・設定のみの変更は PR レビュー観点単独で良い

## Workflow

1. **Plan First**: 非自明タスク（3ステップ以上）は実装前に計画を立て、ユーザーの承認を得る
2. **Delegate & Parallel**: 独立したタスクは可能な限り並列実行する。逐次実行は明確な依存がある場合のみ
3. **Verification**: コード変更を伴う場合、完了前に **Lint → Format → TypeCheck → Test**。全パスまで修正

> 各エージェント固有の追加規定（Claude Code の CLAUDE.md 等）がある場合はそちらにも従うこと。
> ゲートの具体的な実行手段（どのスキル・どのレビュアーを使うか）は各エージェント側の設定が規定する。
> ゲート実行手段が未整備のエージェント環境では、同等の観点を自前のレビューで満たすベストエフォートとする（ゲート未実行のまま完了扱いにしない）。
