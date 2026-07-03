# Spec: packet-decomposition-checkpoint

<!-- spec-curator が /grill-me 合意 (2026-07-03) から正規化。 -->

## Goal
- 2026-07-03 の recall-paper ADR-025 Phase A 走行で実証されたボトルネックを解消する:
  (1) heavy レーンが 6 Must / 12 files を単一 implementer に丸投げし 42 分間 13 iterations を無レビューで
  潜行、(2) レビューが構造的に末尾一括 (Step 5-8) にしか存在しない、(3) その末尾レビューすら
  orchestrator が skip 可能で実際に skip され POLICY VIOLATION 残置のまま completion-report が生成された
  (M-CLIENT-02)、(4) collapsed-loop 検知が Step 4 の事後実行のみで live でない。
- **work-packet 分解**で heavy タスクを順序付き packet 列に割り、**packet 毎の checkpoint (static-verifier
  checkpoint モード)** を挟んで潜行を防ぎつつ、二段門 (Step 4-8 のフル battery + done-evaluator) は
  **task 全体で 1 回のまま**に保つ (コスト膨張と二段門破壊を避ける)。加えて Stop hook の 2 つの穴
  (done-eval 不在／gate 違反残置での完了報告) を機械的に塞ぎ、collapsed-loop 検知を live hook 化し、
  タイムスタンプ規律と estimated_files の裁量見積りを是正する。

## Must (満たさなければ done でない)

- [ ] **Must-1 (work-packet 分解 — topology-mapper 拡張)**:
      `dot_claude/agents/topology-mapper.md` に、以下を満たす packet 分解手順が追加される:
      (a) 発火条件 `must_count >= 4 OR estimated_files >= 10 OR layers_touched >= 3`
          (この 3 条件の論理式が文字列としてそのまま記述される) を **heavy レーンでのみ**評価する旨。
      (b) 発火時、既存の impact map 生成と**同一呼び出し内**で (追加 agent 呼び出しを発生させずに)
          packet 分解案を出す旨。
      (c) 分解案の出力スキーマが `packet_id` / `musts` / `target_files` / `done_when` / `depends_on`
          の 5 フィールドを持つ `packets[]` 配列であり、producer-before-consumer 順序
          (ある packet が定義する symbol の消費者を含む packet は `depends_on` で先行 packet を指す)
          で並ぶ旨が明記される。
      (d) `.agent-evidence/impact-map.md` の出力スキーマに `layers_touched` (変更が跨ぐ層数の整数) が
          新設フィールドとして追加される。
      (e) 分解案の**採否確定は orchestrator が行う** (topology-mapper 自身は提案のみ) 旨が明記される。
      `dot_claude/skills/proven-done/SKILL.md` の Step 2 に、上記 (a)〜(e) の要旨
      (発火条件式・同一呼び出し・採否は Step 2.5 で確定) が反映される。

      **`work-packets.json` スキーマ** (spec 内明記、`.agent-evidence/work-packets.json`。
      topology-mapper が最終応答テキストとして返し、orchestrator が Step 2.5 で永続化・
      `decomposition_adopted` を確定する — topology-mapper は現行 tools 通り Write 権限を持たない):
      ```json
      {
        "schema_version": "1.0",
        "task_id": "<task>",
        "trigger_basis": {"must_count": 6, "estimated_files": 12, "layers_touched": 3},
        "decomposition_adopted": true,
        "packets": [
          {
            "packet_id": "P1",
            "musts": ["Must-1", "Must-2"],
            "target_files": ["path/a.ts", "path/b.ts"],
            "done_when": "P1 の Must が checkpoint verdict PASS/CONCERNS で満たされる",
            "depends_on": []
          },
          {
            "packet_id": "P2",
            "musts": ["Must-3"],
            "target_files": ["path/c.ts"],
            "done_when": "P2 の Must が checkpoint verdict PASS/CONCERNS で満たされる",
            "depends_on": ["P1"]
          }
        ]
      }
      ```

