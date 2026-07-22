# Senior PR Review — 観点プリセット

`SKILL.md` から `Read` される。subagent には該当 preset セクションを抜粋して prompt に埋め込む。

各プリセットの構成:
- **役割**: 一行説明
- **特に厳しく見るべき点**: チェックリスト
- **典型的な Blocking 例**: Phase 0–5 の実例

---

## data

**役割**: BigQuery / SQL / データ取得層全般を、クエリ設計・キャッシュ戦略・並列性・フォールバックの観点でレビュー。

**特に厳しく見るべき点**:
- [ ] cache key にクエリ依存パラメータ (店舗 ID / 期間 / 通貨 等) がすべて含まれているか
- [ ] スコープフィルタ (`shop_id` / `tenant_id` / `org_id` 等) が必ず WHERE に入っているか
- [ ] 並列発行 (`Promise.all`) で N+1 になっていないか / 反対に直列で重くなっていないか
- [ ] 失敗時の fallback (空配列 / null / デフォルト値) が呼出側で安全に扱えるか
- [ ] partition pruning が効くカラムで WHERE しているか (BQ コスト)
- [ ] dry-run / 単体テストで cost が可視化されているか
- [ ] 同名の view / table が dataform に既存していないか (重複定義)
- [ ] 結果が UI 層に渡るまでの型整合 (Decimal / Date / Timestamp の変換)

**典型的な Blocking 例**:
- cache key に `period` が含まれず、期間切替時に古い結果を返す → 集計値の表示バグ
- `WHERE shop_id IS NULL` の暗黙フィルタ漏れで他店舗データが混入 → データ漏洩
- `Promise.all([qA, qB, qC])` で qA が失敗すると全体 reject、UI 全体が空表示 → 部分失敗対応必須
- partition column を使わず `WHERE date >= ...` を文字列比較 → スキャン量爆発でコスト 100x

---

## ui

**役割**: Next.js / React コンポーネント層を、Server/Client 分離・hydration・a11y・デザイントークンの観点でレビュー。

**特に厳しく見るべき点**:
- [ ] `'use client'` が必要最小範囲に絞られているか (Server Component で済むものに付いていないか)
- [ ] hydration mismatch リスク (`Date.now()`, `Math.random()`, `window` 直接参照, locale 依存表示) が無いか
- [ ] dialog / popover / select は **共通 primitive** を経由しているか (独自実装は a11y 欠陥のもと)
- [ ] Tailwind の hard-coded color (`text-[#abc]`) が無いか / token (`text-foreground` 等) を使っているか
- [ ] `key` prop が安定 (index 使い回しでない)
- [ ] loading / error / empty の 3 状態が定義されているか
- [ ] keyboard navigation が壊れていないか (`tabIndex={-1}` の乱用、focus trap の漏れ)
- [ ] suspense boundary / error boundary が適切な粒度で切られているか

**典型的な Blocking 例**:
- 独自 `<div role="dialog">` 実装で focus trap も escape close も無い → a11y 重大欠陥、共通 Dialog primitive を使うべき
- Server Component に `'use client'` を付けたため bundle が肥大、RSC streaming が効かない → 削除必須
- `<table>` の row に `key={index}` で並べ替え時に DOM が崩壊 → 安定 key (`row.id`) 必須

---

## a11y

**役割**: アクセシビリティ。ARIA 属性、focus 管理、keyboard ナビゲーション、screen reader 対応を厳格チェック。

**特に厳しく見るべき点**:
- [ ] interactive な要素はすべて `<button>` / `<a>` / `<input>` 等の semantic tag か (div onClick は NG)
- [ ] `aria-label` / `aria-labelledby` / `aria-describedby` が必要な箇所に付いているか
- [ ] dialog 開閉時に focus が dialog 内へ移動 / close 時に trigger に戻るか
- [ ] `Esc` で dismiss、`Tab` で trap、`Enter`/`Space` で activate が効くか
- [ ] color contrast (WCAG AA: 4.5:1 / AAA: 7:1) を満たすか
- [ ] icon-only button に `aria-label` が無い、または `<VisuallyHidden>` ラベルが無い
- [ ] error message が `aria-live` / `role="alert"` で screen reader に伝わるか
- [ ] form の `<label>` と `<input>` が `htmlFor` / `id` で関連付いているか
- [ ] 画像の `alt` が意味のある内容か (装飾なら `alt=""`)

**典型的な Blocking 例**:
- icon button (`<button><XIcon /></button>`) に `aria-label="Close"` が無く screen reader が「ボタン」としか読まない → 必須
- dialog open 時に focus が body に残り、Tab 後の挙動が予測不能 → focus を最初の interactive 要素へ移動

---

## sql

**役割**: BigQuery 専用の SQL レベルチェック。コスト、パフォーマンス、データ整合性を見る。

