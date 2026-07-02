# Spec: agent-time-budget-hook

<!-- spec-curator が /grill-me 合意 (2026-07-02) から正規化。 -->

## Goal
- proven-done の Time budget (light=30min / heavy=90min) を **散文の不変条件から hook による決定論的執行**
  に変換する。2026-06-29 に implementer が 4 時間ループし、orchestrator が subagent の turn 中に介在できず
  ユーザーの TaskStop でしか止められなかった実績を踏まえ、**PreToolUse hook** で経過時間を tool call ごとに
  検査し、閾値超過時は tool call 自体を deny してループを強制停止させる。
- 新規 `agent-time-budget.sh` は既存 `agent-policy-hook.sh` (PostToolUse, ファイル単位の no-prod-doubles/
  test-bypass 検査) とは独立した別スクリプトとし、既存ロジックは変更しない。
- `.agent-evidence/` 配下への Write/Edit は deny 帯でも常に allow する例外を設け、deny された agent が
  `time-budget-exceeded.md` を書いて Step 10 (後始末) に進める退避路を確保する。
- この repo 自身 (`dotfiles`) は kit の配布元かつ消費 repo 第 0 号であり、現状 `.claude/settings.json` が
  存在せず 3 hook (新規 PreToolUse + 既存 PostToolUse/Stop 相当) いずれも未配線 — 本タスクでこの穴を塞ぐ
  (dogfood 配線)。

## Must (満たさなければ done でない)

- [ ] **Must-1 (agent-time-budget.sh 新設)**:
      `dot_claude/skills/agent-policy-kit/templates/scripts/executable_agent-time-budget.sh`
      (KIT テンプレート、shebang 直後に `# KIT_VERSION: 1.1.0` 行) と、その配布物である vendored copy
      `scripts/agent-time-budget.sh` (executable、内容・KIT_VERSION 行ともテンプレートと同一) が存在し、
      **PreToolUse hook** として次を満たす:
      (a) stdin から hook JSON を読む。既定の証跡ディレクトリは `.agent-evidence` だが、
          `--evidence-dir <dir>` で上書きできる (`verify-evidence-freshness.sh --evidence-dir` と同じ
          慣例。テスト容易性のために必須)。
      (b) **例外判定を最優先で行う**: `tool_name` が `Write` または `Edit` で、`tool_input.file_path` を
          repository root からの相対パスに正規化した結果が `.agent-evidence/` 配下なら、他の条件を評価せず
          exit 0 (allow) で終了する (deny 帯でも常に allow — `time-budget-exceeded.md` を書いて Step 10
          へ退避できるようにするため)。
      (c) 例外に該当せず `<evidence-dir>/.active` が存在しなければ exit 0 (allow)。
      (d) `.active` が存在すれば `started_at` (ISO8601 UTC) と `lane` (`light`|`heavy`。欠落または
          未知値なら `heavy` として扱う) を読み、`now` との経過分を budget (`light`=30分 / `heavy`=90分)
          で割った経過率 `ratio` を計算する:
          - `ratio < 0.75`: exit 0 (allow)、警告なし。
          - `0.75 ≤ ratio < 1.0`: exit 0 (allow) だが、**非ブロックで呼び出し元 agent に届く経路**
            (Claude Code の PreToolUse hook 出力仕様に沿った JSON 出力、またはそれと同等に agent context
            に到達することが公式ドキュメントで確認できる経路 — exit 0 時に agent へ届かないだけの
            plain stderr は不可) で、`lane` 名・経過分・budget 分 (または経過率 %) を含む警告文を出す。
          - `ratio ≥ 1.0`: **exit 2 (deny)**。stderr に `.agent-evidence/time-budget-exceeded.md` を
            書いて Step 10 へ進む旨の案内文を含める。
      実装時の警告到達経路の具体的スキーマ確認は実装者が公式ドキュメント (Context7 等) で行い、
      使用した経路を `commands.txt` に記録する (下記 Open questions Q3)。

- [ ] **Must-2 (`.active` の正規スキーマ化)**: `dot_claude/skills/proven-done/SKILL.md` の Step 0 に、
      `.agent-evidence/.active` が `task=<task>` / `started_at=<ISO8601 UTC>` / `lane=<light|heavy>`
      の 3 行を必須とする旨が明文化され、`agent-time-budget.sh` がこれを parse する前提であることが
      分かる記述になっている (`lane=` がいつ書き込まれるかの具体的な Step 位置は Open questions Q1
      を参照。本 Must は **スキーマの明文化**のみを対象とし、Step 順序の変更有無は問わない)。

