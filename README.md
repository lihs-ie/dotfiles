# dotfiles (lihs-ie)

[chezmoi](https://chezmoi.io) で管理する dotfiles。現在は **agent-policy 三層ループ workflow kit** を収録。

## 収録物 (`dot_claude/` → `~/.claude/`)

モック濫用と未配線完了報告を防ぐ AI 開発ワークフロー。**三層ループ**で構成する:
内側(実装→検証→証拠→修正) / 中間(独立 verifier・grader の差戻し) / 外側(失敗の eval・rule 昇格)。

- `docs/agent-policy.md` — 禁止 / Spec層 / Done When(二段門) / 証跡 / rubric / 外側ループ / 役割・モデル配分の単一正本
- `agents/` — 9 agent: spec-curator / topology-mapper / implementer / static-verifier / runtime-verifier / spec-grader / done-evaluator / failure-miner / harness-maintainer
- `skills/agent-dev/` — `/agent-dev <task>` 中心ループ(spec-curator→…→done-evaluator、決定論ゲート + 2 周レビュー)
- `skills/self-improve/` — `/self-improve` 外側ループ(failure-miner→harness-maintainer、incidents→evals→rules/promoted 昇格)
- `skills/agent-policy-kit/` — 任意 repo へ Detect→Diff→Apply で scaffold する kit(テンプレ + 言語検出 + rubric core/packs)

> **モデル境界ティア**: Sonnet 床 / 境界跨ぎ Opus / 外側ループのメタ作業は DEEPEST_MODEL。
> DEEPEST_MODEL は `docs/agent-policy.md` §7 に集約 (既定 `fable`、**2026-06-22 に `opus` へ 1 行切替**)。

## セットアップ

```bash
brew install chezmoi
chezmoi init lihs-ie/dotfiles        # source を clone (--apply で ~/.claude へ反映)
chezmoi diff                          # 反映前に差分確認
chezmoi apply
```

## 更新フロー

```bash
chezmoi add ~/.claude/skills/<name>   # 実体の変更を source に取り込む
chezmoi cd && git add -A && git commit && git push
```

注: `executable_` prefix は +x、`*.tmpl.literal` は中身の `{{...}}` を評価せず literal 保持(kit テンプレートの placeholder を守るため)。
