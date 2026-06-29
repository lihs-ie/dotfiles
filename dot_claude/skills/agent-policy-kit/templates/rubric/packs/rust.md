# rubric pack: Rust

## 追加判定項目
- 新規 `pub fn` が `lib.rs` / `mod.rs` から re-export され、crate の public API に到達する。
- `unsafe` ブロックが新規導入された場合、`// SAFETY:` コメントと reviewer 承認が必要。
- `tokio::spawn` / `async fn` の非同期タスクが適切に `JoinHandle` で管理され、task leak が無い。
- feature flag (`#[cfg(feature = "...")]`) の切り替えで本番 test double が混入しない。

## seed / clock / random の非決定性制御
- `rand::thread_rng()` を直接本番コードで呼ばず、`SeedableRng` (例: `rand::rngs::StdRng::seed_from_u64(42)`) でシード固定可能にする。
- `std::time::SystemTime::now()` をテスト境界で mock できる `Clock` trait に差し替える。
- `tokio::time::pause()` / `tokio::time::advance()` でタイマーの非決定性を制御する。

## 推奨証拠
- `cargo test --all` + `cargo clippy --all-targets -- -D warnings` + `cargo fmt --check`。
- `cargo audit` で既知脆弱性チェック。
- `cargo test -- --seed 42` でシード固定の決定論テスト (rand を使う場合)。
