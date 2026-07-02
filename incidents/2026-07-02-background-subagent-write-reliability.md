# incident: background subagent の書込が permission auto-deny で消失し、完了報告だけが返る

- 日付: 2026-07-02 / 発見経路: proven-done dogfood (agent-policy-kit-sync Task A) Step 3.5
- 事象: implementer subagent が 2 周連続で「テスト green・git status 出力付き」の完了報告を返したが、実ディスクへの書込ゼロ。プローブで原因判明: background subagent は permission prompt 不可 → Write が auto-deny。agent は sandbox/セッション内で成功に見える検証 (ls / git status / テスト実行) を実施できてしまい、永続化失敗を自覚できない。
- 影響: 未配線完了報告の最悪形態がハーネス層で量産される。Step 3.5 / Step 8 ① 構造ゲート (証跡実在確認) が 2 回とも正しく捕捉した — 二段門設計の有効性が実証された一方、orchestrator が「捏造」と誤診してモデル非難に向かうリスクも実証された (実際は harness-env)。
- 対処: permission 修正 (acceptEdits / settings allow) 後に再実行で解消。
- 昇格候補 (/self-improve 対象):
  1. proven-done Step 3 の実行前に「subagent 書込プローブ」(1 ファイル書いて orchestrator が実在確認) を追加 → harness-env を 1 tool call で検出、implementer の空回り 2 周 (計 25 分 + 255k tokens) を防ぐ
  2. implementer.md に「書込後は必ず tool result で実在確認。auto-deny エラーを見たら即 harness-env でエスカレーション (作業続行禁止)」を明文化
  3. 差し戻し時の orchestrator 文言は「捏造」と断定せず harness-env 可能性を先に切り分ける

## 追記 (同日 run 完了後の全体像)
- 書込消失の実態は「permission auto-deny 期の完全消失」+「修正後の遅延着地」の複合。差し戻し済み implementer #1 は SendMessage 後も作業を継続し完走していた。
- orchestrator (自分) が差し戻しと同時に implementer #2 を新規起動したため、**implementer 2 体 + orchestrator 代筆の三者並行編集**が発生。runtime-verifier の premature-done 指摘 (証跡が配線に先行) はこのレースの観測。
- 昇格候補 4 (追加): **差し戻しは「既存 agent の再開」か「新規起動」の排他選択とし、並行 implementer を禁止**する規定を proven-done SKILL.md Step 3.5 に明文化。差し戻し前に旧 agent の生死・作業継続有無を確認する。

## 昇格済み (2026-07-02, feat/harness-p0-p4)
正本のみ編集 (deployed ~/.claude は merge で反映):
1. 昇格候補 1 → `dot_claude/skills/proven-done/SKILL.md` **Step 2.7: 書込プローブ** (Step 3 直前に新設)。
2. 昇格候補 2 → `dot_claude/agents/implementer.md` **絶対制約** に「書込の実在を毎回確認する」を追加。
3. 昇格候補 4 (排他選択 / 並行 implementer 禁止) → `SKILL.md` **Step 3.5** item 4。
4. 昇格候補 3 (harness-env 先行切り分け) → `SKILL.md` **Step 3.5** item 5。
