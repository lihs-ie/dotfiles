# z3-tla-playbook Codex 配布仕様

## 目的

既存実装を事実上の仕様として読み、全列挙・Z3・TLA+ で反例を探索する
`z3-tla-playbook` を Claude Code と Codex の双方で、同じ方法論とローカル成果物に基づいて実行可能にする。

方法論の出典は [mizchi の gist revision 2133eced8334ed36e47ec4d6e138a46552539256](https://gist.github.com/mizchi/db7817e6fc077d567c41cd9d41bb1c53/2133eced8334ed36e47ec4d6e138a46552539256) とする。
通常実行時には gist、git、その他のリモート正本を取得しない。

## Must

- `dot_claude/skills/z3-tla-playbook` をローカル実装正本とする。
- `SKILL.md`、`scripts/`、`templates/`、`reference/` を一体のパッケージとして扱う。
- `scripts/sync-z3-tla-playbook-codex.sh --write` が Codex 配布物を決定論的に生成する。
- `--check` が正本と `dot_codex/skills/z3-tla-playbook` のドリフトを検出する。
- Codex 固有変換をホームパスと Skill 呼び出し表記に限定する。
- `idchain` と `proven-done` を参照せず、両者からも参照されない独立デバッグツールとする。
- 成果物を `.formal/` のモデル、反例、台帳に限定する。
- 結果を `HOLDS` / `REFUTED` / `ERROR` に分類し、実行エラーを反例と数えない。
- `executable_` source attribute により配布後の2スクリプトへ実行権限を付与する。
- hook を追加しない。

## 検証

```bash
bash scripts/sync-z3-tla-playbook-codex.sh --check
bash tests/z3-tla-playbook-codex-sync-tests.sh
python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py dot_codex/skills/z3-tla-playbook
bash scripts/verify-wiring.sh
```

`tests/z3-tla-playbook-codex-sync-tests.sh` は正本と Codex 生成物の双方に対して既存ハーネス契約を実行する。
