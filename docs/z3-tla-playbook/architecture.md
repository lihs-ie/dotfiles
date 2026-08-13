# z3-tla-playbook アーキテクチャ

## 正本と配布

[gist revision](https://gist.github.com/mizchi/db7817e6fc077d567c41cd9d41bb1c53/2133eced8334ed36e47ec4d6e138a46552539256)
は方法論の出典であり、通常実行時の依存ではない。実行に必要な命令、参照資料、雛形、ハーネスは
`dot_claude/skills/z3-tla-playbook` に同梱する。

同期スクリプトはパッケージ全ファイルを安定順で読み、`~/.claude` を `~/.codex` に、Claude Code の
呼び出し表記を Codex の表記にだけ変換する。`--check` は生成物との byte-level drift を検出する。

## 実行境界

Skill は対象コードを読み、`.formal/` だけに成果物を作る。対象の有限性と決定性を最初に判定し、
全列挙、Z3、TLA+ の順で最小の手段を選ぶ。基準モデルだけでなく broken variant を実行し、検査が
load-bearing であることを確認する。

結果は `HOLDS`、`REFUTED`、`ERROR` の三値である。依存不足や model crash は `ERROR` であり、反例に
格上げしない。`HOLDS` もモデル範囲内の結果で、コード全体の正しさを主張しない。

## 独立性

この Skill はデバッグで停止する。仕様の承認、実装変更、開発パイプラインへの引き渡しは行わない。
hook も追加しない。後続作業は `.formal/ledger.md` を読んだユーザーが別途開始する。
