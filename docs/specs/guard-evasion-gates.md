# Spec: guard-evasion-gates

<!-- spec-curator が /grill-me 合意 + 実測 incident 3 件 (2026-07-03/2026-07-04) から正規化。
     6-fix campaign の Fix-1 のみを対象とする。Fix-2..6 は Non-goals 参照。
     2026-07-05: spec-grader DEEPEST (`.agent-evidence/block-lane-spec-review.json`, verdict=CONCERNS)
     を受けたユーザー承認済み kickoff amendment を適用 (詳細は末尾 `## Amendments`)。 -->

## Goal
- proven-done の完了判定が実際に迂回された 3 経路 (spec self-amend / git stash escape / `.active` tamper)
  を、決定論的スクリプト + hook で検出・遮断する。
- 検出は「本物の正当経路 (承認済み amend / 無関係な user stash / Step 1.5 の唯一の正当 re-stamp)」を
  誤検知しないことを Must と同格で要求する (harness infrastructure の false-positive は以後の全
  proven-done 実行をブロックするため)。

## Must (満たさなければ done でない)

- [ ] **Must-1 (spec-amend スタンプ記録)**: `.agent-evidence/.active` に Step 1.5 (`lane=` 追記時) で
      `spec_sha256=<sha256(docs/specs/<task>.md)>` が同時に書き込まれる (`dot_claude/skills/proven-done/SKILL.md`
      Step 1.5 に明文化)。Step 6.5 の oracle-change branch でユーザー承認 (`AskUserQuestion`) を得た場合、
      `.agent-evidence/oracle-change-approval.json` (フィールド: `spec_path` / `old_spec_sha256` /
      `new_spec_sha256` / `approved_at` (ISO8601 UTC) / `approval_summary`) が書かれ、その後 `.active` の
      `spec_sha256=` が新ハッシュに再記録される。これが唯一の正当な amend 経路であることが
      `dot_claude/skills/proven-done/SKILL.md` Step 6.5 に明文化される。

- [ ] **Must-2 (spec-amend 検出)**: `scripts/verify-guard-integrity.sh` の spec-amend サブチェックが、
      `.active` の `task=` から特定した `docs/specs/<task>.md` の現在の sha256 を計算し `spec_sha256=`
      スタンプと比較する:
      (a) スタンプ未記録 (lane 未確定) → 非対象、exit 0。
      (b) 一致 → exit 0。
      (c) 不一致 かつ `.agent-evidence/oracle-change-approval.json` が非存在、または存在しても
          `new_spec_sha256` が現在のハッシュと一致しない → `POLICY VIOLATION` を出力して非ゼロ終了。
      (d) 不一致だが有効な `oracle-change-approval.json` (`new_spec_sha256` が現在ハッシュと一致) が
          存在する → exit 0 (承認済み amend は許可)。

- [ ] **Must-3 (stash-escape ベースライン記録)**: Step 0 (`.active` 作成時) に、その時点の
      `git stash list` の全 ref/ハッシュをベースラインとして記録する (`.agent-evidence/.active` の
      追加行、または `.agent-evidence/` 配下の別ファイル — 保存場所は実装者裁量だが Must-4 の検出が
      参照できる形にする)。`dot_claude/skills/proven-done/SKILL.md` Step 0 にこの記録を明文化する。
      **[amendment: falsifiable 化]** 記録形式は、Step-0-simulation 実行時点の `git stash list` 出力を
      単一の抽出コマンドで取り出せて `diff`/文字列比較により完全一致を機械判定できる形でなければならない
      (下記 受入条件・Must-8 (iv) の fixture テストがこの diff を実行する — doc-grep のみでは
      falsifiable でないため)。

- [ ] **Must-4 (stash-escape 検出、task-touched-files 述語)**: `scripts/verify-guard-integrity.sh` の
      stash-escape サブチェックが、ベースライン後に追加された stash entry ごとに
      `git stash show --name-only <stash-ref>` でタッチしたファイル一覧を取り、それぞれが
      `.agent-evidence/wiring-map.json` に列挙されたファイル、または現在のタスク diff
      (`verify-wiring.sh` と同じ committed(base...HEAD)∪working-tree の union 規約 — `BASE_REF` 未設定時は
      committed∪staged∪unstaged∪untracked、明示時は committed のみ) に含まれるファイルと 1 件でも
      重複するかを判定する:
      (a) ベースライン後の新規 stash が無い → exit 0。
      (b) 新規 stash はあるが、いずれもタスク対象ファイルと無関係 (user の無関係な背景 WIP) →
          exit 0 (無関係 stash は必ず pass させる)。
      (c) 新規 stash のいずれかがタスク対象ファイルをタッチしている → `POLICY VIOLATION` を出力して
          非ゼロ終了。