- [ ] **Must-3 (dotfiles repo 自身の `.claude/settings.json` 新設)**: リポジトリ root に
      `.claude/settings.json` が存在し (現状皆無)、有効な JSON であり、以下 3 hook を持つ:
      (a) `PreToolUse`: matcher が `Write`/`Edit`/`Bash` の全てにマッチし、`hooks[].command` が
          `agent-time-budget.sh` を指す。
      (b) `PostToolUse`: matcher が `Write`/`Edit` にマッチし、`hooks[].command` が
          `agent-policy-hook.sh` を指す (**既存スクリプトのロジックは変更しない** — 単に配線するのみ)。
      (c) `Stop`: `hooks[].command` が `agent-evidence-gate.sh` を指す (既存スクリプト、ロジック変更なし)。
      これにより、この repo で従来未配線だった PostToolUse/Stop hook 2 本も同時に配線される。

- [ ] **Must-4 (kit への settings スニペット template 同梱 + SKILL.md 更新)**:
      `dot_claude/skills/agent-policy-kit/templates/settings-hooks.snippet.json` が存在し、有効な JSON で
      `PreToolUse`(agent-time-budget.sh) / `PostToolUse`(agent-policy-hook.sh) / `Stop`
      (agent-evidence-gate.sh) の 3 hook 登録例を全て含む (消費 repo が自身の `.claude/settings.json` に
      マージする際の参照ひな形)。`dot_claude/skills/agent-policy-kit/SKILL.md` が
      (i) `scripts/` へコピーするスクリプト一覧に `agent-time-budget.sh` を追加し、
      (ii) `settings-hooks.snippet.json` の存在と用途 (3 hook 登録例) に言及する形に更新されている。

- [ ] **Must-5 (kit-manifest 再生成)**: `bash scripts/kit-manifest-update.sh` 実行後、
      `dot_claude/skills/agent-policy-kit/kit-manifest.yml` の `kit_version` が `"1.1.0"` のまま
      (bump しない)、かつ `files:` に `agent-time-budget.sh` エントリ (sha256 付き) が追加され、
      エントリ総数が既存 12 本から **13 本** になる。この repo 自身 `scripts/agent-time-budget.sh` も
      manifest と一致する (`kit-sync-check.sh --check`/`--self` が両方 exit 0)。

- [ ] **Must-6 (TDD: agent-time-budget.sh のケース追加)**: `tests/run-shell-tests.sh` に、
      `started_at` を細工した fixture `.active` + hook JSON stdin を用いた決定論テストとして
      以下 6 ケースが追加され、`bash tests/run-shell-tests.sh` が fail 0 で終了する:
      (a) `.active` 無し → exit 0。
      (b) `lane=heavy`、経過 50% (45分/90分) → exit 0、警告なし。
      (c) `lane=heavy`、経過 82% (73.8分/90分、warn 帯) → exit 0 だが出力に警告 (lane 名・経過率相当の
          手掛かり) を含む。
      (d) `lane=heavy`、経過 110% (99分/90分) → exit 2。stderr に `time-budget-exceeded.md` を含む。
      (e) (d) と同じ fixture で `tool_name=Write` かつ `tool_input.file_path` が `.agent-evidence/` 配下
          → exit 0 (例外が deny に優先)。
      (f) `lane` 行が欠落した `.active` で経過分を `heavy` (90分) 基準に換算した場合に band 判定が
          heavy 扱いになる (例: light 基準なら deny 帯だが heavy 基準では warn 帯になる経過分を用いて
          heavy 扱いであることを確認する)。

## Should (望ましいが必須でない)

- 警告メッセージ・deny メッセージの文言に `lane` の残り分数 (budget 分 − 経過分) を含め、
  agent が「あと何分で deny されるか」を自己判断しやすくする。
- `agent-time-budget.sh` の deny メッセージに、直近の `.agent-evidence/iterations.json` の
  `failure_class` 分布 (存在すれば) を併記し、単純な time budget 超過なのか collapsed loop 由来かを
  agent が区別できるヒントを与える (無ければ省略して良い)。
- Must-3 の `.claude/settings.json` の hook コマンドは `$CLAUDE_PROJECT_DIR` 相対で記述し、
  worktree/clone 位置に依存しないようにする。

