# rubric pack: Go (Clean Architecture)

依存方向を **機械的に強制** する価値が高い。境界 (`internal/usecase`, `internal/interface`,
`internal/infra`) を固定し、import rule を arch test で守る。

## 追加判定項目
- handler から usecase が呼ばれ、repo interface 実装へ到達する。
- import graph が inward dependency を破っていない (arch test / custom lint)。
- server 起動 smoke と主要 endpoint の health が通る。
- parser / validator / OIDC callback parser / 設定ロードに fuzz budget を割り当てた。

## seed / clock / random の非決定性制御
- `time.Now()` / `rand.Intn()` を直接本番コードで呼ばず、`Clock` interface / `Source` interface に差し替える。
- テストでは `fakeClock{t: time.Unix(1700000000, 0)}` を inject し、決定論的結果を保証する。
- `rand.New(rand.NewSource(42))` でシード固定し、確率的テストを決定論化する。

## 推奨証拠
- `go test ./...` + arch test (import 方向)。
- `httptest` か小さな integration test で handler→usecase→repo (可能なら test DB つき、repo fake ではなく)。
- `go test -fuzz` の coverage guidance で edge case 探索。
