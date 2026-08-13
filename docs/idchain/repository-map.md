# idchain リポジトリ実装マップ

調査基準: `lihs-ie/dotfiles` commit `ae5d75bc3b63b96f563f497bff09f16fad01b182`。

## 読む順番

1. [idchain仕様](https://github.com/lihs-ie/dotfiles/blob/ae5d75bc3b63b96f563f497bff09f16fad01b182/docs/specs/idchain.md)で目的・識別子・ゲートを確認する。
2. [ModelTypes](https://github.com/lihs-ie/dotfiles/blob/ae5d75bc3b63b96f563f497bff09f16fad01b182/dot_claude/idchain/engine/Idchain/ModelTypes.lean)と[Checks](https://github.com/lihs-ie/dotfiles/blob/ae5d75bc3b63b96f563f497bff09f16fad01b182/dot_claude/idchain/engine/Idchain/Checks.lean)で機械保証の境界を確認する。
3. `dot_claude/skills/idchain-*/SKILL.md`で各フェーズの操作順を見る。
4. Codexホストの変更では `scripts/sync-idchain-codex.sh`、`dot_codex/hooks.json`、`tests/idchain-codex-*.sh`を見る。

## 主要ディレクトリ

| パス | 責務 | 入口 | 外部依存・境界 |
|---|---|---|---|
| `dot_claude/idchain/engine/` | Lean型、検査、CLI、initテンプレートの論理正本 | `Idchain.lean`, `Idchain/Cli.lean` | Lean 4 / Lake |
| `dot_claude/skills/idchain*/` | 全工程ルーターと6つの専門フェーズの論理正本 | 各 `SKILL.md` | エージェント対話、git、対象repoのtest command |
| `dot_claude/idchain/hooks/` | Claude Code用PreToolUse adapter | `executable_idchain-edit-guard.sh` | Claude Code hook payload |
| `dot_codex/skills/idchain*/` | Codexが直接発見する同期済みSkill実体 | 各 `SKILL.md` | Codex Skill discovery |
| `dot_codex/idchain/hooks/` | Codex `apply_patch` 用G2編集guard | `executable_idchain-edit-guard.py` | Codex PreToolUse JSON |
| `dot_codex/idchain/executable_sync-engine.sh` | 検証済みengineを `~/.codex` へ原子的に実体化 | script本体 | `rsync`, `shasum` |
| `scripts/sync-idchain-codex.sh` | 共通SkillからCodex版を生成し、engine digestを更新・検査 | `--write`, `--check` | `sed`, `diff`, `shasum` |
| `tests/idchain-fixture-tests.sh` | Lean engineと正負fixtureの契約検証 | test script | Lake |
| `tests/idchain-hook-tests.sh` | Claude hook adapterの契約検証 | test script | Bash |
| `tests/idchain-codex-hook-tests.sh` | Codex hook adapterの契約検証 | test script | Python 3 |
| `tests/idchain-codex-sync-tests.sh` | Skill同期、template、engine実体化・修復の契約検証 | test script | chezmoi |

## 変更時の入口

| 変更内容 | 最初に編集する場所 | 必須追随 |
|---|---|---|
| engineの型・CLI・検査 | `dot_claude/idchain/engine/` | Codex digest、engine tests、必要なら仕様 |
| 共通フェーズ手順 | `dot_claude/skills/idchain*/SKILL.md` | `scripts/sync-idchain-codex.sh --write`、`--check` |
| Codex固有hook契約 | `dot_codex/idchain/hooks/` | `dot_codex/hooks.json`、Codex hook tests |
| Codexへのengine配布 | `dot_codex/idchain/executable_sync-engine.sh` | run_onchange template、sync tests |
| 識別子・ゲートの意味 | `docs/specs/idchain.md` | 用語集、関連Skill、engine検査 |
