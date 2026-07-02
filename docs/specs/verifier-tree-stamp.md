# Spec: verifier-tree-stamp

<!-- spec-curator が /grill-me 合意 (2026-07-02) から正規化。 -->

## Goal
- proven-done の verifier artifact (`static-review.json` / `runtime-verify.json` / `spec-review.json` /
  `done-eval.json`) に「どのツリー状態への判定か」を **決定論的に記録** し、
  done-evaluator が stale な旧 FAIL を裁量で棚上げする運用 (native-trace で頻発、2026-07-02 dogfood で
  premature-done レース実測) を機械検査で潰す。
- 具体的には (1) ツリー状態を JSON で出力する `evidence-stamp.sh`、(2) 最新 round の verifier JSON の
  stamp が現在のツリー状態と一致するかを検査する `verify-evidence-freshness.sh` を kit に新設し、
  (3) verifier 判定 JSON 4 種を `.agent-evidence/round-<N>/` に分離し、(4) 4 verifier agent と
  proven-done SKILL.md にこの検査を義務として配線する。

## Must (満たさなければ done でない)
- [ ] **Must-1 (evidence-stamp.sh 新設)**: `dot_claude/skills/agent-policy-kit/templates/scripts/executable_evidence-stamp.sh`
      (KIT テンプレート、shebang 直後に `# KIT_VERSION: <semver>` 行) と、その配布物である
      vendored copy `scripts/evidence-stamp.sh` (executable) が存在する。実行すると stdout に
      1 行の JSON `{"git_sha": "<git rev-parse HEAD の値>", "dirty_diff_hash": "<sha256(git diff HEAD の出力 + git status --porcelain の出力)>"}`
      を出力する (キーはこの 2 つのみ、値は空でも良いが型は string)。
- [ ] **Must-2 (verify-evidence-freshness.sh 新設)**: `dot_claude/skills/agent-policy-kit/templates/scripts/executable_verify-evidence-freshness.sh`
      (KIT テンプレート、`# KIT_VERSION:` 行あり) と vendored copy `scripts/verify-evidence-freshness.sh`
      (executable) が存在する。既定の evidence dir (`.agent-evidence`、`--evidence-dir <dir>` で上書き可能)
      配下で最も番号の大きい `round-<N>/` を最新 round とし、その直下の全 `*.json` ファイルを対象に
      各ファイルの `tree_stamp` フィールド (`{"git_sha":..., "dirty_diff_hash":...}`、フィールド自体が
      無い場合も不一致扱い) を、**同スクリプトが `evidence-stamp.sh` を呼び出して得る**現在のツリー状態
      (sha256 計算ロジックを複製しない) と比較する。挙動:
      (a) 不一致ファイルが 1 つ以上 → 不一致ファイルのパスを列挙して exit 1、
      (b) 存在する全 `*.json` が一致 → exit 0、
      (c) `.agent-evidence` 配下に `round-*` ディレクトリが 1 つも無い (初回) → exit 0。
- [ ] **Must-3 (round-N/ 分離)**: 4 verifier agent (`dot_claude/agents/{static-verifier,runtime-verifier,spec-grader,done-evaluator}.md`)
      の Output セクションの保存先パスが `.agent-evidence/round-<N>/{static-review,runtime-verify,spec-review,done-eval}.json`
      に更新され、`dot_claude/skills/proven-done/SKILL.md` の Step 4 (決定論ゲート) の `verify-*.log`
      リダイレクト先も `.agent-evidence/round-<N>/` に更新される (`round-N` は Step 9 の周回カウントと
      一致、初回 = `round-1` — ログはツリー状態スタンプを持たないため freshness 検査の対象外、
      整理上の同居に留まる)。implementer 成果物 (`completion-report.md` / `commands.txt` /
      `wiring-map.json` / `iterations.json` / `impact-map.md` / `.active`) は **root のまま**変更しない
      (`scripts/agent-evidence-gate.sh` の参照パスは無変更)。
