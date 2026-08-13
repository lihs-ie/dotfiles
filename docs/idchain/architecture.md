# idchain 技術構成

## 正本と配布

共通engineとフェーズ手順の論理正本は `dot_claude/` に置く。Claude Code向けにはchezmoiがそのまま
`~/.claude/` へ配布する。Codex向けSkillは決定論的な限定変換で `dot_codex/skills/` に生成し、
engineは正本digestを埋め込んだchezmoi `run_onchange` が `~/.codex/idchain/engine/` に実体化する。

Codex配布実体は実行時に `~/.claude/` を参照しない。論理正本の配置とランタイム依存を分離する。

## runtime flow

1. ユーザーが `$idchain` または専門Skillを起動する。
2. Skillが対象repoのCanon、approval、semantic review、reportを観測する。
3. 人間ゲート前後では `lake build` と `lake exe idchain check` が鎖を検査する。
4. G2前のCodex `apply_patch` はPreToolUse adapterが `.gate-status.json` を読み、対象repoの実装編集だけをdenyする。
5. shell経由の変更はhookの完全強制対象にせず、対象repoのpre-commitとCIが検出する。
6. build後は実test resultとTCをcrosscheckし、reportと独立レビューを経てretroへ進む。

## データ境界

| データ | owner | 更新経路 |
|---|---|---|
| `Canon/*.lean` | 対象repo | idchain Skillが起草、人間ゲートはapprove CLI経由 |
| `views/*.md` | engine | `lake exe idchain views` のみ |
| `.gate-status.json` | engine | `lake exe idchain check` |
| `verification-report.*` | engine | `lake exe idchain report` |
| Codex Skill実体 | dotfiles | 共通Skill→同期script→chezmoi |
| Codex engine実体 | dotfiles | engine正本→digest検証→run_onchange |

## deploy・rollback・観測

- deploy前に `chezmoi --source <repo> diff` で `~/.codex` の対象差分だけを確認する。
- applyは `--source` と対象パスを明示し、既定の別sourceを誤用しない。
- engine同期はstaging digestを検証してからdirectoryを入れ替える。
- Skill同期ずれ、engine digestずれ、hook payload違反は契約テストをexit codeで通知する。
- hook定義の追加・変更後はCodex `/hooks` で定義hashを確認し、ユーザーが信頼する。
- rollbackはdotfiles側の変更を戻して対象限定applyを再実行する。chezmoi自体にはundoがない。

## ローカル前提

- `chezmoi`
- `python3`（Codex hook adapter）
- `rsync`, `shasum`（engine同期）
- `elan`, `lake`（idchain engineと対象repo）
- 対象repo固有のtest runnerとxunit出力