## 受入条件 (acceptance — Must の確認方法)

- Must-1 →
  ```
  test -x scripts/agent-time-budget.sh
  grep -q '^# KIT_VERSION: ' dot_claude/skills/agent-policy-kit/templates/scripts/executable_agent-time-budget.sh

  # (b) .agent-evidence/ 配下 Write は無条件 allow (deny 帯の fixture でも)
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/.agent-evidence/time-budget-exceeded.md"}}' \
    | bash scripts/agent-time-budget.sh --evidence-dir <lane=heavy, 経過110% の fixture dir>
  test $? -eq 0

  # (c) .active 無し → allow
  echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
    | bash scripts/agent-time-budget.sh --evidence-dir <.active が無い空 dir>
  test $? -eq 0

  # (d) ratio<0.75 → allow / 0.75<=ratio<1.0 → allow+警告 / ratio>=1.0 → deny(exit 2)
  # (下記 fixture はそれぞれ lane=heavy, started_at をテスト実行時刻から 45分前 / 73.8分前 / 99分前
  #  に設定して動的生成する)
  echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' | bash scripts/agent-time-budget.sh --evidence-dir <50%fixture>; test $? -eq 0
  out="$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' | bash scripts/agent-time-budget.sh --evidence-dir <82%fixture>)"; test $? -eq 0
  printf '%s' "$out" | grep -Eiq 'heavy|警告|warn'
  err="$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' | bash scripts/agent-time-budget.sh --evidence-dir <110%fixture> 2>&1 1>/dev/null)"
  test $? -eq 2
  printf '%s' "$err" | grep -q "time-budget-exceeded.md"
  printf '%s' "$err" | grep -q "Step 10"
  ```
  全コマンド期待通りの exit code / grep 一致。

- Must-2 →
  ```
  grep -A3 "task=" dot_claude/skills/proven-done/SKILL.md | grep -q "started_at="
  grep -A5 "task=" dot_claude/skills/proven-done/SKILL.md | grep -q "lane="
  grep -A5 "lane=" dot_claude/skills/proven-done/SKILL.md | grep -Eq "light.*heavy|heavy.*light"
  grep -B2 -A2 "started_at=" dot_claude/skills/proven-done/SKILL.md | grep -qi "ISO8601"
  ```
  全 exit 0 (一致行あり)。

- Must-3 →
  ```
  test -f .claude/settings.json
  jq empty .claude/settings.json
  jq -r '.hooks.PreToolUse[0].matcher' .claude/settings.json | grep -q "Write"
  jq -r '.hooks.PreToolUse[0].matcher' .claude/settings.json | grep -q "Edit"
  jq -r '.hooks.PreToolUse[0].matcher' .claude/settings.json | grep -q "Bash"
  jq -r '.hooks.PreToolUse[0].hooks[0].command' .claude/settings.json | grep -q "agent-time-budget.sh"
  jq -r '.hooks.PostToolUse[0].matcher' .claude/settings.json | grep -q "Write"
  jq -r '.hooks.PostToolUse[0].matcher' .claude/settings.json | grep -q "Edit"
  jq -r '.hooks.PostToolUse[0].hooks[0].command' .claude/settings.json | grep -q "agent-policy-hook.sh"
  jq -r '.hooks.Stop[0].hooks[0].command' .claude/settings.json | grep -q "agent-evidence-gate.sh"
  diff <(git show HEAD:scripts/agent-policy-hook.sh 2>/dev/null || cat scripts/agent-policy-hook.sh) scripts/agent-policy-hook.sh  # ロジック無変更の確認 (実運用は git diff で確認)
  ```
  全コマンド exit 0 (最後の diff は「変更なし」を意味する空 diff)。

- Must-4 →
  ```
  test -f dot_claude/skills/agent-policy-kit/templates/settings-hooks.snippet.json
  jq empty dot_claude/skills/agent-policy-kit/templates/settings-hooks.snippet.json
  jq -e '.hooks.PreToolUse and .hooks.PostToolUse and .hooks.Stop' dot_claude/skills/agent-policy-kit/templates/settings-hooks.snippet.json
  grep -q "agent-time-budget.sh" dot_claude/skills/agent-policy-kit/templates/settings-hooks.snippet.json
  grep -q "agent-policy-hook.sh" dot_claude/skills/agent-policy-kit/templates/settings-hooks.snippet.json
  grep -q "agent-evidence-gate.sh" dot_claude/skills/agent-policy-kit/templates/settings-hooks.snippet.json
  grep -q "agent-time-budget.sh" dot_claude/skills/agent-policy-kit/SKILL.md
  grep -q "settings-hooks.snippet.json" dot_claude/skills/agent-policy-kit/SKILL.md
  ```
  全 exit 0。