- [ ] **Must-5 (`.active` tamper 検出 — time-budget hardening)**: `scripts/agent-time-budget.sh` が
      `(task, started_at, lane)` の hook-private コピーを **リポジトリ working tree の外側**
      (既定 `$HOME/.claude/state/agent-time-budget/`、リポジトリパス+task でキー、テスト用に
      `--state-dir <dir>` で上書き可能 — 既存 `--evidence-dir` と同じ慣例) に保持する:
      (a) 対象 `task` を初めて見る (private コピー未存在) 時点で `.active` の現在値から private コピーを
          作成する。
      (b) 正当な re-stamp は **1 回のみ**許可する: `lane=` 行が (private コピーにまだ記録されていない
          状態から) 初めて現れた時点 (Step 1.5 Amendment A3 の re-stamp) で、hook は private コピーの
          `started_at`/`lane` を更新する。
      (c) それ以降、`.active` の `started_at` が private コピーの `started_at` と食い違い、かつ private
          コピーに既に `lane` が記録済み (= 正当な re-stamp が既に起きた後) の場合は **tamper** と判定し、
          budget 計算に private コピーの `started_at` を使う (`.active` の値は無視する)。PreToolUse の
          deny メッセージ・PostToolUse の警告メッセージの双方に、re-stamp が検出され無視された旨を
          明記する。
          **[amendment: falsifiable 化]** この「private の値が判定を支配する」ことを exit code
          レベルで証明するため、Must-8 の deny-vs-allow-band fixture では private コピー側の
          `started_at` を deny 帯 (ratio≥1.0) に、`.active` 側の (tamper 後の) `started_at` を allow 帯
          (ratio<0.75) に対応する値に設定する。実装が private コピーを正しく使っていれば PreToolUse で
          **exit 2** (deny) が返り、`.active` の値を誤って使ってしまう実装なら exit 0 (allow) になる —
          この exit code の分岐そのものが、再スタンプ検出「メッセージ」の grep より強い証拠になる
          (メッセージ grep は引き続き併用する)。
      (d) `docs/specs/agent-time-budget-hook.md` Must-6 の既存 fixture (heavy-50/heavy-82/heavy-110/
          lane-missing、いずれも private コピー未存在の「初見」状態) は本変更後も同一の exit code で
          通ること (回帰なし)。

- [ ] **Must-6 (wire-first)**: 上記 3 検出が real entrypoint から到達可能である:
      (a) `scripts/verify-guard-integrity.sh` が新設され、spec-amend (Must-2) と stash-escape (Must-4) の
          両サブチェックを順に実行し、どちらかが `POLICY VIOLATION` を出す場合は非ゼロ終了、両方 pass /
          非対象なら exit 0。
      (b) `dot_claude/skills/proven-done/SKILL.md` Step 4 の決定論ゲート battery
          (`mkdir -p .agent-evidence/round-<N>` に続く 5 本のコマンド列) に
          `bash scripts/verify-guard-integrity.sh > .agent-evidence/round-<N>/verify-guard-integrity.log 2>&1`
          が追加される。
      (c) Step 8 の構造ゲート記述に、`verify-evidence-freshness.sh` と並んで `verify-guard-integrity.sh`
          の exit 0 必須が追記される。
      (d) `scripts/agent-evidence-gate.sh` (Stop hook) が `status: complete` 分岐で
          `bash scripts/verify-guard-integrity.sh` を **その場で直接実行**し (`round-<N>/` の古いログの
          スキャンだけに頼らない — 最終 Step 4 実行後・完了主張前に起きた tamper/escape を逃さないため)、
          非ゼロ終了なら `block()` する。
          **[amendment: fixture 制約]** この直接実行性を「round-log の走査だけでは達成できない」形で
          証明するため、受入条件の fixture は round-<N>/ 配下の `verify-guard-integrity.log` が
          clean (POLICY VIOLATION 不在) であるか、そもそも当該ログファイルが存在しない状態にする。
          その状態でも `agent-evidence-gate.sh` が exit 2 を返すことで、判定が round-log スキャンでは
          なく in-place 直接実行に由来することを機械的に示す。
      (e) **[user-approved scope add]** `dot_claude/skills/proven-done/SKILL.md` Step 4 の決定論ゲート
          battery に `bash tests/run-shell-tests.sh > .agent-evidence/round-<N>/run-shell-tests.log 2>&1`
          の 1 行が追加され、Must-8 の guard 回帰スイート (spec-amend/stash-escape/active-tamper の
          全 fixture ケース) が毎 round 自動実行される。
      (f) **[Should→Must 昇格]** `scripts/agent-evidence-gate.sh` の `is_gate_waived` (substring 部分
          一致) が `verify-guard-integrity.sh` の `POLICY VIOLATION` を waive **できない**:
          `ci/quarantine.yml` の `gates:` エントリが `verify-guard` あるいは `guard-integrity` を
          substring として含んでいても、`status: complete` + spec-amend/stash-escape 違反 fixture に
          対しては waiver が適用されず exit 2 のまま終了する。これは evasion-detection 違反を機械的に
          waive 不能にする **anti-accident invariant のみ**を対象とし、「意図的な期限付き waiver
          運用ポリシーの是非」という論点 (下記 Non-goals 参照、変更なし) には触れない。

