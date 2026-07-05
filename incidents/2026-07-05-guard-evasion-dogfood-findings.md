# Incident: guard-evasion-gates dogfood 走行で自己検出した 2 つの設計ギャップ (2026-07-05)

- 文脈: docs/specs/guard-evasion-gates.md (Fix-1) の proven-done 走行 (block→承認→heavy+packets, done-eval=done)。
  本タスクは自分が実装したガードを走行中に retro-activate して dogfood した。その過程での自己検出。
- promotion_candidate: true

## Finding 1: budget-resume gap — tamper guard に正当な cross-session resume 経路が無い

- failure_class: process (設計ギャップ。走行は human 承認で復旧済み)
- 事象: Must-5 の hook-private state (`~/.claude/state/agent-time-budget/<repo-key>/<task>.json`) は
  同一 task 名の `.active` 再作成 (新 started_at) を tamper と判定する — これは意図した動作だが、
  time-budget 超過 → 翌セッション再開という**正当なフロー自体が tamper と同型**になる。
  本走行では budget 96% 超過時に AskUserQuestion 承認 → 人間承認の証跡を commands.txt に記録した上で
  private state を削除して継続した (手動の human-approved 解除)。
- 再発防止候補: resume token 方式 (時間超過時に hook が resume-grant ファイルを発行し、人間が
  それを承認コピーすると 1 回だけ再スタンプ許可) を Fix-2 (stall/liveness) の spec に含める。
  暫定運用ルール: private state の削除は人間のみが行う (orchestrator の自発削除は tamper と同型で禁止)。

## Finding 2: orchestrator が verifier 走行中に evidence を編集 (concurrent-edit race)

- failure_class: process (3rd-party 実害なし。static-verifier が 3-byte race を実検出)
- 事象: Step 5-7 verifier を並列起動した後、Stop hook のブロックを受けて orchestrator が
  completion-report.md の status header を sed で修正 → 並走中の static-verifier が
  「2 回の Read 間でファイルが 3 bytes 成長」を検出した。tree stamp は .agent-evidence を含まないため
  stamp 照合では捕捉されない盲点 (2026-07-02 の verifier-tree-mutation の**逆方向**: verifier が tree を
  変異ではなく、orchestrator が evidence を変異)。
- 再発防止候補: 「verifier 走行中は orchestrator も tree/evidence を変異しない」を SKILL の
  verifier 並列化ルールと併せて明文化 (Fix-4/Fix-6 scope)。機械化するなら evidence-stamp を
  .agent-evidence の当該 round ファイル集合にも拡張。

## 付記 (deviation 記録、事故ではない)
- checkpoint-P4 skip (最終 packet は full battery が上位互換) と Step 5-7 read-only 並列化は
  budget 圧下の documented deviation として done-eval が許容。SKILL への明文化候補 (Fix-4)。
- static-verifier への check 誤指定 (header=complete を Step 5 時点で要求) による false-FAIL 1 周は
  orchestrator 起因。A5 semantics (complete は done-eval.json 存在後のみ) を verifier prompt の
  定型句に含めるべき (Fix-6)。