- Must-5 →
  ```
  bash scripts/kit-manifest-update.sh
  grep -q 'kit_version: "1.1.0"' dot_claude/skills/agent-policy-kit/kit-manifest.yml
  grep -q '^  agent-time-budget.sh:' dot_claude/skills/agent-policy-kit/kit-manifest.yml
  test "$(grep -c '^  [a-zA-Z0-9_.-]*\.sh:' dot_claude/skills/agent-policy-kit/kit-manifest.yml)" -eq 13
  bash scripts/kit-sync-check.sh --self --manifest dot_claude/skills/agent-policy-kit/kit-manifest.yml
  bash scripts/kit-sync-check.sh --check --manifest dot_claude/skills/agent-policy-kit/kit-manifest.yml
  ```
  全コマンド exit 0。

- Must-6 →
  ```
  test "$(grep -c "agent-time-budget" tests/run-shell-tests.sh)" -ge 6
  bash tests/run-shell-tests.sh; echo $?
  ```
  カウントが 6 以上、かつ最後の exit code が 0。

## Non-goals (今回やらない)

- **no-new-evidence 検知の新規導入** (20分連続で新証拠なしの検出は本 spec のスコープ外。
  既存の time-budget 不変条件のうち wall-clock 部分のみを扱う)。
- **既存 `agent-policy-hook.sh` (PostToolUse) のロジック変更**。配線 (settings.json 登録) のみ行う。
- **PostToolUse 側での時間検査の追加**。時間検査は PreToolUse (`agent-time-budget.sh`) に一本化する。
- **消費 repo (alpha-mind / am-wt-auditlog / native-trace / recall-paper / cloudflare-workers-hs) への
  `.claude/settings.json` 自動書込・PreToolUse hook の rollout**。本 spec はスニペット template の
  提供 (Must-4) までを対象とし、各消費 repo への実配備・マージは別タスク。
- **Two-lane router の判定式自体 (`agent-policy.md` §2.5) の変更**。
- **`verify-failure-class.sh` / collapsed loop・oracle-change branch (Step 6.5) のロジック変更**。
- **`agent-evidence-gate.sh` (Stop hook) のロジック変更**。配線 (settings.json 登録) のみ行う。

## Risk

- level: high-risk
- escalate_to_opus: true
- 理由:
  - **config**: `.claude/settings.json` の hook 配線設定そのものを新設・変更する。deny 判定のバグ
    (fail-closed の誤爆) は通常の開発作業を恒常的にブロックしうる。
  - **event subscription**: `PreToolUse`/`PostToolUse`/`Stop` という Claude Code のライフサイクル
    イベント購読を新規登録・拡張する。band 境界の計算ミスは「本来 deny すべきループを止め損なう」
    (2026-06-29 の 4 時間ループ再発) と「正当な作業を誤って deny する」の両方の事故モードを持つ。
  - **public export相当**: `dot_claude/skills/agent-policy-kit/templates/**` (新規スクリプト +
    settings スニペット + kit-manifest.yml 更新) は 5 消費 repo に配布される kit の公開契約であり、
    将来の sync で全消費 repo に波及する。
  - **two-lane router 上の block 懸念**: 本 spec は `config` / `event subscription` /
    `public export相当` の 3 boundary に触れており、`agent-policy.md` §2.5 の `boundary_touched=multi`
    (2 つ以上の boundary を跨ぐ) に該当し得る。`high-risk AND boundary_touched=multi` は two-lane
    router の block 条件を満たすため、素朴には implementer を起動せず topology-mapper → spec-grader
    DEEPEST での分割提案 → `AskUserQuestion` によるキックオフが必要になる可能性がある
    (`agent-policy-kit-sync` / `verifier-tree-stamp` の先例と同型。下記 Open questions Q2)。

## Open questions (あれば)

