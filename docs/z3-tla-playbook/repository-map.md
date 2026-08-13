# z3-tla-playbook リポジトリマップ

調査開始時点の基準 commit: [`ae5d75bc3b63b96f563f497bff09f16fad01b182`](https://github.com/lihs-ie/dotfiles/tree/ae5d75bc3b63b96f563f497bff09f16fad01b182)。
変更中の現在正本は以下の相対リンクを参照する。

| パス | 役割 |
|---|---|
| [`dot_claude/skills/z3-tla-playbook/`](../../dot_claude/skills/z3-tla-playbook/) | ローカル実装正本。Skill、scripts、templates、reference を含む。 |
| [`dot_codex/skills/z3-tla-playbook/`](../../dot_codex/skills/z3-tla-playbook/) | Codex 配布物。同期スクリプトが生成し、手編集しない。 |
| `scripts/sync-z3-tla-playbook-codex.sh` | ホームパスと呼び出し表記だけを変換する決定論的同期。 |
| [`tests/z3-tla-playbook-tests.sh`](../../tests/z3-tla-playbook-tests.sh) | setup-env / run-checks のハーネス契約。正本・Codex の両方に再利用する。 |
| `tests/z3-tla-playbook-codex-sync-tests.sh` | パッケージ完全性、分離、同期、validator、両ホストのハーネス契約を検査する。 |
| `docs/z3-tla-playbook/` | 用語、構成、アーキテクチャの説明。 |

対象リポジトリで生成される `.formal/` は dotfiles の配布物ではない。モデル、反例、依存 lock、台帳を
デバッグ対象の近くに保存する実行時成果物である。