- [ ] **Must-7 (canonical-first kit sync + doc 更新)**:
      (a) `dot_claude/skills/agent-policy-kit/templates/scripts/executable_agent-time-budget.sh` /
          `executable_agent-evidence-gate.sh` を正本として先に更新し、新規
          `executable_verify-guard-integrity.sh` テンプレートを追加する。
      (b) `bash scripts/kit-manifest-update.sh` 実行後、`dot_claude/skills/agent-policy-kit/kit-manifest.yml`
          の `kit_version` が amendment 時点の現行値 `"1.1.0"` から新バージョンへ bump され
          (`kit-manifest-update.sh` は全テンプレート間で `KIT_VERSION` 不一致があれば非ゼロ終了するため、
          単一バンプが機械的に強制される)、`verify-guard-integrity.sh` エントリが追加され、
          テンプレートエントリ総数が既存 14 本から **15 本**になる。
          **[amendment: falsifiable 化]** 受入条件は「エントリが存在する」grep だけでなく、
          (1) `kit_version` の値が変更前後で異なることの直接比較、(2) `^  [A-Za-z0-9_.-]*\.sh:`
          パターンに一致するエントリ行数が 15 であることの `-eq` assertion、の両方を機械的に確認する
          (`docs/specs/agent-time-budget-hook.md` Must-5 の `-eq 13` style を踏襲)。
      (c) repo-local `scripts/agent-time-budget.sh` / `scripts/agent-evidence-gate.sh` /
          `scripts/verify-guard-integrity.sh` が対応テンプレートとバイト一致する
          (`bash scripts/kit-sync-check.sh --self` と `--check` の両方が exit 0)。
      (d) `dot_claude/skills/proven-done/SKILL.md` の Step 0 (`.active` スキーマ + stash baseline)、
          Step 1.5 (`spec_sha256=` スタンプ + hook 側 re-stamp 挙動)、Step 4/Step 8 (Must-6 の battery/
          構造ゲート追記)、Step 6.5 (`oracle-change-approval.json` が唯一の正当 amend 経路である旨) が
          更新される。
      (e) `dot_claude/docs/agent-policy.md` に `verify-guard-integrity.sh` (spec-amend / stash-escape の
          2 サブチェック) への最小限の参照が追加される (既存の証跡提出・Done 二段門の記述箇所に 1 行程度)。
      (f) **[Should→Must 昇格]** `dot_claude/skills/agent-policy-kit/SKILL.md` の Phase-2 Apply
          scaffold コピー対象スクリプト一覧 (SKILL.md:31-35、現行 13 本を列挙) に
          `verify-guard-integrity.sh` を追加する (Must-7(a) と同一 packet (P4) で行う — 新規消費 repo
          への scaffold 時にテンプレートが死蔵されないようにするため)。

- [ ] **Must-8 (テスト: red/green + 正当経路)**: `tests/run-shell-tests.sh` に、Must-2/Must-4/Must-5 の
      各検出について最低 3 ケースずつ (計 9 ケース以上) が fixture 駆動で追加される:
      spec-amend: (i) 未承認 mismatch → 非ゼロ, (ii) hash 一致 → exit 0, (iii) 承認済み
      `oracle-change-approval.json` あり → exit 0。
      stash-escape: (i) タスク対象ファイルをタッチする新規 stash → 非ゼロ, (ii) stash 無し → exit 0,
      (iii) 無関係な新規 stash → exit 0, (iv) **[amendment]** Must-3 の baseline 記録が
      Step-0-simulation 実行時点の `git stash list` 出力と diff/文字列比較で完全一致する
      (stash-baseline fixture)。
      active-tamper: (i) **[amendment: falsifiable 化]** 正当 re-stamp 後にさらに `.active` の
      `started_at` を書き換える tamper — **deny-vs-allow-band fixture** (private コピー側
      `started_at` は deny 帯 (ratio≥1.0)、`.active` 側 (tamper 後) `started_at` は allow 帯
      (ratio<0.75)) を用い、private コピー基準で判定されて **exit 2** (deny 帯の verdict がそのまま
      返ることで private 値の支配を証明) かつ re-stamp 検出メッセージを含む,
      (ii) tamper 無し (通常経過) → 既存 Must-6 fixture と同じ exit code,
      (iii) 唯一の正当 re-stamp (Step 1.5 A3) → private コピーが更新され exit 0。
      `bash tests/run-shell-tests.sh` が追加後も fail 0 で終了する。