- [ ] **Must-4 (tree_stamp 記録義務 + stale 裁量棚上げ禁止)**: 4 verifier agent の Output JSON スキーマに
      `evidence-stamp.sh` の出力をそのまま埋め込む `tree_stamp` フィールドが必須項目として追加される。
      `done-evaluator.md` には (a) **最新 round のみ**を読む旨、(b) 印不一致 (stale) の判定を
      「stale だから無視してよい」と **自己判断してはならず**、orchestrator に該当 verifier の
      **再実行を要求**する (continue/エスカレーション相当の扱いにする) 旨、の 2 点が明文化される。
- [ ] **Must-5 (proven-done Step 8 構造ゲート拡張)**: `dot_claude/skills/proven-done/SKILL.md` の
      Step 8 ① 構造ゲートに `bash scripts/verify-evidence-freshness.sh` の実行と **exit 0 必須**が
      追加され、非ゼロ時は「該当 verifier を再実行する (done-evaluator の裁量禁止)」という対応方針が
      明記される。同 SKILL.md に round 番号が Step 9 の周回カウントと一致し初回が `round-1` である旨も
      明記される。
- [ ] **Must-6 (kit-manifest 再生成・kit_version 1.1.0 bump)**: `templates/scripts/` 配下の
      **全 12 本** (既存 10 本 + 新規 2 本) の `executable_*.sh` が同一の `# KIT_VERSION: 1.1.0` 行を持つ
      (`kit-manifest-update.sh` は全テンプレート間で単一バージョンの一致を強制し、不一致時 exit 1 で
      落ちるため、bump は新規 2 本だけでなく既存 10 本のバージョン行更新も伴う機械的帰結)。
      `kit-manifest-update.sh` を再実行して生成した `dot_claude/skills/agent-policy-kit/kit-manifest.yml`
      が `kit_version: "1.1.0"` と、`evidence-stamp.sh` / `verify-evidence-freshness.sh` を含む
      12 エントリの sha256 を持つ。
- [ ] **Must-7 (TDD: evidence-stamp / verify-evidence-freshness のケース追加)**: `tests/run-shell-tests.sh`
      に evidence-stamp.sh の出力スキーマを検証するケースと、verify-evidence-freshness.sh の
      match (exit 0) / mismatch (exit 1) / no-round-dir (exit 0) の 3 ケースが追加され、
      対応する `tests/fixtures/` (mismatch・no-round-dir は静的 fixture。match は `git_sha`/`dirty_diff_hash`
      がテスト実行時のライブなツリー状態に依存するため、テスト内で `evidence-stamp.sh` を呼んで
      動的に round dir を構成してから検査する) が存在し、`bash tests/run-shell-tests.sh` が
      fail 0 で終了する。

## Should (望ましいが必須でない)
- `verify-evidence-freshness.sh` の不一致メッセージに、各不一致ファイルの `tree_stamp.git_sha` /
  現在の `git_sha` を併記し、「commit が進んだだけの不一致」か「working tree が変わった不一致」かを
  人間が一瞥で区別できるようにする。
- `dot_claude/skills/agent-policy-kit/SKILL.md` の Phase 2/Sync 節に、新規 2 スクリプトが
  scaffold/sync 対象に含まれる旨を追記する (kit-sync-check.sh の対象範囲は manifest 駆動のため
  自動的に含まれるが、文書上の一覧にも明記する)。

## 受入条件 (acceptance — Must の確認方法)
- Must-1 →
  ```
  test -x scripts/evidence-stamp.sh
  grep -q '^# KIT_VERSION: ' dot_claude/skills/agent-policy-kit/templates/scripts/executable_evidence-stamp.sh
  stamp="$(bash scripts/evidence-stamp.sh)"
  echo "$stamp" | jq -e --arg sha "$(git rev-parse HEAD)" '.git_sha == $sha'
  echo "$stamp" | jq -e '.dirty_diff_hash | test("^[0-9a-f]{64}$")'
  ```
  全コマンド exit 0。
