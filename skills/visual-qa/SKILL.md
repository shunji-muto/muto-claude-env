---
name: visual-qa
description: Playwright CLIを使ったUIビジュアル検証スキル。スクリーンショットの繰り返し撮影を自動化し、CSSプロパティの一括チェックとBefore/After比較を行う。「UI確認」「スクリーンショット確認」「CSS確認」「表示が正しいか確認」「レイアウト確認」「visual-qa」「見た目を確認」「スタイル確認」「画面確認して」「UIが問題ないか」「UI的に問題」「全てのページを確認」「Playwright」「画面を確認」「問題ないかどうか確認」「表示確認」「UIをチェック」「画面のスクショ」などのトリガーで起動。
context: fork
agent: general-purpose
allowed-tools: Bash, Read, Glob, Grep
---

# Playwright UIビジュアル検証

Playwright CLIを使って、UIの表示状態を効率的に検証する。手動でのスクリーンショット繰り返しを排除し、CSSプロパティの一括取得・期待値との差分検出・Before/After比較を自動化する。

---

## 最重要ルール

**このスキルではファイルの編集・作成・削除を一切行わない。** UIの検証レポートの提示が目的であり、CSSやコードの修正はスキルの範囲外とする。

---

## 実行手順

### 1. 検証対象の確認

ユーザーから以下の情報を収集する。不足があれば質問する。

| 項目 | 確認内容 |
|------|---------|
| 対象URL | localhost:3000/xxx など |
| 検証対象の要素 | CSSセレクタ（例: `.template-grid`, `#footer`） |
| 期待する状態 | 期待するCSSプロパティ値のリスト |
| ビューポートサイズ | デフォルト: 1280x720。レスポンシブ確認が必要ならサイズ一覧 |

### 2. 現状のスナップショット取得

以下を1回のBash実行で一括取得する。

```bash
# 1. スクリーンショット撮影
playwright-cli screenshot --filename=/tmp/visual-qa-before.png <URL>

# 2. DOM構造のスナップショット
playwright-cli snapshot <URL>

# 3. 対象要素のCSSプロパティ一括取得
playwright-cli eval "JSON.stringify(
  Array.from(document.querySelectorAll('<セレクタ>')).map(el => {
    const s = getComputedStyle(el);
    return {
      selector: el.className,
      display: s.display,
      position: s.position,
      width: s.width,
      height: s.height,
      gridTemplateColumns: s.gridTemplateColumns,
      gap: s.gap,
      margin: s.margin,
      padding: s.padding
    };
  }), null, 2
)" <URL>
```

### 3. 期待値との差分検出

取得したCSSプロパティと期待値を比較し、差分をテーブル形式で出力する。

```
## CSS差分レポート

| 要素 | プロパティ | 現在値 | 期待値 | 状態 |
|------|----------|--------|--------|------|
| .template-grid | grid-template-columns | repeat(2, 1fr) | repeat(3, 1fr) | ❌ 不一致 |
| .template-grid | gap | 16px | 16px | ✅ 一致 |
| #footer | position | static | fixed | ❌ 不一致 |
```

### 4. 修正後の再検証（Before/After）

ユーザーがCSSを修正した後に再度実行する場合:

```bash
# After スクリーンショット
playwright-cli screenshot --filename=/tmp/visual-qa-after.png <URL>

# After CSSプロパティ取得（同じevalコマンド）
```

Before/Afterの比較テーブルを出力:

```
## Before/After 比較

| 要素 | プロパティ | Before | After | 期待値 | 状態 |
|------|----------|--------|-------|--------|------|
| .template-grid | grid-template-columns | repeat(2, 1fr) | repeat(3, 1fr) | repeat(3, 1fr) | ✅ 修正済み |
| #footer | position | static | fixed | fixed | ✅ 修正済み |
```

### 5. レスポンシブ検証（オプション）

複数のビューポートサイズで一括検証が必要な場合:

```bash
# 各サイズでスクリーンショット + CSS取得
for size in "375x667" "768x1024" "1280x720" "1920x1080"; do
  playwright-cli resize-page $size <URL>
  playwright-cli screenshot --filename=/tmp/visual-qa-${size}.png <URL>
  playwright-cli eval "<CSSプロパティ取得>" <URL>
done
```

サイズ別の差分テーブルを出力。

### 6. 検証レポートの出力

```
## ビジュアル検証レポート

### 検証対象
- URL: <URL>
- ビューポート: <サイズ>
- 検証日時: <日時>

### 結果サマリ
- ✅ 一致: N件
- ❌ 不一致: M件

### CSS差分詳細
[差分テーブル]

### スクリーンショット
- Before: /tmp/visual-qa-before.png
- After: /tmp/visual-qa-after.png

### 推奨修正箇所
[不一致の要素に対する修正ヒント（ファイルパスは特定しない、CSSプロパティ値の変更のみ提示）]
```

---

## 注意事項

- ファイルの編集・作成・削除は一切禁止
- Playwright CLIが起動していない場合は、ユーザーにplaywright-cliスキルでの起動を促す
- スクリーンショットは `/tmp/visual-qa-*.png` に保存し、セッション終了時の自動削除に任せる
- CSSプロパティの取得は `getComputedStyle` を使い、実際にレンダリングされた値を取得する
- 1回の検証で複数要素を一括チェックし、個別のscreenshot/evalの繰り返しを最小化する
