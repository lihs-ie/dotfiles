---
name: skill-catalog
description: 87 個以上ある自作 skill の使い分けを解決するルーティング表。Use when (1) ユーザーが「どの skill を使えばいい」「skill 一覧」「skill 整理して」「skill 棚卸し」と言ったとき、(2) /skill-catalog を実行したとき、(3) 新しい skill を作る依頼を受けて既存 skill との重複を確認したいとき、(4) タスクの入口 skill 選択に迷ったとき。INDEX.md (手動管理のルーティング表) が正本で、scripts/generate.sh が USAGE.md (transcripts からの使用実績・未使用リスト) を再生成する。
---

# Skill Catalog

自作 skill 87+ 個の「どれを使うか」を 1 枚で解決する。

## ファイル構成

| ファイル | 役割 | 更新方法 |
|---|---|---|
| `INDEX.md` | ルーティング表 (正本) | 手動。分類と推奨を編集 |
| `USAGE.md` | 使用実績・未使用リスト | `scripts/generate.sh` が上書き |

## モード

### 1. ルーティング (「どの skill 使えばいい？」)

1. `INDEX.md` を Read する
2. ユーザーのタスクを INDEX の「状況」列に照合し、入口 skill を **1 つ** 推奨する
3. 該当なしの場合のみ「skill なしで直接」を推奨する（skill を無理に当てない）

### 2. 棚卸し (「skill 整理して」/ 月次)

1. `bash ~/.claude/skills/skill-catalog/scripts/generate.sh` を実行
2. USAGE.md の「未使用 skill」を確認し、増減をユーザーに報告
3. アーカイブ候補（長期未使用かつ INDEX に載っていない skill）を提案する。
   **移動・削除はユーザー承認後のみ**。承認後は `~/.claude/skills/_archive/<name>/` へ移動
4. INDEX.md の分類が実績と乖離していたら更新を提案する

### 3. 新設ゲート (「〜という skill 作って」への前処理)

新 skill 作成の依頼を受けたら、作る前に必ず:

1. `INDEX.md` と `USAGE.md` で同目的の既存 skill を確認
2. 既存があれば「新設ではなく `empirical-prompt-tuning` での改良」を第一候補として提示
3. 新設する場合は、完成後に INDEX.md の該当セクションへ 1 行追加する（載せない skill は
   発見されず未使用リスト入りする — 61 個の未使用 skill はこれが原因）

## 運用上の注意

- INDEX.md 編集後は dotfiles repo (`~/workspace/dotfiles/dot_claude/skills/skill-catalog/`) にも
  同じ変更を反映する（正本は dotfiles、実体は ~/.claude/skills）
- USAGE.md は自動生成物なので手で編集しない
- generate.sh は transcripts (~/.claude/projects/*/*.jsonl) を読むだけで、書き込みは USAGE.md のみ