- [ ] **Must-2 (packet ループ + checkpoint レビュー)**:
      `dot_claude/skills/proven-done/SKILL.md` の Step 3 が、`work-packets.json` が存在し
      `decomposition_adopted: true` の場合に **packet ループ**へ分岐する旨を明記する:
      (a) packet 毎に implementer を起動 (既定は同一 implementer への `SendMessage` 継続。詳細は Must-3)。
      (b) 各 packet 完了ごとに決定論ゲート (`verify-no-prod-doubles.sh` / `verify-test-bypass.sh` /
          `verify-wiring.sh` / `verify-no-stub-placeholder.sh` / `verify-failure-class.sh`) を
          **累積 diff に対して**実行する旨 — 既存スクリプト群は引数無し実行で常に
          committed∪working-tree の累積差分を見るため (`verify-wiring.sh` 含む)、packet 対象ファイルへの
          引数絞り込みを**行わない**ことが明記される (`commands.txt` に記録されるコマンドが Step 4 と
          同一の引数無し形式であることを acceptance で確認する)。
      (c) `static-verifier` を **checkpoint モード**で 1 回起動し、`.agent-evidence/checkpoint-<packet_id>.json`
          に保存する旨 (`round-<N>/` とは別名前空間)。
      (d) 全 packet 完了後、既存のフル battery (Step 4〜8) を **task 全体で 1 回だけ**実行する旨
          (毎 packet フル battery は行わない — 二段門の意味論を変更しない)。

      `dot_claude/agents/static-verifier.md` に **checkpoint モード**の節が追加される:
      (i) orchestrator から `packet_id` と対象 packet の `target_files`/`musts` を渡されて起動される旨。
      (ii) 通常モードの検査項目 (test-double / bypass / placeholder / allowlist / scope) に加え、
          **方向違い**(spec と異なる層に実装している) と **冗長再実装**(既存実装の重複)の検出を
          checkpoint モード固有の finding として明記する旨。
      (iii) 出力パスが `.agent-evidence/checkpoint-<packet_id>.json` であり、`round-<N>/` 命名規則
          (`verify-evidence-freshness.sh` が `round-*/` のみを走査するため checkpoint artifact は
          freshness 検査の対象外になる — 次 packet がツリーを変異させるため per-packet の stale は
          設計上無害) であることが明記される。
      (iv) 既存の read-only 制約 (`tree_stamp`/`self_stamp_before`/`self_stamp_after`) を checkpoint
          モードでも維持する旨。

      **`checkpoint-<packet_id>.json` スキーマ** (spec 内明記。`verdict`〜`required_followups` は
      static-verifier が書き、`checkpoint_verdict_history`〜`reason_detail` は orchestrator が
      Must-3 の機械判定結果として同ファイルに追記する 2 段階書込):
      ```json
      {
        "schema_version": "1.0",
        "packet_id": "P1",
        "task_id": "<task>",
        "attempt": 1,
        "verdict": "PASS | CONCERNS | FAIL",
        "severity": "P0 | P1 | P2 | P3",
        "tree_stamp": {"git_sha": "", "dirty_diff_hash": ""},
        "self_stamp_before": {"git_sha": "", "dirty_diff_hash": ""},
        "self_stamp_after": {"git_sha": "", "dirty_diff_hash": ""},
        "findings": [
          {
            "title": "",
            "why_it_matters": "",
            "evidence": "",
            "exact_missing_wiring_or_rule": "",
            "suggested_fix": ""
          }
        ],
        "required_followups": [],
        "checkpoint_verdict_history": ["FAIL", "FAIL"],
        "continuation_decision": "continue | fresh | escalate",
        "reason_code": "fail-x2 | agent-dead | collapsed-loop | packet-over-budget | null",
        "reason_detail": "checkpoint verdict FAIL x2 consecutive for packet_id=P1"
      }
      ```

- [ ] **Must-3 (implementer 継続性の機械的判定)**:
      `dot_claude/skills/proven-done/SKILL.md` の packet ループ節に、継続可否判定が
      **enum のみ**で行われる旨が明記される (抽象裁量による fresh 起動・escalation を禁止):
      - 既定: `continuation_decision: continue` (`SendMessage` で同一 implementer に次 packet +
        checkpoint findings を渡す)。
      - `fail-x2`: 同一 `packet_id` の checkpoint `verdict` が **FAIL 2 回連続** →
        `continuation_decision: fresh` (findings 付き packet contract を再発行して新規 implementer)。
      - `agent-dead`: `SendMessage` エラー/応答なし (既存の生死確認ルール適用) →
        `continuation_decision: fresh`。
      - `collapsed-loop`: checkpoint 時点の `verify-failure-class.sh` が exit 2 →
        `continuation_decision: escalate`、既存 **Step 6.5 oracle-change branch** へ routing
        (fresh ではない)。
      - `packet-over-budget`: packet 経過時間 > `1.5 × (レーン budget ÷ packet 数)` (文字列
        `1.5 ×` がそのまま記述される) →
        `continuation_decision: escalate` (残 packet の再分解提案、または `AskUserQuestion` で
        エスカレーション。fresh 継続はしない)。
      - 上記 4 reason_code 以外の理由での fresh 起動・escalation は禁止である旨が明記される。
      判定入力は全て決定論的 (checkpoint JSON の `verdict` 履歴、UTC タイムスタンプ、exit code) である旨。

- [ ] **Must-4 (Stop hook 強制 — done-eval 存在検査)**:
      `scripts/agent-evidence-gate.sh` と kit テンプレート
      `dot_claude/skills/agent-policy-kit/templates/scripts/executable_agent-evidence-gate.sh`
      (両者内容一致、`KIT_VERSION` 行含む) が拡張され、以下を満たす:
      (a) `--evidence-dir <dir>` オプションを追加 (既定 `.agent-evidence`。テスト容易性のため、
          既存 `agent-time-budget.sh`/`verify-evidence-freshness.sh` と同じ慣例)。
      (b) 既存チェック (`completion-report.md`/`commands.txt`/`wiring-map.json` 非空) に加え、
          `<evidence-dir>/.active` が存在し `completion-report.md` が非空のとき、
          `<evidence-dir>/round-*/` のうち番号最大のディレクトリ (`verify-evidence-freshness.sh` と
          同じ「最大 N」判定ロジック) 直下の `done-eval.json` が非空で存在するかを確認する。
      (c) `round-*` ディレクトリが 1 つも無い、または最新 round に `done-eval.json` が無い/空の場合、
          代替証跡 (`<evidence-dir>/time-budget-exceeded.md` が非空、または
          `<evidence-dir>/escalation-*.md` に該当する非空ファイルが 1 つ以上) があれば許可 (exit 0)、
          無ければ **exit 2 で Stop をブロック**し、stderr に `done-eval.json` を含むメッセージを出す。

