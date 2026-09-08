---
name: idchain
description: idchain のフルライフサイクルを状態に応じて再開・進行する。対象 repo の導入状態、Lean 正本、承認、TC、検証レポート、学び台帳を検査し、idchain-init / discovery / spec / approve / build / retro の次に実行可能な1フェーズへルーティングする。Use when (1) ユーザーが「idchain を使って」「idchain で開発して」「次のフェーズへ進めて」「idchain を再開して」と言ったとき、(2) /idchain [対象repo] を実行したとき、(3) 添付資料「『動くだけ』のその先へ」の決定論的ハーネスを一周させたいとき。個別フェーズが明示された場合は対応する idchain-* skill を直接使う。
---

# idchain

仕様・テスト設計・検証をIDで繋ぎ、固定した利用者成果まで実装サイクルを回す。
状態から次に実行できる専門skillを選ぶ。通常モードは人間ゲートで待ち、明示的な委任実行では
承認済み契約の範囲内を連続実行する。ゲートの検査を省くことと、判断を委任することを混同しない。

## 実行モードと終了境界

ユーザーが一気通貫の実行・代理判断を明示した場合は、最初に
[idchain-approve](../idchain-approve/SKILL.md) の「委任実行」を読み、成果・受入条件・対象外・対象ID・
有限予算を一度に固定する。既に同内容の委任があるなら再質問せず再利用する。
単なる「進めて」から無制限の委任を推測しない。委任契約をエージェント自身で拡張・再承認しない。

追加作業は固定受入条件との対応と必要性を示す。レビュー指摘は範囲内の具体的反例だけを修正し、
将来互換・汎用化・他RMは候補として記録するだけにする。準備は実際の受入検証を妨げる問題の解消に限る。
SP数・文書量ではなく、受入条件の達成数と実観測で進捗を測る。全条件を満たしたら停止し、次RMへ自動移行しない。
進まないときは未承認の追加案を捨てて同じ成果への最小手段に戻す。予算を使い切った場合は増額やID変更で
回避せず、完成済み・残差・必要な人間判断を報告する。

## 不変条件

- 正本は `<対象repo>/idchain/Canon/*.lean`。`views/*.md` は生成物なので編集しない。
- 実装は、意味一致レビュー済みかつ G2 承認済みの SP と導出済み TC がある場合だけ始める。
- 人間承認を捏造しない。委任時は実際のエージェント名・根拠契約・判断を記録し、人間の直接承認と区別する。
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
| 一周が完了し、ユーザーから次の成果の新規依頼がある | `idchain-discovery` |
| 既存 Why/What 内で、まだ未達の委任成果に含まれる次 SP が確定している | `idchain-spec` |
| 固定成果が達成済みで次の成果の依頼がない | 完了報告して停止 |

専門 skill は次から読む。

```text
~/.claude/skills/idchain-init/SKILL.md
~/.claude/skills/idchain-discovery/SKILL.md
~/.claude/skills/idchain-spec/SKILL.md
~/.claude/skills/idchain-approve/SKILL.md
~/.claude/skills/idchain-build/SKILL.md
~/.claude/skills/idchain-retro/SKILL.md
```

## 4. フェーズ境界を報告する

各専門 skill の完了時に、次を簡潔に提示する。

- 完了したフェーズと対象 ID
- 実行した決定論的ゲートと結果
- Canon、report、review、learning の成果物パス
- 次に選択されるフェーズ
- ユーザー判断が必要なら、現内容と推奨判断を添えた1問

委任実行ではフェーズ境界は進捗報告に留め、契約内の次工程へ続ける。人間へ戻すのは範囲変更、
受入条件の緩和、権限を超える操作、予算内で解消できない重大な問題に限る。
不可逆操作等に必要な操作時確認は委任で免除しない。通常モードでは人間ゲートの判断を待つ。
