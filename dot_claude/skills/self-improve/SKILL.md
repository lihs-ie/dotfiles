---
name: self-improve
description: 三層ループの外側ループを駆動する。失敗事例 (incidents/・レビュー指摘・本番補正) を failure-miner でクラスタ化して eval/rule 候補を出し、harness-maintainer で hooks/lints/tests/rubric/正本へ昇格する。incidents → evals → rules/promoted の自己改善を回し、昇格後は新ゲートが発火することを確認する。トリガーは /self-improve、または『失敗をルール化』『再発防止を昇格』『incident を eval に』『harness を直す』『この指摘を二度と出さないように』等。前提: ~/.claude/agents/ の failure-miner / harness-maintainer と、対象 repo の incidents/ evals/ rules/promoted/ memory/lessons/ (無ければ agent-policy-kit で scaffold)。最深モデル (DEEPEST_MODEL = opus、2026-06-22 cutover 完了) を使う。
---

# self-improve

三層ループの **外側ループ**。失敗を「その場の会話」で終わらせず、durable な eval / rule / hook へ昇格する。
人間は結果を直すのではなく、結果を生んだ **harness を直す** 側に回る。

正本: `~/.claude/docs/agent-policy.md` §6 (昇格しきい値)。

## 前提チェック (Step 0)

1. リポジトリルートを確認。`incidents/` `evals/` `rules/promoted/` `memory/lessons/` が在るか確認する。
   **無ければ** 「先に `agent-policy-kit` skill で外側ループ ディレクトリを scaffold してください」と案内する。
2. 対象とする失敗の入力を確定する: `incidents/` のエントリ、直近の `.agent-evidence/*-review.json` の
   blocking findings、ユーザーが渡した補正・本番異常。無ければ「どの失敗を昇格するか」を 1 行尋ねる。

## パイプライン

| 段 | subagent_type | model | 成果物 |
|---|---|---|---|
| 1 Mine | failure-miner | sonnet (多数 incident 集約は **DEEPEST_MODEL**) | rule/eval 候補 (yaml) |
| 2 Promote | harness-maintainer | **DEEPEST_MODEL** | `rules/promoted/<id>.yml` + lesson + 昇格物 |

> **DEEPEST_MODEL** は `agent-policy.md` §7 で定義 (`opus`、2026-06-22 cutover 完了)。
> Agent tool 起動時に `model: "opus"` を渡す。

### Step 1: Mine
`failure-miner` を起動し、`incidents/` と過去のレビュー指摘・補正を **failure class でクラスタ化** させる。
横断集約 (多数 incident) のときは DEEPEST_MODEL で起動する。出力は rule/eval 候補 (occurrences / sources /
proposed_enforcement / static_decidable / priority / rollback_condition)。

### Step 2: しきい値で昇格先を確定 (skill + 人間)
§6 昇格しきい値で候補ごとに昇格先を決める。破壊的・広範な昇格 (CI gate 追加・正本変更) は人間承認を取る。

| 条件 | 昇格先 |
|---|---|
| 同じ指摘が 2 回 | 正本 `agent-policy.md` に短文化 (→ kit 再適用で AGENTS.md/CLAUDE.md に伝播) |
| 同じ failure class が 3 回 | `evals/wiring/` or `evals/spec/` に eval 作成 |
| false negative のコスト高 | CI gate / hook へ昇格 |
| 静的に確実に判定できる | ast-grep / hlint / grep gate (`scripts/verify-*.sh`) |
| 実行時しか判定できない | smoke / E2E / `rubric/core` or `rubric/packs` 項目追加 |
| false positive が多い | memory に戻す / matcher を narrow 化 (rollback) |

### Step 3: Promote
`harness-maintainer` を **DEEPEST_MODEL** で起動し、昇格を実装させる:
- 短文ルール → 正本を直す (生成物 AGENTS.md/CLAUDE.md は直接編集しない)。
- 静的 → ast-grep/hlint or verify スクリプトの grep gate。
- 実行時 → smoke / rubric 項目。
- eval → `evals/` に fixture + 期待結果。
- 記録 → `rules/promoted/<id>.yml` + `memory/lessons/<date>-<slug>.md`。

### Step 4: 発火確認 (必須)
昇格した新ゲートが **実際に発火** することを確認する: わざと違反を作り exit 非ゼロ → clean で exit 0。
false positive が `rollback_condition` を満たすなら narrow に再設計するか memory へ戻す。

### Step 5: 報告
- **昇格した内容** (どの failure class を、どこへ、なぜ)。
- **変更/追加ファイル一覧** (rules/promoted, evals, rubric, 正本, スクリプト)。
- **発火確認結果** (違反で非ゼロ / clean で 0 を示す)。
- **rollback 条件** と残リスク。

## 不変条件
- 昇格は **正本を直してから生成物へ伝播**。生成済み AGENTS.md/CLAUDE.md を直接編集しない。
- 無期限 allowlist を作らない。過剰検出を生む昇格は必ず rollback する。
- lesson は 1 file 1 lesson。誤りと判明したら削除、重複は新規作成せず更新する。