- [ ] **Must-5 (Stop hook 強制 — gate 違反ブロック)**:
      同スクリプト (`agent-evidence-gate.sh` / kit テンプレート) に追加で:
      (a) `--quarantine <file>` オプションを追加 (既定 `ci/quarantine.yml`)。
      (b) Must-4 で判定した最新 `round-<N>/` 配下の `verify-*.log` を走査し、`"POLICY VIOLATION"`
          文字列を含むログが 1 つ以上あるか確認する。
      (c) 該当ログがある場合、そのログの basename (`verify-<name>.log` → 対象ゲート名 `verify-<name>.sh`)
          が `<quarantine>` の `gates:` エントリのうち `gate` フィールドに部分一致し、
          `expires_at` が実行日以降 (未期限切れ) かつ `substitute_verification` が非空のエントリで
          waive されているかを確認する (この Stop hook の waiver 判定は形式的整合性チェックに限定し、
          代替検証証跡の実体確認は done-evaluator の意味判定に委ねる — 二重実装しない旨を明記する)。
      (d) waive されない POLICY VIOLATION ログが 1 つでも残れば **exit 2 で Stop をブロック**し、
          stderr に `"POLICY VIOLATION"` と該当ログのパスを含める。全て waive済み、または
          POLICY VIOLATION が無ければ許可 (exit 0)。
      Must-4/5 実装後、`kit-manifest-update.sh` で `kit-manifest.yml` の
      `agent-evidence-gate.sh` エントリの `sha256` のみが更新され (`kit_version` は `"1.1.0"` のまま)、
      `kit-sync-check.sh --self` が exit 0 になる。

- [ ] **Must-6 (collapsed-loop の live hook 化)**:
      新規テンプレート
      `dot_claude/skills/agent-policy-kit/templates/scripts/executable_collapsed-loop-guard.sh`
      (`# KIT_VERSION: 1.1.0` 行あり) と vendored copy `scripts/collapsed-loop-guard.sh`
      (executable、内容・KIT_VERSION 行ともテンプレートと同一) が存在し、**PostToolUse hook** として
      次を満たす (`agent-time-budget.sh` の実証済み stdin JSON パターンを踏襲):
      (a) stdin から hook JSON を読む。`--evidence-dir <dir>` オプション対応 (既定 `.agent-evidence`)。
      (b) `hook_event_name`/`tool_name` が欠落・未知の場合は **fail-safe allow (exit 0) + stderr 診断**
          (agent-time-budget.sh と同じ fail-safe 方針)。
      (c) `tool_name` が `Write`/`Edit` 以外、または `tool_input.file_path` を正規化した結果が
          `<evidence-dir>/iterations.json` と一致しない場合は exit 0 (no-op)。
      (d) 一致する場合、`bash scripts/verify-failure-class.sh <evidence-dir>/iterations.json` を実行し:
          - exit 0 または exit 1 → exit 0 (schema 違反は Step 4/static-verifier の担当。この hook は
            collapsed loop (exit 2) のみを扱う)。
          - exit 2 (collapsed loop) → **非ブロック警告**として stderr に verify-failure-class.sh の
            メッセージ相当を含め、**exit 2** で終了する (PostToolUse の非ブロック警告意味論。
            `docs/specs/agent-time-budget-hook.md` Amendments Q3 と同じ経路)。
      配線: `dot_claude/skills/agent-policy-kit/templates/settings-hooks.snippet.json` の
      `PostToolUse` 配列に `collapsed-loop-guard.sh` (matcher `Write|Edit`) を追加、
      dotfiles 自身の `.claude/settings.json` にも同様に追加 (dogfood)、
      `dot_claude/skills/agent-policy-kit/SKILL.md` の scaffold 対象スクリプト一覧・`.claude/settings.json`
      節に追記。`kit-manifest-update.sh` 実行後、`kit-manifest.yml` に
      `collapsed-loop-guard.sh` エントリ (sha256 付き) が追加されエントリ総数が 13→**14** になり、
      `kit_version` は `"1.1.0"` のまま。

- [ ] **Must-7 (UTC タイムスタンプ規律)**:
      (a) `dot_claude/agents/implementer.md` の iterations.json 書き方ルールに、
      「`started_at` は `date -u +%Y-%m-%dT%H:%M:%SZ` で取得した実時刻に限り、**ローカル時刻を
      Z 付きで書くことを禁止する**」という明示的な禁止文が追加される (既存の「作業順の代替値で
      埋めない」規定を、ローカル時刻誤表記という具体的な禁止パターンで補強する)。
      (b) `scripts/verify-failure-class.sh` と kit テンプレート
      `dot_claude/skills/agent-policy-kit/templates/scripts/executable_verify-failure-class.sh`
      (両者内容一致) に、`started_at` が存在する各 `iterations[]` entry についてタイムスタンプ検査が
      追加される:
      - **未来時刻**: entry の `started_at` が現在 UTC + 5 分を超える → exit 1 (メッセージに
        `future` の語を含む)。
      - **逆行**: entry の `started_at` (`started_at` を持つ) が、`iterations[]` 配列順で直前の
        `started_at` を持つ entry の値より前 → exit 1 (メッセージに `regress` または `逆行` の語を
        含む)。
      - GNU date (`date -u -d`) と BSD date (`date -u -j -f`) の両方でエポック秒に変換できる実装
        (`tests/run-shell-tests.sh` の既存 `iso8601_seconds_ago` ヘルパーと同じ移植パターン)。
      既存の `iterations_valid.json`/`iterations_collapsed.json`/`iterations_triangulation.json`
      フィクスチャの exit code (0/2/0) は変更されない (回帰なし)。

