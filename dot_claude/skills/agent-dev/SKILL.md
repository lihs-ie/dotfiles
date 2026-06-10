---
name: agent-dev
description: "モック濫用と未配線完了報告を防ぐ多段 AI 開発パイプラインを 1 タスクに対して駆動する。Planner→Explorer→Implementer→決定論ゲート(fitness hook + verify-*.sh)→Static→Integration→Final reviewer を、役割別モデル(Haiku/Sonnet/Opus)と昇格ルールで順に実行し、レビュー 2 周ループ→人間エスカレーションで収束させる。証跡(.agent-evidence/: task-contract / impact-map / wiring-map / commands / completion-report / *-review.json)を必ず残し、Done When は『real public entrypoint から到達可能』で判定する。トリガーは /agent-dev <task> slash command、または『agent-dev で実装』『配線まで保証して実装』『未配線を防ぐパイプラインで』『reviewer 付きで実装してエスカレーションまで』等の依頼。前提: ~/.claude/agents/ の planner/explorer/implementer/integration-verifier/reviewer-static/reviewer-integration/reviewer-final と、対象 repo の AGENTS.md / wiring_manifest.yml / scripts/verify-*.sh。これらが無い repo では先に agent-policy-kit skill で scaffold する。"
---

# agent-dev

要求を 1 つ受け取り、`~/.claude/docs/agent-policy.md` の二大事故
(本番テストダブル混入 / 未配線完了報告) を防ぎながら実装〜レビューまで駆動する。

## 前提チェック (Step 0)

1. 引数 `<task>` を受け取る。無ければユーザーに 1 行で要求を尋ねる。
2. リポジトリルート (`git rev-parse --show-toplevel`) を確認。
3. このリポジトリに `AGENTS.md` と `wiring_manifest.yml` と `scripts/verify-no-prod-doubles.sh`
   が**揃っているか**確認する。**無ければ** 「先に `agent-policy-kit` skill でガードを scaffold
   してください」と案内し、ユーザー承認の上で agent-policy-kit を実行してから続行する。
4. `.agent-evidence/` を作り、**実行中マーカー** を立てる:
   `.agent-evidence/.active` に `task=<task>` と開始時刻を書く
   (これがある間だけ Stop hook の証跡ゲートが発火する)。
5. TaskCreate で進捗 TODO (Plan/Explore/Implement/Gate/Review×3) を作る。

> マーカーは**必ず最後に消す** (PASS でも人間エスカレーションでも)。途中で異常終了して
> `.active` が残った場合に備え、Stop hook のメッセージは解除方法を案内する。

## パイプライン

各段は **Agent tool** で対応する subagent_type を起動し、`model` は下表で上書きする。
Planner が `risk.level=high-risk` を返したら、**high-risk フラグ**を立て、
Integration Verifier / Integration Reviewer / Final Reviewer を **Opus** に昇格する。

| 段 | subagent_type | 既定 model | high-risk 時 | 成果物 |
|---|---|---|---|---|
| 1 Plan | planner | sonnet | opus | `.agent-evidence/task-contract.md` |
| 2 Explore | explorer | haiku | haiku | `.agent-evidence/impact-map.md` |
| 3 Implement | implementer | sonnet | sonnet | code + `wiring-map.json`/`commands.txt`/`completion-report.md` |
| 4 Gate | (skill が直接 Bash 実行) | — | — | `verify-*.log` |
| 5 Verify | integration-verifier | sonnet | opus | `integration-verify.json` |
| 6a Static | reviewer-static | haiku | haiku | `static-review.json` |
| 6b Integration | reviewer-integration | sonnet | opus | `integration-review.json` |
| 6c Final | reviewer-final | opus | opus | `final-review.json` |

### Step 1: Plan
`planner` を起動し Task Contract を生成、`.agent-evidence/task-contract.md` に保存。
`risk.level` を読み high-risk フラグを決める。`## Open questions` があればユーザーに確認。

### Step 2: Explore
`explorer` を起動し Impact Map を生成、`.agent-evidence/impact-map.md` に保存。
orphan(到達不能になりうる)経路の警告があれば Contract に反映。

### Step 3: Implement
`implementer` に **Goal / Context / Constraints / Done When / Evidence Required** の 5 スロットを
Task Contract + Impact Map から埋めて渡す。実装中は PostToolUse の fitness hook が
編集ごとにガード(ast-grep/hlint/lint/test/no-prod-doubles/test-bypass)を回し、違反は exit 2 でブロックされる。
実装者は wiring-map.json / commands.txt / completion-report.md を残す。

### Step 4: Deterministic gates (skill が直接実行)
```
bash scripts/verify-no-prod-doubles.sh   > .agent-evidence/verify-no-prod-doubles.log 2>&1
bash scripts/verify-test-bypass.sh       > .agent-evidence/verify-test-bypass.log 2>&1
bash scripts/verify-wiring.sh            > .agent-evidence/verify-wiring.log 2>&1
```
いずれか非ゼロ終了なら、その出力を implementer に戻して Step 3 へ(レビュー周回にカウントしない)。

### Step 5: Integration verify
`integration-verifier` を起動。build/wiring/entrypoint 到達を実行で確認。FAIL なら Step 3 へ。

### Step 6: Review loop (最大 2 周)
1. `reviewer-static` → `reviewer-integration` → `reviewer-final` を順に起動。
2. いずれかが **FAIL/CONCERNS** を返したら、blocking findings をまとめて `implementer` に戻し、
   Step 3〜5 をやり直して **同じ 3 reviewer を再実行** (これで 1 周)。
3. **2 周終えても FAIL が残る**、または `final-review.json.escalate_to_human=true`、
   または同一 finding が 2 周連続で出た(collapsed loop)場合は **人間にエスカレーション**:
   未解決の blocking findings と該当 artifact パスを提示して停止する。
4. 全 reviewer が **PASS** → 成功。

### Step 7: 後始末と報告
- `.agent-evidence/.active` を **削除** する。
- ユーザーへ対話で次の 3 セクションを返す:
  - **対応した内容** — Goal に対し何をどう実装/結線したか。entrypoint 到達を明記。
  - **変更ファイル一覧** — wiring-map.json と対応付け。
  - **エスカレーション事項** — 残リスク、人間判断が要る点、未実行 smoke 等。

## 不変条件
- テストが緑なだけで「完了」と言わない。wiring map と real entrypoint 到達を示してから完了とする。
- reviewer の指摘は必ずコードパス/artifact に紐付ける。抽象的懸念だけで pass/fail しない。
- 本番パスの test double / test-bypass は allowlist 以外は無条件で差し戻す。
