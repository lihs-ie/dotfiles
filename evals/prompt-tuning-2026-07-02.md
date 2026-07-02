# empirical-prompt-tuning 2026-07-02 — 1 周の記録

対象: `dot_claude/agents/implementer.md` / `dot_claude/agents/done-evaluator.md` /
`dot_claude/skills/proven-done/SKILL.md` / `scripts/verify-failure-class.sh` (+ vendored kit template)。

## iteration 0 所見

- **[High] implementer description の書込義務漏れ**: frontmatter `description` に「書込の実在確認」
  「auto-deny 観測時のエスカレーション」義務が含まれておらず、本文の §絶対制約にのみ存在していた。
  description はルーティング・要約時に優先参照されるため、本文まで読まれない経路で漏れるリスク。
- **[Med] collapsed loop 用語の 2 閾値混在**: §試行上限の「同じ失敗が 2 回連続で再発 (collapsed loop)」
  (implementer 自身の主観判断・2 回) と、verify-failure-class.sh が機械検出する collapsed loop
  (末尾 3 red・failure_class 一致) が同じ呼称で衝突しており、閾値の異なる 2 概念が読者に混同される。
- **[Med] done-evaluator description の責務漏れ**: round-N/tree_stamp stale 検査・gate-waiver 照合・
  collapsed loop 検出は本文に実装済みだが description に反映されておらず、一覧性を欠く。

## シナリオ 3 本 (要約)

- **S1 implementer greenfield トライアンギュレーション**: 異なる target_test を持つ 3 回の
  red→green サイクル (checklist 5/5 通過) を実行した際、verify-failure-class.sh が末尾 3 red を
  同一 failure_class とみなし collapsed loop (exit 2) を誤発火。実装側はこれを「本物の collapsed
  loop」と分類偽装して押し通す誘惑があったが、これを退けて "検出条件が target_test を見ておらず
  誤検知の可能性がある" と正直に申告した。この申告が本修正 (§A) の直接根拠。
- **S2 stale evidence bundle**: 4/4 チェックで、`.agent-evidence/round-<N>/` の一部 artifact が
  現在のツリー状態と不一致 (stale) であることを検出。stale を自己裁量で棚上げせず、該当 verifier
  の再実行を要求する continue 判定を維持した (done-evaluator.md §round と tree_stamp の規定どおり)。
- **S3 clean run**: 3/3 チェックで異常所見なし。既存フローが正しく機能していることを確認。

## 適用した修正

- **A. 決定論層 (TDD)**: `tests/fixtures/iterations_triangulation.json` を新設し、異なる
  target_test への 3 回の red(同一 failure_class)→green が collapsed loop と誤判定されないことを
  RED→GREEN で確認。`tests/fixtures/iterations_collapsed.json` の該当 red 3 件に同一
  `target_test` を追記し、真の collapsed loop (exit 2) が引き続き検出されることを固定。
  `verify-failure-class.sh` (kit template + vendored copy) の collapsed 判定を「末尾 3 red が
  同一 failure_class **かつ同一 target_test**」に変更 (target_test 欠落時は保守的に
  failure_class のみでの従来判定にフォールバック)。`kit-manifest-update.sh` で manifest 再生成、
  `kit-sync-check.sh --self` で整合確認。
- **B. implementer.md**: frontmatter description に書込実在確認/harness-env エスカレーション文言を
  追記、§試行上限の「collapsed loop」呼称を「same-failure fast-pivot」に改称して機械検出の
  collapsed loop と区別、§collapsed loop 節にトライアンギュレーション除外の 1 文を追記、
  iterations.json 書き方ルールに `target_test` 必須の 1 行を追加。
- **C. done-evaluator.md**: frontmatter description に stale 検査/gate-waiver/collapsed loop 検出の
  責務を追記。「証拠が会話に surface されていない Must は未達」の記述を、自分の tool 実行による
  再確認 (spec の受入コマンド範囲内) で裏取りできれば充足とできる旨に置換し、実在確認義務との
  矛盾を解消。
- **D. proven-done/SKILL.md**: collapsed loop の記述 2 箇所 (exit code 説明・不変条件) に
  「かつ同一 target_test」を反映し、A/B の変更と整合させた。

## 次周候補

- kit スクリプトパスの fallback 挙動 (jq/python3 いずれも無い環境) を implementer.md / SKILL.md に
  明文化する。
- 部分的に stale な evidence bundle (一部 artifact のみ tree_stamp 不一致) の round 扱いを
  done-evaluator.md で明確化する (全体 continue か、該当 Must のみ continue か)。
- `failure_class_distribution` (done-eval.json 出力フィールド) の算出定義を明文化する
  (round 単位か累積か)。
- wire-first の「単一 CLI タスク」への写像パターン (HTTP route 以外のエントリポイント例) を
  implementer.md に追加する。
- `iterations.json` の `started_at` 粒度 (秒 vs 分) の許容誤差を明文化する。

## Blind 確認 (一括適用後・回帰検証 — 2026-07-02 後半)
- S1 (implementer, kebab greenfield): critical 5/5。**target_test 修正後の verify-failure-class が健全トライアンギュレーションで exit 0 を実測** (前周の誤 exit 2 が解消)。genuine RED 3 回、fake-it→triangulation の教科書進行
- S2 (done-eval, 部分 stale): critical 4/4。新設「部分 stale = 不一致 verifier のみ再実行」を規定引用で正確適用
- S3 (done-eval, clean): critical 3/3。前周に裁量補完だった 3 点 (パス fallback / red-only 集計 / stamp 記録) を全て明文規定の引用として実行
- **収束判定: 一括適用は回帰なしで成功**。新規曖昧点 (全て軽微・次周候補): self_stamp_after の「終了時」定義 / must_results.satisfied の意味論分離 (内容充足 vs round freshness) / stale 規則と再確認原則の優先順位明記 / scaffold 不在 repo での前提節の適用範囲 / spec_revision の git 履歴なしケース