- [ ] **Must-8 (estimated_files の接地 + Step 2 後の再 triage)**:
      (a) `dot_claude/agents/spec-curator.md` の Output 契約 (Risk 節テンプレート) に、
      リテラル文字列 `estimated_files: <N> (basis:` を含む行が追加され、`basis` に
      「変更が波及しそうなファイルを Glob/Grep で列挙したコマンドまたは参照」を書く旨の説明が
      追加される (裸の当て推量を禁止する)。
      (b) `dot_claude/skills/proven-done/SKILL.md` に **Step 2.5**
      (「実測 file 数での再 triage + packet 分解の採否確認」、Step 2 と Step 2.7 の間に位置) が
      新設され、以下を満たす:
      - topology-mapper の impact-map.md に列挙された変更対象・結線先ファイル (Public entrypoints /
        Wiring points / Blast radius 各節) の総数 (重複除去) を実測 `estimated_files` として算出する旨。
      - 実測値が block 閾値 (`estimated_files > 30`、既存 Step 1.5 の block 条件と同一の数値) を
        超えたら、Step 1.5 の block レーンと同じ手順 (`blocking_reasons` を列挙し `.active` を削除して
        停止、分割提案へ) を取る旨。
      - Must-1 の packet 分解発火条件 (`must_count >= 4 OR estimated_files >= 10 OR layers_touched >= 3`)
        を、この**実測値**で再判定し、`work-packets.json` の `decomposition_adopted` を確定する旨
        (spec-curator の初期見積りではなく、この Step 2.5 の実測値を採用する)。

## Should (望ましいが必須でない)

- `collapsed-loop-guard.sh` の警告メッセージに `iterations.json` の `failure_class` 分布を併記し、
  implementer が単純な繰り返しなのか同一原因の collapsed loop なのかを自己判断しやすくする。
- `checkpoint-<packet_id>.json` の `continuation_decision`/`reason_code` 履歴を
  `completion-report.md` にサマリとして含め、人間が packet ループの全体像を後から追える形にする。
- Must-7 のタイムスタンプ検査を、`iterations[]` の `started_at` だけでなく `.agent-evidence/iterations.json`
  トップレベルの `started_at` (task 開始時刻) にも将来的に拡張できる形にしておく (本 spec は
  `iterations[]` のみを対象とする)。
- `agent-evidence-gate.sh` の block メッセージに、該当ログを確認するための具体コマンド
  (例: `cat .agent-evidence/round-<N>/verify-wiring.log`) を含める。
- `dot_claude/skills/agent-policy-kit/SKILL.md` Phase 3 のスモークテスト一覧に
  `collapsed-loop-guard.sh` の合成 collapsed fixture での exit 2 確認を追記する。

## 受入条件 (acceptance — Must の確認方法)

- Must-1 →
  ```
  grep -q "must_count >= 4" dot_claude/agents/topology-mapper.md
  grep -q "estimated_files >= 10" dot_claude/agents/topology-mapper.md
  grep -q "layers_touched >= 3" dot_claude/agents/topology-mapper.md
  grep -q "work-packets.json" dot_claude/agents/topology-mapper.md
  grep -q "packet_id" dot_claude/agents/topology-mapper.md
  grep -q "depends_on" dot_claude/agents/topology-mapper.md
  grep -q "producer-before-consumer\|producer.*consumer" dot_claude/agents/topology-mapper.md
  grep -q "layers_touched" dot_claude/agents/topology-mapper.md
  grep -q "work-packets.json" dot_claude/skills/proven-done/SKILL.md

  # 埋め込み例の JSON スキーマ妥当性 (spec 本文の work-packets.json 例をそのまま検査)
  cat <<'JSON' | jq -e '.packets | type == "array" and length >= 1'
  {"packets":[{"packet_id":"P1","musts":["Must-1"],"target_files":["a"],"done_when":"x","depends_on":[]}]}
  JSON
  cat <<'JSON' | jq -e '.packets[0] | has("packet_id") and has("musts") and has("target_files") and has("done_when") and has("depends_on")'
  {"packets":[{"packet_id":"P1","musts":["Must-1"],"target_files":["a"],"done_when":"x","depends_on":[]}]}
  JSON
  ```
  全コマンド exit 0。

- Must-2 →
  ```
  grep -q "checkpoint-" dot_claude/agents/static-verifier.md
  grep -q "checkpoint" dot_claude/skills/proven-done/SKILL.md
  grep -q "冗長" dot_claude/agents/static-verifier.md
  grep -q "方向違い\|方向が違う\|レイヤー違い" dot_claude/agents/static-verifier.md
  grep -q "累積" dot_claude/skills/proven-done/SKILL.md
  grep -q "1 回だけ\|1回だけ" dot_claude/skills/proven-done/SKILL.md

  # 埋め込み例の JSON スキーマ妥当性
  cat <<'JSON' | jq -e 'has("verdict") and has("tree_stamp") and has("continuation_decision") and has("reason_code") and has("checkpoint_verdict_history")'
  {"verdict":"PASS","tree_stamp":{},"continuation_decision":"continue","reason_code":null,"checkpoint_verdict_history":[]}
  JSON

  # verify-evidence-freshness.sh は round-*/ のみ走査するため checkpoint-*.json (round 外) は
  # stale 判定に影響しないことを回帰テストで確認する (tests/run-shell-tests.sh に追加):
  #   fixture: <dir>/checkpoint-P1.json (故意に古い tree_stamp) を round-* が無い/ある両方の
  #   evidence-dir 直下に置き、bash scripts/verify-evidence-freshness.sh --evidence-dir <dir> が
  #   exit 0 のままであること (checkpoint ファイルが誤検出されない)。
  bash tests/run-shell-tests.sh 2>&1 | grep -q "checkpoint"
  ```
  全コマンド exit 0 (最後の grep は新規追加した checkpoint 関連テストケースが実在することの確認)。