## Should (望ましいが必須でない)

- `POLICY VIOLATION` メッセージに、どちらのサブチェック (spec-amend / stash-escape) が失敗したかを
  1 行目で明示する。waiver 不能自体は Must-6(f) で機械的に保証されるため、本項目は診断メッセージの
  可読性向上のみを扱う (waiver 運用ガイドへの「spec-amend/stash-escape の POLICY VIOLATION は原則
  waive 対象外」明記は、Must-6(f) の mechanical invariant を補足する運用ドキュメントとして引き続き
  望ましい)。
- private コピー (`$HOME/.claude/state/agent-time-budget/`) のディスク肥大防止のため、
  `.active` 削除 (Step 10) と同時に対応する private コピーも削除するクリーンアップを検討する。

## 受入条件 (acceptance — Must の確認方法)

- Must-1 →
  ```
  grep -A3 "spec_sha256=" dot_claude/skills/proven-done/SKILL.md | grep -qi "lane="
  grep -q "oracle-change-approval.json" dot_claude/skills/proven-done/SKILL.md
  # fixture: Step0->Step1.5 相当をシミュレートし、.active に spec_sha256= が実ファイルの
  # sha256sum(docs/specs/<task>.md) と一致することを確認する回帰テスト (Must-8 参照)
  ```

- Must-2 →
  ```
  bash scripts/verify-guard-integrity.sh --evidence-dir <stamp未記録 fixture>; test $? -eq 0
  bash scripts/verify-guard-integrity.sh --evidence-dir <hash一致 fixture>;     test $? -eq 0
  err=$(bash scripts/verify-guard-integrity.sh --evidence-dir <未承認mismatch fixture> 2>&1 1>/dev/null)
  test $? -ne 0 && printf '%s' "$err" | grep -q "POLICY VIOLATION"
  bash scripts/verify-guard-integrity.sh --evidence-dir <承認済みapproval fixture>; test $? -eq 0
  ```

- Must-3 →
  ```
  grep -A5 "^前提チェック (Step 0)" dot_claude/skills/proven-done/SKILL.md | grep -qi "stash"
  # fixture (tests/fixtures/guard-evasion-gates/stash-baseline/): scratch git repo で
  # Step-0-simulation (Step 0 のベースライン記録ロジック相当) を実行した直後、同一プロセス内で
  # `git stash list` を再実行し、記録されたベースラインと診断的に diff/文字列比較する。
  # 完全一致でなければ非ゼロ終了になるテストとして tests/run-shell-tests.sh に追加する
  # (Must-8 stash-escape (iv) 参照)。doc-grep のみでは falsifiable でないため必須。
  actual="$(git -C <scratch-repo> stash list)"
  bash <Step-0-simulation の実行コマンド> --evidence-dir <scratch-repo>/.agent-evidence
  recorded="$(<記録されたベースラインを抽出するコマンド — 実装が定めたスキーマに従う>)"
  test "$recorded" = "$actual"
  ```

- Must-4 →
  ```
  bash scripts/verify-guard-integrity.sh --evidence-dir <新規stashなし fixture>;         test $? -eq 0
  bash scripts/verify-guard-integrity.sh --evidence-dir <無関係stash fixture>;           test $? -eq 0
  err=$(bash scripts/verify-guard-integrity.sh --evidence-dir <タスク対象ファイルをタッチする stash fixture> 2>&1 1>/dev/null)
  test $? -ne 0 && printf '%s' "$err" | grep -q "POLICY VIOLATION"
  ```

- Must-5 →
  ```
  # (a) 初見: private コピーが state-dir に作成される
  echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
    | bash scripts/agent-time-budget.sh --evidence-dir <task=/started_at=のみの fixture> --state-dir <scratch>
  test -f <scratch>/.../<task>.json   # private コピー実在

  # (b) 唯一の正当 re-stamp: lane= 追記後、private コピーが新 started_at/lane に更新される
  echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
    | bash scripts/agent-time-budget.sh --evidence-dir <lane=heavy 追記済み fixture> --state-dir <scratch>
  grep -q "<新started_at>" <scratch>/.../<task>.json

  # (c) tamper: re-stamp 後に .active の started_at のみ書き換え、private コピー基準で判定される。
  #     [amendment] deny-vs-allow-band fixture: private コピー側 started_at は deny 帯 (ratio≥1.0)
  #     相当、.active 側 (tamper 後) started_at は allow 帯 (ratio<0.75) 相当に設定する。
  out=$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
    | bash scripts/agent-time-budget.sh --evidence-dir <deny-vs-allow-band tamper済み fixture> --state-dir <scratch> 2>&1 1>/dev/null)
  test $? -eq 2   # private 側 (deny 帯) の verdict がそのまま返ることで private 値の支配を証明
  printf '%s' "$out" | grep -Eiq "re-stamp|再スタンプ"

  # (d) 既存 Must-6 fixture (heavy-50/82/110/lane-missing) が state-dir 未使用 (=初見) でも同一 exit code
  bash tests/run-shell-tests.sh   # 既存 agent-time-budget ケースが引き続き PASS
  ```