**特に厳しく見るべき点**:
- [ ] partition column を WHERE に含む (DATE / TIMESTAMP) か
- [ ] cluster column を活用しているか (フィルタ順序の最適化)
- [ ] `SELECT *` が無いか (必要カラムのみ列挙)
- [ ] sub-query で JOIN 前に絞り込んでいるか (Cartesian / large JOIN 防止)
- [ ] `NULL` を `COALESCE` / `IFNULL` で適切に処理しているか
- [ ] `WHERE x IN (sub-query)` より `JOIN` の方が速いケースを見落としていないか
- [ ] window function の `PARTITION BY` / `ORDER BY` が意図通りか
- [ ] approximate aggregation (`APPROX_COUNT_DISTINCT`) が許容される文脈か (財務系では NG)
- [ ] dry-run のスキャンサイズ見積もりが許容範囲内か (e.g. < 10GB)

**典型的な Blocking 例**:
- `WHERE DATE(created_at) >= '2026-01-01'` で関数適用により partition pruning が効かず、テーブル全スキャン → 関数を外す or `created_at >= TIMESTAMP('2026-01-01')` に
- `LEFT JOIN` の ON 句に NULL 許容カラムを使い、想定外の row 倍増 → `COALESCE` で防御 or INNER JOIN

---

## sec

**役割**: セキュリティ。入力検証、認可、データ漏洩、OWASP Top 10 を見る。

**特に厳しく見るべき点**:
- [ ] ユーザー入力が SQL / shell / HTML に直接埋め込まれていないか (injection)
- [ ] 認可チェック (店舗権限 / 組織スコープ / role) が API 層で行われているか
- [ ] secrets / token が log / response に漏れていないか
- [ ] CSRF token / SameSite cookie が必要な API で設定されているか
- [ ] redirect URL がオープンリダイレクト脆弱性になっていないか
- [ ] file upload で MIME / extension / size を検証しているか
- [ ] error response に内部スタックトレース / DB スキーマが漏れていないか
- [ ] 認証されていない経路で sensitive endpoint に到達できないか
- [ ] dependency に既知 CVE (audit) が無いか

**典型的な Blocking 例**:
- API handler で `req.user.shopId` を信用せず query string の `shopId` を使う → 他店舗データに到達可能、認可破綻
- `console.log({ user, token })` が production で残る → token leak

---

## types

**役割**: TypeScript の型安全性。`any` 排除、discriminated union exhaustiveness、不要な cast を見る。

**特に厳しく見るべき点**:
- [ ] `any` / `as any` / `// @ts-ignore` / `// @ts-expect-error` が無いか (理由コメント無しは Blocking)
- [ ] `as` cast で型を書き換えていないか (代わりに type guard 関数を)
- [ ] discriminated union の switch / if 分岐に `default: never` または exhaustive check があるか
- [ ] optional chain `?.` の連鎖が深すぎないか (3 段以上は型設計の見直し検討)
- [ ] generic の制約 (`extends`) が適切で `unknown` で逃げていないか
- [ ] enum の代わりに `as const` / union literal を使っているか (CLAUDE.md 規約)
- [ ] readonly / Readonly\<T\> が適用されているか (immutable 意図がある場合)
- [ ] 関数引数 3 つ以上はオブジェクト引数化されているか (CLAUDE.md 規約)

**典型的な Blocking 例**:
- API response を `as ResponseType` で強制 cast、実際の shape と乖離 → runtime error の温床。`zod` 等で parse すべき
- `switch (action.type)` に `default` 無しで新規 type 追加時の漏れ検出不能 → exhaustive `assertNever` 必須

---

## perf

**役割**: パフォーマンス。bundle size、RSC streaming、cache hit rate、N+1 を見る。

**特に厳しく見るべき点**:
- [ ] 大型ライブラリ (moment / lodash 全量 / mui 全量) を tree-shake せずに import していないか
- [ ] `'use client'` で client bundle が肥大していないか
- [ ] RSC で `await Promise.all` で並列化できる箇所が直列になっていないか
- [ ] React の `useMemo` / `useCallback` が必要な箇所に無く、子の再レンダーが頻発していないか
- [ ] `key` の不安定で reconciler が DOM 再生成していないか
- [ ] data fetch で N+1 (loop 内 fetch) が無いか / batch / dataloader 化されているか
- [ ] cache (Next.js `unstable_cache`, BQ result cache, in-memory) の hit rate が見えているか
- [ ] 画像が `next/image` で最適化されているか (raw `<img>` は減点)

**典型的な Blocking 例**:
- `import _ from 'lodash'` で 70KB+ 持ち込み → `lodash-es` の名前付き import に
- list 表示で row ごとに `await fetchUser(row.userId)` を呼ぶ → batch fetch 1 回に集約

---

## 参考: Phase 0–5 plan

各 preset の典型例は以下から抽出:
- `~/.claude/plans/dashboard-v3-phase{0..5}.md`
- 該当 Phase で実際に Blocking として挙がった指摘を蓄積していく
