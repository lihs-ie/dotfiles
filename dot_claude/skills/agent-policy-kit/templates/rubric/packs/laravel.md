# rubric pack: Laravel

controller を直接信じず、**Feature test で route→controller→service→DB→response** を通す。
policy / middleware / validation / transaction まで含めて確認する。

## 追加判定項目
- `route:list` に対象 endpoint が存在する。
- middleware / policy が想定どおり適用される。
- request validation により不正 payload が拒否される。
- DB transaction 後の **read-back が一致** する (「200 を返す」では不十分)。

## seed / clock / random の非決定性制御
- `now()` / `Str::uuid()` を本番コードで直接呼ばず、`Carbon::setTestNow()` / `Str::createUuidsUsing()` でテスト中の値を固定する。
- `DatabaseSeeder` の乱数シードを固定し、テスト間の状態汚染を防ぐ。
- `RefreshDatabase` トレイトでテストごとに DB をリセットし、順序依存を排除する。

## 推奨証拠
- `php artisan test --testsuite=Feature` を relevant gate に含める。
- `tests/Unit` は value object / domain service / mapper に限定。
- mock 禁止は `app/`, `bootstrap/`, `config/` の grep gate で落とす。