- Must-6 →
  ```
  grep -q "verify-guard-integrity.sh" dot_claude/skills/proven-done/SKILL.md   # Step4/Step8 双方に出現
  grep -c "verify-guard-integrity.sh" dot_claude/skills/proven-done/SKILL.md   # >= 2 (Step4 battery + Step8 記述)
  grep -q "verify-guard-integrity" scripts/agent-evidence-gate.sh

  # (d) [amendment] fixture 制約: round-<N>/ の verify-guard-integrity.log が clean/absent でも
  #     exit 2 になることで「round-log 走査ではなく in-place 直接実行」であることを証明する
  bash scripts/agent-evidence-gate.sh --evidence-dir <status:complete + tampered spec + clean/absent round-log fixture>; test $? -eq 2
  bash scripts/agent-evidence-gate.sh --evidence-dir <status:complete + 全て正当 fixture>;      test $? -eq 0

  # (e) [user-approved scope add] run-shell-tests.sh が Step 4 battery に追加される
  grep -q "run-shell-tests.sh" dot_claude/skills/proven-done/SKILL.md
  bash tests/run-shell-tests.sh; test $? -eq 0

  # (f) [Should→Must 昇格] quarantine waiver の substring match が verify-guard-integrity.sh の
  #     POLICY VIOLATION を waive できない
  bash scripts/agent-evidence-gate.sh --evidence-dir <status:complete + tampered spec + "verify-guard"/"guard-integrity" substring waiver 付き ci/quarantine.yml fixture>; test $? -eq 2
  ```

- Must-7 →
  ```
  test -f dot_claude/skills/agent-policy-kit/templates/scripts/executable_verify-guard-integrity.sh
  pre_version="1.1.0"   # amendment 時点の現行値 (Read で確認済み)
  bash scripts/kit-manifest-update.sh
  post_version="$(grep '^kit_version:' dot_claude/skills/agent-policy-kit/kit-manifest.yml | sed -E 's/^kit_version: *"?([^"]*)"?/\1/')"
  test "$post_version" != "$pre_version"
  grep -q '^  verify-guard-integrity.sh:' dot_claude/skills/agent-policy-kit/kit-manifest.yml
  test "$(grep -c '^  [A-Za-z0-9_.-]*\.sh:' dot_claude/skills/agent-policy-kit/kit-manifest.yml)" -eq 15
  bash scripts/kit-sync-check.sh --self  --manifest dot_claude/skills/agent-policy-kit/kit-manifest.yml
  bash scripts/kit-sync-check.sh --check --manifest dot_claude/skills/agent-policy-kit/kit-manifest.yml
  grep -q "oracle-change-approval.json" dot_claude/skills/proven-done/SKILL.md
  grep -q "verify-guard-integrity" dot_claude/docs/agent-policy.md
  grep -q "verify-guard-integrity.sh" dot_claude/skills/agent-policy-kit/SKILL.md   # (f) scaffold copy list
  ```
  全コマンド exit 0。

- Must-8 →
  ```
  test "$(grep -ci 'spec-amend'   tests/run-shell-tests.sh)" -ge 3
  test "$(grep -ci 'stash-escape' tests/run-shell-tests.sh)" -ge 3
  test "$(grep -Eic 'active-tamper|re-stamp' tests/run-shell-tests.sh)" -ge 3
  test "$(grep -ci 'stash-baseline'     tests/run-shell-tests.sh)" -ge 1   # Must-3 diff fixture
  test "$(grep -ci 'deny-vs-allow-band' tests/run-shell-tests.sh)" -ge 1   # Must-5(c) band fixture
  bash tests/run-shell-tests.sh; test $? -eq 0
  ```

## Non-goals (今回やらない)

- **Fix-2 (subagent stall/liveness handling)** — 別 spec。
- **Fix-3 (kit-sync-check manifest fallback / 配布修復)** — 別 spec。
- **Fix-4 (light レーン fast path・model-floor compliance)** — 別 spec。
- **Fix-5 (timeout/curl portability shims)** — 別 spec。
- **Fix-6 (prompt-corpus contradiction cleanup)** — 別 spec。
- **消費 repo (alpha-mind / am-wt-auditlog / native-trace / recall-paper / cloudflare-workers-hs) への
  本 fix のロールアウト** — merge 後の別タスク (kit sync)。