- Must-2 →
  ```
  test -x scripts/verify-evidence-freshness.sh
  grep -q "evidence-stamp.sh" scripts/verify-evidence-freshness.sh   # 二重実装でないこと
  bash scripts/verify-evidence-freshness.sh --evidence-dir <round-* が無い空 dir>; test $? -eq 0
  bash scripts/verify-evidence-freshness.sh --evidence-dir <round-N の全 json が現在の stamp と一致する fixture>; test $? -eq 0
  bash scripts/verify-evidence-freshness.sh --evidence-dir <round-N の json が古い stamp を持つ fixture>; test $? -eq 1
  ```
  最後のコマンドの出力に不一致ファイル名が列挙される (grep で確認)。
- Must-3 →
  ```
  for f in static-verifier runtime-verifier spec-grader done-evaluator; do
    grep -q "round-" dot_claude/agents/$f.md || echo "MISSING round- path: $f"
  done
  grep -q "round-" dot_claude/skills/proven-done/SKILL.md
  ```
  最初のループの出力が空、かつ 2 つ目の grep が一致行を返す。加えて implementer 成果物 6 種の
  ファイル名 (`completion-report.md` 等) が `round-` prefix を伴わず root 参照のまま残っていることを
  目視 diff で確認する (agent-evidence-gate.sh は本 spec の変更対象外)。
- Must-4 →
  ```
  for f in static-verifier runtime-verifier spec-grader done-evaluator; do
    grep -q "tree_stamp" dot_claude/agents/$f.md || echo "MISSING tree_stamp: $f"
  done
  grep -q "stale" dot_claude/agents/done-evaluator.md
  grep -q "再実行" dot_claude/agents/done-evaluator.md
  ```
  最初のループの出力が空、後続 2 つの grep が一致行を返す。
- Must-5 →
  ```
  grep -q "verify-evidence-freshness.sh" dot_claude/skills/proven-done/SKILL.md
  grep -q "round-1" dot_claude/skills/proven-done/SKILL.md
  ```
  両方 exit 0 (一致行あり)。
- Must-6 →
  ```
  bash scripts/kit-manifest-update.sh
  grep -q 'kit_version: "1.1.0"' dot_claude/skills/agent-policy-kit/kit-manifest.yml
  grep -q '^  evidence-stamp.sh:' dot_claude/skills/agent-policy-kit/kit-manifest.yml
  grep -q '^  verify-evidence-freshness.sh:' dot_claude/skills/agent-policy-kit/kit-manifest.yml
  test "$(grep -c '^  [a-zA-Z0-9_.-]*\.sh:' dot_claude/skills/agent-policy-kit/kit-manifest.yml)" -eq 12
  bash scripts/kit-sync-check.sh --self --manifest dot_claude/skills/agent-policy-kit/kit-manifest.yml
  ```
  全コマンド exit 0 (最後の `--self` はテンプレートと manifest の整合確認)。
- Must-7 →
  ```
  grep -c "evidence-stamp" tests/run-shell-tests.sh          # >=1
  grep -c "verify-evidence-freshness" tests/run-shell-tests.sh  # >=3
  bash tests/run-shell-tests.sh; echo $?                     # 0
  ```

## Non-goals (今回やらない)
- **implementer 成果物の round 分離**: `completion-report.md` / `commands.txt` / `wiring-map.json` /
  `iterations.json` / `impact-map.md` / `.active` は root のまま。
- **Stop hook (`scripts/agent-evidence-gate.sh` およびそのテンプレート) の変更**: 参照パス・ロジックとも無変更。
- **消費 repo への rollout**: 新規 2 スクリプト (`evidence-stamp.sh` / `verify-evidence-freshness.sh`) を
  含む kit 変更一式の 5 消費 repo (alpha-mind / am-wt-auditlog / native-trace / recall-paper /
  cloudflare-workers-hs) への sync 適用は別タスク (`agent-policy-kit` の Sync フロー) で行う。
- **`no-new-evidence` 検知の新規導入**: 既存の time-budget 不変条件のスコープ外。
- **既存 10 本の verify-*.sh のロジック変更**: KIT_VERSION 行 (バージョン番号) の機械的更新のみ行い、
  スクリプトの検査ロジック・出力形式は変更しない。

