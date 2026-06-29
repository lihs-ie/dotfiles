# rubric pack: Swift (UIKit / SwiftUI)

## 追加判定項目
- 新規 `View` / `ViewModel` が `@StateObject` / `@ObservableObject` で適切に DI され、preview stub が本番コードに混入していない。
- async/await の非同期境界で `Task` が適切にキャンセルされ、memory leak (retain cycle) が無い。
- `AppDelegate` / `SceneDelegate` / `App` struct から新規 feature module が結線されている。
- protocol witness / mock は `Tests/` 配下のみ (本番 target に含まない)。

## seed / clock / random の非決定性制御
- `Date()` / `UUID()` / `arc4random()` を直接呼ぶ production code は DI 可能な `Clock` / `IDGenerator` protocol に差し替える。
- テストでは `TestClock` / `MockIDGenerator` を inject し、シード固定で決定論的結果を保証する。
- `XCTestCase.setUp` で seed を `srand(42)` 等で固定し、テスト間の状態汚染を防ぐ。

## 推奨証拠
- `xcodebuild test` (xcresult の `failedTests==0` を一次判定)。
- SwiftUI Previews が本番 target に混入しないことを `grep -r 'PreviewProvider' Sources/` で確認。
- Instruments / Memory Graph で retain cycle 無しを確認。