- **Q1 (`.active` の `lane=` 書込タイミング)**: 現行 `proven-done/SKILL.md` の Step 0 (marker 作成) は
  Step 1 (spec curation) より前に実行され、Step 1.5 (Two-lane router によるレーン判定) は Step 1 の
  spec 出力 (`must_count`/`estimated_files`/`risk.level`) に依存する。よって **Step 0 の時点では
  構造的に `lane` を確定できない**。案 (A) `.active` 作成自体を Step 1.5 完了後まで遅延させ、
  Step 1 (spec curation) 自体は time budget 対象外にする。案 (B) Step 0 では `task=`/`started_at=`
  のみ書き (この間 `agent-time-budget.sh` は `lane` 欠落 → `heavy` 扱いの安全側デフォルトで動作)、
  Step 1.5 で `lane=` 行を追記する。実装前に人間判断が必要 (Must-2 は案 A/B いずれでも成立するよう
  「スキーマの明文化」のみを要求している)。
  参考: 本タスク自身の `.agent-evidence/.active` は現に `task=`/`started_at=`/`lane=heavy`/
  `risk=high-risk` の **4 行**で運用されており (spec 未確定の時点で `lane` を先行して仮決定している)、
  `risk=` を正規スキーマの 4 行目に含めるかどうかも合わせて確認が必要 (合意本文は 3 行のみを必須と
  述べている)。
- **Q2 (two-lane router の block 判定をどう扱うか)**: 上記 Risk 節の通り、本 spec は `high-risk` かつ
  `boundary_touched=multi` (config / event subscription / public export相当) に該当し得るため block
  レーン条件に抵触する可能性がある。本 spec の 6 Must を単一タスクとして block レーン判定を経由
  (topology-mapper → spec-grader DEEPEST → AskUserQuestion) した上で一括実装するか、先例
  (`agent-policy-kit-sync` の Task A/B 分割) に倣い Task A (`agent-time-budget.sh` 本体 + `.active`
  スキーマ + TDD、Must-1/2/6 — config 境界主体) / Task B (dotfiles 自身の hook 配線 + kit
  テンプレ/snippet/SKILL.md 更新 + kit-manifest 再生成、Must-3/4/5 — event subscription +
  public export相当境界) に分割するかは人間判断が必要。
- **Q3 (warn 帯の agent 到達機構)**: 75%〜100% 帯の警告を「非ブロックで agent に届く」形で実装する
  具体的な Claude Code PreToolUse hook 出力機構 (JSON `hookSpecificOutput` 相当のどのフィールドが
  allow 判定時にも agent context に到達することを公式ドキュメント上保証するか) は、spec-curator では
  断定できず実装時点の公式ドキュメント確認 (Context7 等) に委ねる。該当機構が存在しない、または
  ドキュメント不十分と判明した場合、(i) 75%〜100% 帯を「常に allow・agent 到達の保証なし」に留めるか、
  (ii) より保守的な閾値 (例: 90%) で先に deny してしまうか、方針転換が必要になり得る。実装者は
  この事実を発見した場合、Must-1(d) の warn 帯要件について推測で実装を進めず、`oracle_change_request`
  相当でエスカレーションすること。

## Amendments (2026-07-02 orchestrator 裁定 — grill-me 委任範囲)

- **Q1 決定 (案 B)**: Step 0 は `task=` / `started_at=` の 2 行で .active を作成し、Step 1.5 のレーン確定時に `lane=` を追記する。`lane=` 欠落時の hook は heavy (90min) デフォルト。`risk=` 等の追加行は任意 (hook は無視)。
- **Q2 決定**: heavy レーンで一括実装 (ハーネス内部の単一配布境界。人間キックオフは grill-me で取得済み — P1 と同一裁定)。
- **Q3 決定**: agent-time-budget.sh を **PreToolUse と PostToolUse の両方に登録**し、stdin JSON の `hook_event_name` で分岐する。Pre 側: ≥100% で deny (exit 2 = 呼び出しブロック)、.agent-evidence/ 配下への Write/Edit は常に allow。Post 側: 75〜100% で exit 2 (= 実行後の非ブロック警告が model に届く公式意味論)、それ以外 exit 0。settings.json / snippet は両イベントに同スクリプトを登録する。
- **Amendment 追記 (static-review CONCERNS 対応)**: 本文の受入コマンド JSON に `hook_event_name` を明示するよう補正 (Q3 二重登録により同 field が分岐キーになったため)。`hook_event_name` 欠落/未知の入力は **fail-safe allow (exit 0) + stderr 診断行** を正規挙動とし、テストで明示する (fail-closed にすると field 名変更でセッションが brick するため)。