## Risk
- level: high-risk
- escalate_to_opus: true
- 理由:
  - **config**: `kit-manifest.yml` (単一 KIT_VERSION + per-file sha256) と `scripts/verify-*.sh` は
    proven-done の完了ゲート・CI 相当の決定論チェックが直接消費する設定物であり、
    `verify-evidence-freshness.sh` の判定ミス (false negative で stale を見逃す / false positive で
    正当な artifact を stale 扱いする) は完了判定の信頼性を直接損なう。
  - **public export 相当**: `templates/scripts/` 配下は kit が消費 repo に配布する「公開契約」であり、
    kit_version の一括 bump は既存 10 本テンプレートの KIT_VERSION 行 (＝ sha256) 全てに波及する。
  - **meta-wiring 境界跨ぎ**: verifier agent 4 本 (`static-verifier.md`/`runtime-verifier.md`/
    `spec-grader.md`/`done-evaluator.md`) と orchestrator (`proven-done/SKILL.md`) を同時に改修する
    ため、Output スキーマと参照パスの不整合 (どれか 1 本が更新漏れ) が起きると done-evaluator が
    誤った round を読む/tree_stamp を欠いた artifact を PASS 扱いする、という本 spec が防ごうとしている
    事故そのものを再発させかねない。
  - **two-lane router 上の block 相当の懸念**: 本 spec は `config` と `public export 相当` の
    **2 boundary** に触れており (`agent-policy.md` §2.5 の `boundary_touched=multi` の定義に該当しうる)、
    `high-risk AND boundary_touched=multi` は two-lane router の block 条件を満たす。また Must-6 の
    機械的帰結 (既存 10 テンプレートの KIT_VERSION 行更新) を含めると変更ファイル数が
    12 (テンプレート) + 2 (vendored 新規) + 4 (verifier agent) + 1 (SKILL.md) + 1 (manifest) +
    1 (test runner) + 数本の fixture ≈ 25〜30 に達し、`estimated_files > 30` にも接近する。
    実装レーン判定は Open questions Q2 参照。

## Open questions (あれば)
- **Q1 (この repo 自身の既存 vendored コピーの再同期範囲)**: Must-6 で `templates/scripts/` の既存
  10 本の KIT_VERSION 行が 1.1.0 に上がるが、この repo は「kit の配布元かつ消費 repo 第0号」
  (`AGENTS.md` 40 行目) でもある。この repo自身の `scripts/verify-*.sh` (新規 2 本を除く既存 10 本、
  内容非変更・バージョン行のみ diff) を **本タスク内で再同期** (コピー再配置 + chmod) するか、
  `kit-sync-check.sh --check` が非一致時に返す exit 2 (警告のみ・非 block) を許容して次回 sync タスクに
  委ねるか、人間判断が必要。前者を選ぶと Risk 節の `estimated_files` 見積りが確実に 30 を超える。
- **Q2 (two-lane router の block 判定をどう扱うか)**: 本 spec は `high-risk` かつ `config`/`public export相当`
  の 2 boundary に触れるため `boundary_touched=multi` に該当し得る。two-lane router
  (`agent-policy.md` §2.5) 上は **block レーン** (`must_count > 8 OR estimated_files > 30 OR
  (high-risk AND boundary_touched=multi)`) に該当し、素朴には implementer を起動せず
  topology-mapper→spec-grader DEEPEST での分割提案→ユーザーへの `AskUserQuestion` キックオフが必要になる。
  `agent-policy-kit-sync` spec (2026-07-02) で同種の判定に対し Task A/B 分割を行った前例があるが、
  本 spec をそのまま分割するか (例: Task A = evidence-stamp.sh + verify-evidence-freshness.sh + TDD
  [config 境界のみ]、Task B = verifier agent 4 本 + SKILL.md 配線 + kit-manifest bump
  [public export/meta-wiring 境界])、それとも grill-me 済みの一体性を優先し block レーンの判定を
  経由 (topology-mapper 等を通す) した上で一括実装するかは、人間判断が必要。