- Must-3 →
  ```
  grep -q "fail-x2" dot_claude/skills/proven-done/SKILL.md
  grep -q "agent-dead" dot_claude/skills/proven-done/SKILL.md
  grep -q "collapsed-loop" dot_claude/skills/proven-done/SKILL.md
  grep -q "packet-over-budget" dot_claude/skills/proven-done/SKILL.md
  grep -q "continuation_decision" dot_claude/skills/proven-done/SKILL.md
  grep -q "reason_code" dot_claude/skills/proven-done/SKILL.md
  grep -q "1.5 ×\|1\\.5倍\|1\\.5 \\*" dot_claude/skills/proven-done/SKILL.md
  ```
  全 exit 0 (一致行あり)。

- Must-4 →
  ```
  test -x scripts/agent-evidence-gate.sh
  grep -q '^# KIT_VERSION: ' dot_claude/skills/agent-policy-kit/templates/scripts/executable_agent-evidence-gate.sh

  # (a) round-1/done-eval.json 欠落 + completion-report.md あり + 代替証跡なし -> block
  # fixture: <dir>/.active, completion-report.md(非空), commands.txt(非空), wiring-map.json(非空),
  #          round-1/ に done-eval.json を置かない
  err="$(bash scripts/agent-evidence-gate.sh --evidence-dir tests/fixtures/agent-evidence-gate/missing-done-eval < /dev/null 2>&1 1>/dev/null)"
  ec=$?; test "$ec" -eq 2 && printf '%s' "$err" | grep -q "done-eval.json"

  # (b) 同 fixture + escalation-*.md あり -> allow
  bash scripts/agent-evidence-gate.sh --evidence-dir tests/fixtures/agent-evidence-gate/missing-done-eval-escalated < /dev/null
  test $? -eq 0

  # (c) round-1/done-eval.json 非空で存在 + POLICY VIOLATION 無し -> allow
  bash scripts/agent-evidence-gate.sh --evidence-dir tests/fixtures/agent-evidence-gate/normal-done < /dev/null
  test $? -eq 0

  # 既存挙動の回帰: completion-report.md 等 3 点セット欠落は従来通り exit 2
  bash scripts/agent-evidence-gate.sh --evidence-dir tests/fixtures/agent-evidence-gate/missing-core-evidence < /dev/null
  test $? -eq 2
  ```
  全コマンド期待通りの exit code / grep 一致。

- Must-5 →
  ```
  # (d) round-1/verify-wiring.log に POLICY VIOLATION + waiver 無し -> block
  err="$(bash scripts/agent-evidence-gate.sh --evidence-dir tests/fixtures/agent-evidence-gate/gate-violation-unwaived < /dev/null 2>&1 1>/dev/null)"
  ec=$?; test "$ec" -eq 2 && printf '%s' "$err" | grep -q "POLICY VIOLATION"

  # (e) 同種違反 + ci/quarantine.yml gates: に期限内 waiver (gate: "verify-wiring.sh" 相当) -> allow
  bash scripts/agent-evidence-gate.sh \
    --evidence-dir tests/fixtures/agent-evidence-gate/gate-violation-waived \
    --quarantine tests/fixtures/agent-evidence-gate/gate-violation-waived/quarantine.yml < /dev/null
  test $? -eq 0

  # (f) waiver の expires_at が過去 -> block
  bash scripts/agent-evidence-gate.sh \
    --evidence-dir tests/fixtures/agent-evidence-gate/gate-violation-expired-waiver \
    --quarantine tests/fixtures/agent-evidence-gate/gate-violation-expired-waiver/quarantine.yml < /dev/null
  test $? -eq 2

  bash scripts/kit-manifest-update.sh
  bash scripts/kit-sync-check.sh --self --manifest dot_claude/skills/agent-policy-kit/kit-manifest.yml
  ```
  全コマンド期待通りの exit code / grep 一致。

- Must-6 →
  ```
  test -x scripts/collapsed-loop-guard.sh
  grep -q '^# KIT_VERSION: ' dot_claude/skills/agent-policy-kit/templates/scripts/executable_collapsed-loop-guard.sh

  # (合成 iterations.json: 3 red 同一 class+target = 既存 tests/fixtures/iterations_collapsed.json を再利用)
  mkdir -p tests/fixtures/collapsed-loop-guard/collapsed tests/fixtures/collapsed-loop-guard/healthy
  cp tests/fixtures/iterations_collapsed.json tests/fixtures/collapsed-loop-guard/collapsed/iterations.json
  cp tests/fixtures/iterations_valid.json tests/fixtures/collapsed-loop-guard/healthy/iterations.json

  err="$(echo '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/tests/fixtures/collapsed-loop-guard/collapsed/iterations.json"}}' \
    | bash scripts/collapsed-loop-guard.sh --evidence-dir tests/fixtures/collapsed-loop-guard/collapsed 2>&1 1>/dev/null)"
  ec=$?; test "$ec" -eq 2 && printf '%s' "$err" | grep -Eiq 'collapsed|collapse'

  echo '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/tests/fixtures/collapsed-loop-guard/healthy/iterations.json"}}' \
    | bash scripts/collapsed-loop-guard.sh --evidence-dir tests/fixtures/collapsed-loop-guard/healthy
  test $? -eq 0

  echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{}}' \
    | bash scripts/collapsed-loop-guard.sh --evidence-dir tests/fixtures/collapsed-loop-guard/collapsed
  test $? -eq 0

  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/tests/fixtures/collapsed-loop-guard/collapsed/iterations.json"}}' \
    | bash scripts/collapsed-loop-guard.sh --evidence-dir tests/fixtures/collapsed-loop-guard/collapsed
  test $? -eq 0   # hook_event_name 欠落 = fail-safe allow

  grep -q "collapsed-loop-guard.sh" dot_claude/skills/agent-policy-kit/templates/settings-hooks.snippet.json
  grep -q "collapsed-loop-guard.sh" .claude/settings.json
  grep -q "collapsed-loop-guard.sh" dot_claude/skills/agent-policy-kit/SKILL.md

  bash scripts/kit-manifest-update.sh
  grep -q '^  collapsed-loop-guard.sh:' dot_claude/skills/agent-policy-kit/kit-manifest.yml
  test "$(grep -c '^  [a-zA-Z0-9_.-]*\.sh:' dot_claude/skills/agent-policy-kit/kit-manifest.yml)" -eq 14
  grep -q 'kit_version: "1.1.0"' dot_claude/skills/agent-policy-kit/kit-manifest.yml
  bash scripts/kit-sync-check.sh --self --manifest dot_claude/skills/agent-policy-kit/kit-manifest.yml
  bash scripts/kit-sync-check.sh --check --manifest dot_claude/skills/agent-policy-kit/kit-manifest.yml
  ```
  全コマンド期待通りの exit code / grep 一致。

