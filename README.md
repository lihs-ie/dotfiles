# dotfiles (lihs-ie)

[chezmoi](https://chezmoi.io) で管理する dotfiles。現在は **agent-policy workflow kit** を収録。

## 収録物 (`dot_claude/` → `~/.claude/`)

モック濫用と未配線完了報告を防ぐ AI 開発ワークフロー。

- `docs/agent-policy.md` — 禁止 / Done When / 証跡 / レビュー基準の単一正本
- `agents/` — planner / explorer / implementer / integration-verifier / reviewer-static / -integration / -final
- `skills/agent-dev/` — `/agent-dev <task>` オーケストレーター(Planner→…→Final、2 周レビューループ)
- `skills/agent-policy-kit/` — 任意 repo へ Detect→Diff→Apply で scaffold する kit(テンプレ + 言語検出)

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
