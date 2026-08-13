---
name: idchain
description: idchain のフルライフサイクルを状態に応じて再開・進行する。対象 repo の導入状態、Lean 正本、承認、TC、検証レポート、学び台帳を検査し、idchain-init / discovery / spec / approve / build / retro の次に実行可能な1フェーズへルーティングする。Use when (1) ユーザーが「idchain を使って」「idchain で開発して」「次のフェーズへ進めて」「idchain を再開して」と言ったとき、(2) $idchain [対象repo] を実行したとき、(3) 添付資料「『動くだけ』のその先へ」の決定論的ハーネスを一周させたいとき。個別フェーズが明示された場合は対応する idchain-* skill を直接使う。
---

# idchain

idchain の状態を正本と機械出力から判定し、次に実行できる専門 skill を1つだけ選んで実行する。
工程を推測で飛ばさず、人間ゲート G1/G2/G3 では必ずユーザーの判断を待つ。

## 不変条件

- 正本は `<対象repo>/idchain/Canon/*.lean`。`views/*.md` は生成物なので編集しない。
- 実装は、意味一致レビュー済みかつ G2 承認済みの SP と導出済み TC がある場合だけ始める。
- 承認を自動生成しない。G1/G2/G3 はユーザーに現内容と判断材料を提示する。
- テストは SP から導出する。実装から仕様や TC を逆算しない。
- 独立レビューには実装中の会話や判断理由を渡さず、差分と検査観点だけを渡す。
- `lake build`、`check`、`crosscheck`、`report` の失敗を無視して次工程へ進まない。

## 1. 対象 repo を確定する

ユーザーがパスを指定していれば絶対パスへ解決する。未指定なら現在の git root を使う。
対象が git repo でない、または複数候補がある場合だけユーザーに1問で確認する。

```bash
git -C <対象repo> rev-parse --show-toplevel
```

## 2. 状態を観測する

存在するファイルだけを読み、存在しない成果物をエラー扱いせずルーティング材料にする。

```bash
test -f <対象repo>/idchain/idchain.json
test -f <対象repo>/idchain/Canon/Artifacts.lean
test -f <対象repo>/idchain/Canon/Approvals.lean
test -f <対象repo>/idchain/Canon/SemanticReviews.lean
find <対象repo>/idchain/reports -name verification-report.json -type f 2>/dev/null | sort
```

導入済みなら、変更を加える前に現在の決定論的状態を確認する。

```bash
cd <対象repo>/idchain
export PATH="$HOME/.elan/bin:$PATH"
lake build
lake exe idchain check
```

失敗した場合は違反を読み、違反を解消する専門フェーズへ戻す。ゲート違反を実装で迂回しない。

## 3. 次の1フェーズへルーティングする

上から最初に一致した行だけを選ぶ。選んだ専門 skill の `SKILL.md` を全文読み、その手順に従う。

| 観測状態 | 次の skill |
|---|---|
| `idchain/idchain.json` がない | `idchain-init` |
| PB/VL/FA/HY が未起票、または次に検証する課題・仮説が未確定 | `idchain-discovery` |
| G1/G2/G3 の判断が提示済みで、ユーザーが承認・却下・修正を選ぶ段階 | `idchain-approve` |
| SP がない、意味一致レビューがない、SP が未承認、または承認済み SP に TC がない | `idchain-spec` |
| 承認済み SP と TC があり、対応する PASS レポートまたは独立レビュー完了記録がない | `idchain-build` |
| PASS レポートとリリース後の実測値があり、HY 判定または LL/RM 更新が未完了 | `idchain-retro` |
| 一周が完了し、次の課題・仮説を選び直す | `idchain-discovery` |
| 一周が完了し、既存 Why/What 内の次 SP が確定している | `idchain-spec` |

専門 skill は次から読む。

```text
~/.codex/skills/idchain-init/SKILL.md
~/.codex/skills/idchain-discovery/SKILL.md
~/.codex/skills/idchain-spec/SKILL.md
~/.codex/skills/idchain-approve/SKILL.md
~/.codex/skills/idchain-build/SKILL.md
~/.codex/skills/idchain-retro/SKILL.md
```

## 4. フェーズ境界を報告する

各専門 skill の完了時に、次を簡潔に提示する。

- 完了したフェーズと対象 ID
- 実行した決定論的ゲートと結果
- Canon、report、review、learning の成果物パス
- 次に選択されるフェーズ
- ユーザー判断が必要なら、現内容と推奨判断を添えた1問

ユーザーが全工程の継続を依頼していても、人間ゲートでは停止する。承認後は状態を再観測し、
このルーターを先頭から評価して次の1フェーズへ進む。
