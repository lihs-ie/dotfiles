# rubric pack: DDD

仕様違反はしばしば「挙動」ではなく **境界の破壊** として表れる。
ユビキタス言語の誤用・aggregate 越え直接参照・application service の過肥大・
インフラ都合の domain 汚染を static gate に落とす。

## 追加判定項目
- aggregate boundary を横断する **直接更新** がない。
- app service が domain rule を迂回していない。
- domain event と subscriber 契約が保持されている (contract test)。
- terminology が spec / code / docs で一致している。

## 命名規約 (lihs standard)
- `Detail` / `Info` のような曖昧語を domain model 名に使わない。
- 識別子型は `XXXIdentifier` (例: `StockIdentifier`)。自身の識別子フィールドは `identifier`。
- 他モデルの識別子はそのモデル名をフィールド名にし suffix `Identifier` を付けない
  (例: `LotteryApplication.stock: StockIdentifier`)。

## seed / clock / random の非決定性制御
- domain event の `occurredAt` は domain service に inject された `Clock` から取得する (domain が `Date.now()` を直呼びしない)。
- aggregate の識別子生成は `IdGenerator` 型クラス / interface に差し替え、テストで固定 ID を inject する。
- contract test でイベントのタイムスタンプを固定し、snapshot test の flaky を防ぐ。

## 推奨証拠
- bounded context ごとの import / dependency rule を arch test 化。
- domain event / outbox / integration event を contract test で固定。
