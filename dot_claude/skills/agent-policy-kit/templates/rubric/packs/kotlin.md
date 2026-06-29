# rubric pack: Kotlin (Android / KMP)

## 追加判定項目
- `ViewModel` が `Hilt` / `Koin` で DI され、`Activity` / `Fragment` から直接インスタンス化されていない。
- `Flow` / `StateFlow` が `viewModelScope` / `lifecycleScope` でのみ collect され、scope leak が無い。
- Room / Retrofit の実装が Repository 層に閉じ、ViewModel が DB / API を直接参照しない。
- instrumented test (`androidTest/`) と unit test (`test/`) が分離されている。

## seed / clock / random の非決定性制御
- `System.currentTimeMillis()` / `UUID.randomUUID()` を本番コードで直接呼ばず、`Clock` / `IdGenerator` interface に差し替える。
- `TestCoroutineScheduler` / `UnconfinedTestDispatcher` でコルーチンのタイミングを制御する。
- `Random(seed = 42)` でシード固定し、テスト間の非決定性を排除する。

## 推奨証拠
- `./gradlew test` + `./gradlew connectedAndroidTest` (CI 環境の AVD)。
- Hilt / Koin のモジュールグラフが compile time で検証される (Hilt: `@InstallIn` の型チェック)。
- `kotlinx.coroutines.test.runTest` + `TestCoroutineScheduler` による決定論テスト。