- **`docs/specs/agent-time-budget-hook.md` 自体の Must 書き換え** — 本 spec は同ファイルの Must-1〜6 を
  変更せず、Must-5 として追加的にハードニングするのみ (既存 fixture の exit code に回帰がないことを
  Must-5(d)/Must-8 で保証する)。
- **`ci/quarantine.yml` への spec-amend/stash-escape 違反の実際の waiver 登録** — 本 spec は
  「原則 waive 対象外」という運用ガイド追記 (Should) までを扱い、実際の waiver ポリシー変更 (期限付き
  例外運用の是非) は別途人間判断。
- **`verify-wiring.sh` / `verify-failure-class.sh` 等、既存 6 本の verify スクリプトのロジック変更** —
  参照 (task diff 算出) のみ行い、それ自体は変更しない。

## Risk

- level: high-risk
- must_count: 8
- boundary_touched: multi (event subscription + config + public export)
  - **event subscription**: 既に配線済みの `PreToolUse`/`PostToolUse`/`Stop` hook (`scripts/agent-time-budget.sh`
    / `scripts/agent-evidence-gate.sh`) の判定ロジックそのものを拡張する。
  - **config**: `.agent-evidence/.active` のスキーマに `spec_sha256=` 行を追加し、新規スキーマ
    `.agent-evidence/oracle-change-approval.json` を新設する (config/契約変更に相当)。
  - **public export相当**: `dot_claude/skills/agent-policy-kit/templates/scripts/**` + `kit-manifest.yml`
    は 5 消費 repo に配布される kit の公開契約であり、本 fix は将来の sync で全消費 repo に波及する。
- estimated_files: 13 (basis:
  - `Glob dot_claude/skills/agent-policy-kit/templates/scripts/*.sh` → 既存 14 テンプレート中 2 本
    (`executable_agent-time-budget.sh` / `executable_agent-evidence-gate.sh`) を編集 + 新規 1 本
    (`executable_verify-guard-integrity.sh`) を追加。
  - 対応する repo-local `scripts/agent-time-budget.sh` / `scripts/agent-evidence-gate.sh` (編集) +
    `scripts/verify-guard-integrity.sh` (新規) の 3 本 (`Read scripts/agent-time-budget.sh` /
    `scripts/agent-evidence-gate.sh` で現状確認済み)。
  - `dot_claude/skills/agent-policy-kit/kit-manifest.yml` (`Read` で現状 14 エントリ・
    `kit_version: "1.1.0"` を確認済み、再生成で 15 エントリ・新バージョンへ)。
  - `dot_claude/skills/proven-done/SKILL.md` (`Grep "Step 0|Step 1\.5|Step 4|Step 6\.5|Step 8"` で
    編集対象の各 Step 見出しの実在行を確認済み。amendment による `run-shell-tests.sh` の Step 4
    battery 行追加 (Must-6(e)) もこの同一ファイル内であり、新規ファイル追加ではない)。
  - `dot_claude/docs/agent-policy.md` (`Grep` で該当する証跡提出/Done 二段門記述行を確認済み)。
  - `dot_claude/skills/agent-policy-kit/SKILL.md` (**amendment で新規追加** — Should→Must 昇格
    (Must-7(f)) により Phase-2 Apply scaffold コピー対象一覧が必須編集対象になった。`Read
    dot_claude/skills/agent-policy-kit/SKILL.md` 31〜35 行目で現行 13 本列挙のコピー行を確認済み、
    `verify-guard-integrity.sh` を追加して 14 本にする)。
  - `tests/run-shell-tests.sh` (`Read` で既存 432 行のテスト構造・fixture 生成パターンを確認済み)。
  - `tests/fixtures/guard-evasion-gates/**` (新規 fixture ツリー — 既存
    `tests/fixtures/agent-evidence-gate/*` が 1 シナリオあたり 3〜7 ファイルである実績 (`Glob` で確認済み)
    から、spec-amend/stash-escape/active-tamper 各 2〜3 シナリオ + stash-baseline diff fixture +
    deny-vs-allow-band fixture + quarantine-waiver 除外 fixture 想定でまとまった 1 ディレクトリ群
    として 1 単位に計上)。
  合計 3+3+1+1+1+1+1+1 = 12、旧 `docs/specs/agent-time-budget-hook.md` への軽微な参照更新
  (Must-5(d) の回帰確認に伴う可能性、非破壊) を保守的に +1 して 13。)