- Must-7 →
  ```
  grep -q "ローカル時刻を" dot_claude/agents/implementer.md
  grep -q "禁止" dot_claude/agents/implementer.md   # 既存文脈中にも出現するため上の行と合わせて目視確認

  # (動的 fixture: テスト実行時刻基準で未来/逆行タイムスタンプを生成)
  # future: iterations[0].started_at = now + 1h
  # regress: iterations[1].started_at < iterations[0].started_at
  out_future="$(bash scripts/verify-failure-class.sh tests/fixtures/iterations_future_timestamp.json 2>&1)"; ec=$?
  test "$ec" -eq 1 && printf '%s' "$out_future" | grep -qi "future"

  out_regress="$(bash scripts/verify-failure-class.sh tests/fixtures/iterations_regressed_timestamp.json 2>&1)"; ec=$?
  test "$ec" -eq 1 && printf '%s' "$out_regress" | grep -Eiq "regress|逆行"

  # 既存 fixture の exit code 回帰なし
  bash scripts/verify-failure-class.sh tests/fixtures/iterations_valid.json; test $? -eq 0
  bash scripts/verify-failure-class.sh tests/fixtures/iterations_collapsed.json; test $? -eq 2
  bash scripts/verify-failure-class.sh tests/fixtures/iterations_triangulation.json; test $? -eq 0

  diff dot_claude/skills/agent-policy-kit/templates/scripts/executable_verify-failure-class.sh scripts/verify-failure-class.sh \
    | grep -v KIT_VERSION | grep -v '^[0-9]'  # shebang/KIT_VERSION 行以外は同一 (空出力)
  ```
  全コマンド期待通りの exit code / grep 一致 (`iterations_future_timestamp.json`/
  `iterations_regressed_timestamp.json` は実装者が `date -u` でテスト実行時刻基準に動的生成する
  ヘルパーとして `tests/run-shell-tests.sh` に追加する — agent-time-budget-hook Must-6 の
  `iso8601_seconds_ago` パターンを踏襲)。

- Must-8 →
  ```
  grep -q "estimated_files: <N> (basis:" dot_claude/agents/spec-curator.md
  grep -q "Step 2.5" dot_claude/skills/proven-done/SKILL.md
  grep -q "estimated_files > 30" dot_claude/skills/proven-done/SKILL.md
  grep -q "must_count >= 4" dot_claude/skills/proven-done/SKILL.md   # Step 2.5 が Must-1 の閾値を実測値で再判定する旨
  grep -q "decomposition_adopted" dot_claude/skills/proven-done/SKILL.md
  grep -q "blocking_reasons" dot_claude/skills/proven-done/SKILL.md  # 既存 Step 1.5 の block 手順を Step 2.5 でも再利用
  ```
  全 exit 0 (一致行あり)。

- **横断 (全 Must 共通)** →
  ```
  bash tests/run-shell-tests.sh; echo $?   # 0 (既存 30 ケース回帰なし + 新規ケース green)
  chezmoi diff   # dot_claude/ の変更が意図した差分のみであることを目視確認 (dry-run。実 apply は merge 後)
  ```

## Non-goals (今回やらない)

- DTO field-completeness rubric (native-trace orphaned-field 事故由来) — backlog 送り。
- **毎 packet フル battery / done-evaluator の複数回実行** — 二段門意味論の変更禁止。フル battery は
  task 全体で 1 回のまま。
- no-new-evidence 検知の自動化 (v2 送りのまま)。
- **block レーン / light レーンの判定式変更** — Step 2.5 の再 triage は実測値の適用であり、
  two-lane router の閾値式自体 (`agent-policy.md` §2.5) は変更しない。
- `agent-time-budget.sh` 自体への per-packet budget 組込み — packet 予算判定 (Must-3
  `packet-over-budget`) は orchestrator (SKILL.md 側の判定) に留め、hook のロジックは変更しない
  (hook の cross-tool 互換リスク回避)。
- **`ci/allowlist.yml` 単体でのゲート POLICY VIOLATION 免除** — Must-5 の Stop hook waiver は
  `ci/quarantine.yml` の `gates:` に一本化する (`ci/allowlist.yml` は各 verify スクリプト自身が
  test-double 個別許可として既に消費済みであり、POLICY VIOLATION が Stop hook まで残る時点で
  allowlist は既に不十分と判定されている — 二重実装しない)。
- 決定論ゲート 5 本 (`verify-no-prod-doubles.sh` 等) 自体の検査ロジック変更。Must-2 は
  「呼び出し方法 (累積・引数無し) の規律」のみを扱う。
- `spec-grader.md`/`done-evaluator.md` の waiver 判定ロジック自体の変更 (`docs/specs/gate-waiver.md`
  で確定済みの意味判定はそのまま。Must-5 の Stop hook は形式チェックのみの別レイヤー)。
