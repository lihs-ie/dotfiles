# タイトル
ADR-002: z3-tla-playbook をローカル正本から Codex へ決定論配布し、独立デバッグツールとして運用する

# ステータス
承認済み

# コンテキスト
z3-tla-playbook は、既存実装を事実上の仕様として読み、宣言された意図と暗黙の挙動を分離し、全列挙・Z3・TLA+ で反例を探索する開発手法である。

方法論の正本は mizchi の gist revision `2133eced8334ed36e47ec4d6e138a46552539256` とする。ただし通常実行時に gist や git から取得してはならず、必要な命令、参照資料、雛形、ハーネスはローカルに完結させる。

次の案を不採用とする。

- 実行ごとに gist や git から取得する案
- Codex から `~/.claude` の package を直接参照する案
- `dot_claude` と `dot_codex` を個別に手編集する二重正本案
- idchain / proven-done へ結果を引き渡す案
- hook で実行を強制する案

# 決定
`dot_claude/skills/z3-tla-playbook` をローカル実装正本とする。

`scripts/sync-z3-tla-playbook-codex.sh` により、`SKILL.md`、`scripts`、`templates`、`reference` を一体の package として `dot_codex/skills/z3-tla-playbook` へ決定論的に生成する。

同期は開発・配布時だけ行い、Skill の通常実行時にはネットワーク、git、gist、Claude package に依存しない。Codex 配布物は手編集しない。

同期処理は次を保証する。

- source と destination の同一指定を拒否する
- 許可されていない destination を外部状態の変更前に拒否する
- destination と同じ filesystem 上で staging する
- INT / TERM / 失敗時に旧 package を復元する
- `--check` で byte-level drift を検出する

Skill は独立デバッグツールとして動作し、成果物を対象 repository の `.formal/` に限定する。idchain、proven-done、仕様承認、実装修正、handoff、hook には接続しない。

検査手段は問題の性質に応じて最小のものを選ぶ。

- 有限かつ決定的: 全列挙
- 一時点の全入力に対する述語: Z3
- 状態遷移、非決定性、interleaving: TLA+ / TLC

個々の主張は `HOLDS` / `REFUTED` / `ERROR` に分類する。process exit はこれと分離し、期待結果一致を0、不一致を1、solver unknown・依存不足・構文エラー等を2以上とする。`ERROR` を反例へ格上げしない。

基準モデルだけでなく broken variant を実行し、検査が load-bearing であることを確認する。結果、witness、trace、model↔code gap、未確定事項は `.formal/ledger.md` に残す。

# 影響
Positive:

- Codex 単独で z3-tla-playbook を利用できる
- Claude Code と Codex の方法論とハーネスが一致する
- 実行時の外部取得や Claude 環境への依存がない
- solver error と実際の反例を区別できる
- 全列挙・Z3・TLA+ の過剰利用を避けられる
- 独立した再現可能なデバッグ成果物が残る

Negative:

- `dot_claude` というホスト名を含むパスが論理正本として残る
- Codex package の変更には同期処理が必要になる
- TLC の分類は既知の出力形式に依存する。ただし未知形式は安全側の `ERROR` になる
- solver と TLC の実行環境は対象 repository の `.formal/` に導入する必要がある

# コンプライアンス
次の検査を必須とする。

- `bash scripts/sync-z3-tla-playbook-codex.sh --check`
- `bash tests/z3-tla-playbook-codex-sync-tests.sh`
- `bash scripts/verify-wiring.sh`
- Claude / Codex 両 package の `quick_validate.py`
- `git diff --check`
- empirical-prompt-tuning の修正後3回連続 clear
- 未使用 hold-out scenario の合格
- raw executor record、生成 `.formal`、親再実行ログ、SHA-256 の保存

# 備考
- 著者: Codex
- 承認日: 2026-08-13
- 承認者: ユーザー
- 最終更新日: 2026-08-13
- 変更点: 初版。ローカル正本、Codex 決定論配布、独立デバッグ境界、三値結果分類を決定した。