- escalate_to_opus: true
- 理由:
  - 触れているのは**既に全 proven-done 実行を通過させている稼働中 hook** (`Stop`/`PreToolUse`/
    `PostToolUse`) であり、false-positive は以後の全タスクの完了主張を無条件でブロックする
    (harness infrastructure 特有の高コスト事故)。
  - kit テンプレートは 5 消費 repo に配布される公開契約であり、本 fix のバグは sync 経路で他 repo にも
    伝播する。
  - `must_count=8` は two-lane router の block 閾値 (`> 8`) 自体には未到達だが、`high-risk` かつ
    `boundary_touched=multi` の組が成立するため、`agent-policy.md` §2.5 の block レーン条件
    (`high-risk AND boundary_touched=multi`) に該当し得る。**2026-07-05 kickoff で recommendation B
    (single heavy-lane task + パケットループ) を採用し解消済み — 下記 `## Work packets` /
    `## Amendments` 参照。**
- 残存リスク (2026-07-05 kickoff amendment 時点で記録、本 spec の Must 外・対応は別タスク):
  - root `AGENTS.md` は `dot_claude/docs/agent-policy.md` から生成される。本 fix で正本
    (`agent-policy.md`) を編集しても kit apply/dogfood 再実行までは自動反映されない (impact-map
    Blast radius)。完了報告にこの drift を明記すること。
  - `.agent-evidence/oracle-change-approval.json` のフィールド名タイプミス (例: `spec_path` の誤字)
    は schema 検証機構が無いため静かに無視されるリスクがある (impact-map)。本 spec ではこれを
    Must-8 の fixture テスト (承認済み/未承認/フィールド欠落の各ケース) でのみ緩和し、JSON schema
    検証機構の追加そのものは Non-goal (別タスク)。

## Work packets

`.agent-evidence/block-lane-spec-review.json` (spec-grader DEEPEST recommendation B, 2026-07-05) を
採用し、**single heavy-lane task 内の Step-3 work-packets.json パケットループ**として次の 3 パケットで
実装する (Task A/B/C の repo 分割は不採用 — 各パケットが独立に high-risk かつ
`boundary_touched=multi` になり得るため block レーンを回避できず、human sign-off を 4x/2x に増やし、
producer-before-consumer 順序と `kit_version` 単一バンプの atomicity を壊すのみ)。

- **P12** = Must-1, Must-2, Must-3, Must-4 + Must-8 の spec-amend/stash-escape テスト群。
  スコープ: `scripts/verify-guard-integrity.sh` の spec-amend サブチェック + stash-escape サブチェック
  + stash-baseline 記録を実装し、対応する kit テンプレート (`executable_verify-guard-integrity.sh`)
  および scaffold リスト行 (Must-7(f)) を追加する。
  depends_on: []
- **P3** = Must-5 + Must-8 の active-tamper テスト群。
  スコープ: `scripts/agent-time-budget.sh` の tamper hardening (`$HOME/.claude/state/agent-time-budget/`
  への private コピー) と対応テンプレートを実装する。
  depends_on: []  (P12 と別ファイル境界のため並行実行可)
- **P4** = Must-6 (全 sub-item、新 (e)/(f) 含む) + Must-7 (全 sub-item、新 (f) 含む) + 最終フル回帰。
  スコープ: `scripts/agent-evidence-gate.sh` への wiring (spec-amend/stash-escape/active-tamper の
  3 検出全てをその場で直接実行)、Step 4/Step 8 の SKILL.md 更新 (`verify-guard-integrity.sh` +
  `run-shell-tests.sh` の両行)、kit-manifest bump + scaffold リスト更新、`agent-policy.md` 参照追記、
  `bash tests/run-shell-tests.sh` フル green run。
  depends_on: [P12, P3]

P12 と P3 の `done_when` は、`verify-guard-integrity.sh` が **P4 完了まで意図的に未配線** (どの
entrypoint からも呼ばれない状態) であることを各パケットの Non-goal として明示的に宣言しなければ
ならない (impact-map Warning 5)。これを宣言しないと、intra-packet の wiring チェック
(「未配線 = 失敗」という一般ルール) が誤って false-fail する。

## Open questions (あれば)

- **Q1 (block レーン該当時の分割要否)**: 上記 Risk の通り `high-risk AND boundary_touched=multi` が
  成立し得るため、Step 1.5 の two-lane router 判定で **block レーン**に該当する可能性がある。
  本 6-fix campaign の Fix-1 は既にユーザー承認済みスコープだが、実装を単一 heavy レーンの一括タスクと
  して進めるか (`agent-time-budget-hook.md` Q2 の前例では「ハーネス内部の単一配布境界」として一括実装を
  裁定)、あるいは `agent-policy-kit-sync` の Task A/B 分割の前例に倣い
  (Task A: spec-amend + stash-escape 検出スクリプト・テスト (Must-1/2/3/4/8 の該当部分、config 境界主体) /
  Task B: `.active` tamper hardening (Must-5、event subscription 境界主体) /
  Task C: wire-first + canonical kit sync + doc 更新 (Must-6/7、public export相当境界主体))
  に分割するかは、Step 1.5 で人間判断 (`AskUserQuestion`) が必要。