- 5 消費 repo (alpha-mind / am-wt-auditlog / native-trace / recall-paper / cloudflare-workers-hs) への
  kit rollout。本 spec は dotfiles 側テンプレート・このリポジトリ自身の vendored コピー・dogfood
  配線までを対象とする。
- deployed `~/.claude` への実際の `chezmoi apply` 実行。本 spec は `chezmoi diff` による差分確認までを
  対象とし、実 apply は PR merge 後の別工程 (既存運用踏襲、`memory/proven-done-bottleneck-audit-2026-07`
  「deployed agent prompt は merge するまで更新されない」)。

## Risk

- level: high-risk
- escalate_to_opus: true
- must_count: 8
- estimated_files: ~20 (basis: 実装対象の列挙 —
  `dot_claude/agents/{topology-mapper,static-verifier,implementer,spec-curator}.md` (4) +
  `dot_claude/skills/proven-done/SKILL.md` (1) +
  `scripts/{agent-evidence-gate,verify-failure-class,collapsed-loop-guard}.sh` (3) +
  同 3 本の kit テンプレート `templates/scripts/executable_*.sh` (3) +
  `templates/settings-hooks.snippet.json` (1) + `.claude/settings.json` (1) +
  `dot_claude/skills/agent-policy-kit/{SKILL.md,kit-manifest.yml}` (2) +
  `tests/run-shell-tests.sh` (1) = 16 コアファイル、これに
  `tests/fixtures/**` 新規 (agent-evidence-gate 系 6 dir 前後 + collapsed-loop-guard 系 2 dir +
  timestamp 系 2 file, 見積り 8-10) を加えて ≈ 24-26。範囲の中心を取り ~20〜25 と見積る)。
- boundary_touched: multi (config / event subscription / public export相当 の 3 boundary)
- 理由:
  - **config**: `.claude/settings.json` の hook 配線・`ci/quarantine.yml` の `gates:` 参照・
    `kit-manifest.yml` の再生成という設定物を直接変更する。
  - **event subscription**: 新規 `PostToolUse` hook (`collapsed-loop-guard.sh`) の登録、および
    既存 `Stop` hook (`agent-evidence-gate.sh`) の block 条件拡張という Claude Code ライフサイクル
    イベント購読を新設・変更する。判定ミスは「本来 block すべき未配線完了を止め損なう」
    (M-CLIENT-02 再発) と「正当な完了報告を誤って block する」の両事故モードを持つ。
  - **public export相当**: `dot_claude/skills/agent-policy-kit/templates/**` (新規スクリプト2本 +
    既存スクリプト拡張1本 + settings スニペット + kit-manifest.yml 更新) は 5 消費 repo に配布される
    kit の公開契約であり、将来の sync で全消費 repo に波及する。
  - **two-lane router 上の block 懸念**: `high-risk AND boundary_touched=multi` は two-lane router の
    block 条件を満たしうる。ただし本 spec の 8 Must は実質的に 2 グループに分離可能で、
    Must-1/2/3/8 (packet 分解パイプライン: `dot_claude/agents/{topology-mapper,static-verifier,
    spec-curator}.md` + `dot_claude/skills/proven-done/SKILL.md` のみに触れ、`.claude/settings.json`
    や kit テンプレートには触れない) は DI/routing/auth/config/migration/schema/public export/
    background job/event subscription の**いずれにも該当しない**可能性が高く、
    Must-4/5/6/7 (hook 強制: `.claude/settings.json`/kit テンプレート/`kit-manifest.yml` に触れる)
    のみが上記 3 boundary を持つ。詳細は Open questions Q1 参照 (人間判断が必要)。

## Open questions (あれば)

- **Q1 (block レーン判定と Task 分割の要否)**: 上記 Risk 節の通り、本 spec は `high-risk` かつ
  `boundary_touched=multi` (config / event subscription / public export相当) に該当しうるため
  two-lane router の block 条件に抵触しうる。一方で 8 Must は自然に 2 群に分かれる:
  - **Task A候補 = Must-1/2/3/8** (packet 分解 + checkpoint + 継続性判定 + estimated_files 接地):
    `dot_claude/agents/{topology-mapper,static-verifier,spec-curator}.md` と
    `dot_claude/skills/proven-done/SKILL.md` のみに触れ、`.claude/settings.json` や
    `agent-policy-kit/templates/**` には触れない。9 boundary のいずれにも非該当の可能性が高く、
    `low-risk` または最大でも single-boundary になりうる。
  - **Task B候補 = Must-4/5/6/7** (Stop hook 強制 + collapsed-loop live hook + timestamp 規律):
    `scripts/*.sh` + kit テンプレート + `.claude/settings.json` + `kit-manifest.yml` に触れ、
    `docs/specs/agent-time-budget-hook.md`/`gate-waiver.md` と同型の
    `high-risk AND boundary_touched=multi` に該当する。
  先例 (`agent-policy-kit-sync.md` Task A/B 分割、`agent-time-budget-hook.md` Amendments Q2 の
  「heavy レーンで一括実装 (人間キックオフは grill-me で取得済み)」裁定) のどちらに倣うか、
  すなわち (a) 本 spec のまま 1 タスクとして block レーン手順 (topology-mapper → spec-grader
  DEEPEST → `AskUserQuestion`) を経由して heavy 実装するか、(b) 上記 Task A/B に分割し Task A を
  先行実装するか、人間判断が必要。
