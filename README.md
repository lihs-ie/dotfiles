# dotfiles (lihs-ie)

[chezmoi](https://chezmoi.io) で管理する個人 dotfiles。`dot_*/` 以下を実ホームに展開する。

## 収録物

- `dot_claude/` → `~/.claude/` — Claude Code 設定 (agents / skills / docs)。

> 今後 zsh / git / その他ツールの dotfiles も `dot_*/` で追加していく。

## セットアップ

```bash
brew install chezmoi
chezmoi init lihs-ie/dotfiles        # source を clone
chezmoi diff                          # 反映前に差分確認
chezmoi apply
```

## 更新フロー

```bash
chezmoi add ~/.claude/<path>          # 実体の変更を source に取り込む
chezmoi cd && git add -A && git commit && git push
```

注: `executable_` prefix は +x、`*.tmpl.literal` は中身の `{{...}}` を評価せず literal 保持。