## Amendments (2026-07-05 kickoff 裁定 — AskUserQuestion 承認、spec-grader DEEPEST recommendation B 採用)

- **Q1 決定 (recommendation B 採用)**: `.agent-evidence/block-lane-spec-review.json`
  (spec-grader DEEPEST, verdict=CONCERNS, recommendation=B, 2026-07-05) を採用する。
  `high-risk AND boundary_touched=multi` の block レーン条件は Task A/B/C 分割では回避できない
  (各パケットが独立に high-risk かつ multi になり得る、human sign-off が 4x/2x に増える、
  producer-before-consumer 順序と `kit_version` 単一バンプの atomicity を壊す) ため、
  **single heavy-lane task + Step-3 の work-packets.json パケットループ (P12/P3/P4)** で実装する。
  詳細は上記 `## Work packets` を参照。
- **Must-3 falsifiable rewrite**: stash-baseline の記録主張を「doc-grep + 散文コメント」から、
  Step-0-simulation 実行時点の `git stash list` 出力と記録内容を diff/文字列比較する実行可能な
  fixture テストに置き換えた (受入条件 Must-3、Must-8 stash-escape (iv))。
- **Must-5(c) falsifiable rewrite**: 「private の値が判定を支配する」ことを re-stamp メッセージの
  grep だけでなく、deny-vs-allow-band fixture (private 側 `started_at` = deny 帯、`.active` 側
  (tamper 後) `started_at` = allow 帯) で **exit 2** を assert することにより、exit code レベルで
  証明する形に変更した (受入条件 Must-5(c)、Must-8 active-tamper (i))。
- **Must-7(b) falsifiable rewrite**: 「bump された」という主張を、(1) `kit_version` の値が
  amendment 時点の現行値 `"1.1.0"` と異なることの直接比較、(2) テンプレートエントリ数が 14→15 に
  なることの `-eq 15` assertion (`docs/specs/agent-time-budget-hook.md` Must-5 の `-eq 13` style を
  踏襲) の 2 点で機械的に確認する形に変更した。
- **Should→Must 昇格 (scaffold copy list)**: `agent-policy-kit/SKILL.md` の Phase-2 Apply scaffold
  コピー対象一覧 (SKILL.md:31-35) への `verify-guard-integrity.sh` 追加を Must-7(f) として昇格した
  (テンプレートを作成する packet (P4) と同一パケットで行う — 新規消費 repo での死蔵テンプレート化を
  防ぐ)。
- **Should→Must 昇格 (quarantine-waiver 除外)**: `is_gate_waived` の substring 部分一致が
  `verify-guard-integrity.sh` の POLICY VIOLATION を waive できないことを Must-6(f) として昇格した。
  これは evasion-detection 違反の機械的 anti-accident invariant のみを対象とし、既存 Non-goal の
  「`ci/quarantine.yml` への実際の waiver 登録・期限付き waiver 運用ポリシーの是非は別途人間判断」は
  変更しない。
- **Must-6(e) 追加 [user-approved scope add]**: `bash tests/run-shell-tests.sh` を
  `dot_claude/skills/proven-done/SKILL.md` Step 4 の決定論ゲート battery に追加し、Must-8 の
  guard 回帰スイートが毎 round 自動実行されるようにした。
- **Must-6(d) fixture 制約追加**: 「Stop hook が round-log スキャンではなく in-place 直接実行する」
  という主張の受入 fixture は、round-<N>/ の `verify-guard-integrity.log` が clean/absent な状態で
  なければならない (これにより exit 2 が古いログ由来ではなく直接実行由来であることが機械的に
  区別できる)。
- **Packet plan の記録**: 承認済み 3-packet 分解 (P12/P3/P4、`depends_on`、transient-unwired window の
  宣言要件) を `## Work packets` として記録した。
- **estimated_files 再計上**: Must-7(f) の Should→Must 昇格により `dot_claude/skills/agent-policy-kit/SKILL.md`
  が新規に必須編集対象となったため、estimated_files を 12 → 13 に更新した (basis は上記 `## Risk`
  参照)。Step 4 battery 行追加 (Must-6(e)) と kit-manifest bump (Must-7(b)) は既存カウント対象ファイル
  内の変更のため、追加カウントは発生していない。
- **残存リスクの記録**: root `AGENTS.md` の生成遅延ドリフト、および
  `.agent-evidence/oracle-change-approval.json` のフィールドタイプミス緩和策 (Must-8 fixture のみ) を
  `## Risk` に追記した (いずれも本 spec の Must 外、別タスク/別リスクとして記録のみ)。