- **Q2 (Step 9 収束ループと packet ループの相互作用)**: 全 packet 完了後のフル battery (Step 5-8) が
  FAIL/continue を返し Step 9 が Step 3 へ差し戻した場合、(i) packet ループ全体をやり直すのか、
  (ii) FAIL の原因になった Must を含む packet だけを `work-packets.json` 上で再オープンするのか、
  (iii) packet 機構を使わず通常の単発 implementer 差し戻しに切り替えるのか、grill-me 合意に明記が
  無い。本 spec は Must-2/3 を「(ii): 該当 packet のみ再オープンし通常の checkpoint ループを再実行する」
  という前提で書いているが、この前提の妥当性は人間確認が必要。

## Amendments

- **A1 (2026-07-03, Q1 裁定)**: 1 タスク heavy + packet 分解自己適用で一括実装する。two-lane router の
  block 条件 (`high-risk AND boundary_touched=multi`) には形式該当するが、block レーンの趣旨である
  「人間キックオフ」は grill-me 2 ラウンド + 本 Q1 裁定で取得済み (先例:
  `docs/specs/agent-time-budget-hook.md` Amendments Q2)。Task A/B 分割はしない (分割が与えるはずの
  分解便益は work-packet 自己適用が代替する)。PR は 1 本、packet 境界で atomic commit。
- **A2 (2026-07-03, Q2 裁定)**: Step 9 差し戻しは **(ii) 該当 packet のみ再オープン**で確定
  (spec 本文の暫定前提を確定に昇格)。blocking findings → Must → packet の対応付けは
  `work-packets.json` の `packets[].musts` を索引に機械的に行う。差し戻し後のフル battery は
  従来通り task 全体で再実行する (二段門不変)。
- **A3 (2026-07-03, dogfood 中の欠陥発見 → 本 spec に修正を追加)**: **wall clock budget の起点欠陥**。
  `.active` の `started_at` が Step 0 起点のため、grill-me / spec 化の人間対話時間 (本走行の実測で
  約 40 分) が implementer の実装 budget (heavy=90min) を食い潰す。2026-06-29 事故 (agent-time-budget-hook
  の動機) の対象は autonomous 実装ループの暴走であり、人間対話の待ち時間ではない。修正:
  `dot_claude/skills/proven-done/SKILL.md` の Step 1.5 に「`lane=` 追記と同時に `started_at` を
  現在 UTC で**再スタンプ**する (spec 化までの人間対話時間を budget から除外するため)」を明記する。
  hook (`agent-time-budget.sh`) 側の変更は無し。受入:
  `grep -q "再スタンプ" dot_claude/skills/proven-done/SKILL.md` が exit 0。本走行にも自己適用する
  (lane=heavy 追記時に再スタンプ)。
- **A4 (2026-07-03, dogfood 中の欠陥発見 → 本 spec に修正を追加)**: **前タスク残骸による
  `.agent-evidence/` 汚染**。Step 10 は `.active` を削除するが implementer 成果物 (iterations.json /
  commands.txt / wiring-map.json / completion-report.md / round-N/ / wiring-waivers.txt) を残置する
  ため、次タスクが旧 task_id の iterations.json を引き継ぎ、verify-failure-class.sh・failure_class
  分布・freshness 検査が前タスクのデータを誤読する (本走行で topology-mapper が merge 済み前タスク
  `verify-wiring-long-lived-branch-blindspot` の残骸と期限なし wiring-waiver の残置を実検出)。
  修正: `dot_claude/skills/proven-done/SKILL.md` Step 0 に「`.active` を書く前に、既存の implementer
  成果物が残っていれば `.agent-evidence/_archive/<旧 task_id>/` へ退避する」を明記する (P1 に同梱)。
  `wiring-waivers.txt` への期限導入は backlog 送り。受入:
  `grep -q "_archive" dot_claude/skills/proven-done/SKILL.md` が exit 0。本走行にも自己適用する
  (旧 task 残骸を `_archive/` へ退避済み)。
- **A5 (2026-07-03, dogfood 中の欠陥発見 → Must-4 の詳細設計を置換)**: **Stop 証跡ゲートが
  「途中停止」と「完了主張」を区別できない**。A4 の残骸退避直後の turn 終了で
  `agent-evidence-gate.sh` が発火し、pipeline 進行中の正当な一時停止 (background subagent 待ち /
  AskUserQuestion 待ち) が 3 点セット不在でブロックされることが実証された。従来顕在化しなかったのは
  前タスク残骸が gate を偽 pass させていたため (A4 の汚染が本欠陥を隠蔽)。さらに Must-4 の原設計
  (completion-report.md 存在 + done-eval.json 不在 → block) をそのまま実装すると 3 点セット要求と
  合成されて「Step 8 前の全 turn 終了がブロックされる」deadlock になる。修正 (Must-4(b)(c) を置換):
  - `completion-report.md` に必須ヘッダ `status: in-progress | complete | escalated` を導入し、
    作成時点 (Step 3 開始時) から living document として運用する (implementer.md と SKILL.md
    Step 10 に明記。Step 10 / escalation 時に status を確定値へ更新する)。
  - gate 判定 3 分岐: (a) `.active` あり + completion-report.md 不在 or `status: in-progress` →
    **途中停止として allow**。ただし `commands.txt` 非空を要求 (最低限の作業ログ強制)。
    (b) `status: complete` → 最新 round-N/`done-eval.json` 非空、かつ未 waive の POLICY VIOLATION
    なし (Must-5) を要求。欠けば exit 2。(c) `status: escalated` → `escalation-*.md` または
    `time-budget-exceeded.md` 非空を要求。
  - Must-4 受入条件の fixture はこの 3 分岐を反映する (missing-done-eval 系 fixture の
    completion-report.md は `status: complete` を持つ。加えて `status: in-progress` で allow される
    fixture を 1 つ追加する)。本走行にも自己適用する (証跡 3 点を living document として即設置)。
