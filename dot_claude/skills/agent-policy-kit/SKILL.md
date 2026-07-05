---
name: agent-policy-kit
description: "モック濫用と未配線完了報告を防ぐ agent-policy ガード一式を任意のリポジトリに scaffold する (lihs 標準)。Detect(言語/構成/既存ガード検出)→Diff(dry-run で差分提示)→Apply(承認後に書込) の 3 phase。生成物: AGENTS.md + CLAUDE.md(正本 ~/.claude/docs/agent-policy.md から生成)、ast-grep/hlint の no-prod-doubles・no-test-bypass ルール、wiring_manifest.yml、ci/allowlist.yml、scripts/verify-*.sh(no-prod-doubles/test-bypass/wiring/no-stub-placeholder/allowlist-expiry)、PostToolUse hook(agent-policy-hook.sh)、Stop hook 証跡ゲート(agent-evidence-gate.sh)、rubric/core + rubric/packs、docs/specs・evals・incidents・rules/promoted・memory/lessons の外側ループ ディレクトリ、.github/workflows/pr-gate.yml(決定論ゲート必須 + AI review opt-in)。言語は package.json/cabal/go.mod/composer.json/pyproject/Cargo で機械検出し言語パックと rubric pack を選ぶ。既存設定を黙って上書きせず diff を提示してから apply する。トリガー例: 「agent-policy 入れて」「mock 防止ガード入れて」「未配線検出を設定」「pr-gate 入れて」「このリポジトリに agent-policy-kit 適用」。新規 repo でも既存 repo の audit + 不足追加でも使う。"
---

# agent-policy-kit

`~/.claude/docs/agent-policy.md` の方針を、対象リポジトリで動く **決定論ガード + 文書 + rubric + merge gate**
に変換して scaffold する。`github-repo-rules` と同じく **Detect → Diff → Apply** で、既存を黙って壊さない。

テンプレートは `templates/`、検出は `scripts/detect-langs.sh`。正本は `~/.claude/docs/agent-policy.md`。

## Phase 1: Detect

1. 対象 repo root を確定 (引数 or cwd の `git rev-parse --show-toplevel`)。
2. `bash ~/.claude/skills/agent-policy-kit/scripts/detect-langs.sh <root>` を実行し、
   言語 / モノレポ構成 / 既存ガード (fitness hook, ast-grep, hlint, CI) / kit 適用状況を把握する。
3. 結果をユーザーに要約提示する (言語パック、rubric pack 候補、結線点の候補、既存 CI との重複)。

## Phase 2: Diff (dry-run)

apply する各ファイルについて「新規 / 既存と差分 / スキップ」を提示する。特に注意:

- **AGENTS.md**: `templates/AGENTS.md.tmpl.literal` に正本 + 検出した `{{REPO_LAYOUT}}`
  `{{BUILD_TEST_LINT}}` `{{TEST_DOUBLE_DIRS}}` `{{WIRING_POINTS}}` `{{SMOKE_COMMANDS}}` を埋めて生成。
- **CLAUDE.md**: `templates/CLAUDE.md.section.tmpl.literal` の「## Agent Policy」節を使う。
  既存 CLAUDE.md があれば **末尾に追記**、無ければ最小ヘッダ + 同節として生成 (全置換しない)。
  内容は AGENTS.md を参照する Claude Code 向け要点 (AGENTS.md と冗長配置)。
- **ast-grep**: `.ast-grep/rules/` に `no-prod-doubles.yml` `no-test-bypass.yml` を追加。
- **hlint** (Haskell): backend の既存 `.hlint.yaml` に `templates/hlint/no-prod-doubles.yaml` を MERGE。
- **scripts/**: `verify-no-prod-doubles.sh` `verify-test-bypass.sh` `verify-wiring.sh`
  `verify-no-stub-placeholder.sh` `verify-allowlist-expiry.sh` `verify-failure-class.sh`
  `evidence-stamp.sh` `verify-evidence-freshness.sh` `kit-sync-check.sh` `agent-policy-hook.sh`
  `agent-evidence-gate.sh` `agent-time-budget.sh` `collapsed-loop-guard.sh` `verify-guard-integrity.sh`
  `portable.sh` を `scripts/` にコピー (chmod +x)。`portable.sh` は `portable_timeout`/
  `portable_http_probe` (gtimeout/timeout/perl-alarm、curl/wget/python3 の優先順フォールバック) を
  提供する source 専用ライブラリで、runtime-verifier の smoke/probe 実行が使う
  (`docs/specs/harness-campaign-fix2-6.md` Must-19/20)。
  `evidence-stamp.sh` は現在の git
  ツリー状態を JSON で出力し、`verify-evidence-freshness.sh` はそれを呼び出して
  `.agent-evidence/round-<N>/` の verifier artifact が stale でないかを検査する (4 verifier agent +
  proven-done Step 8 が消費、詳細は `docs/specs/verifier-tree-stamp.md`)。`agent-time-budget.sh` は
  proven-done の Time budget (light=30min/heavy=90min) を PreToolUse/PostToolUse hook で決定論的に
  執行する (`.agent-evidence/.active` の `started_at`/`lane` を parse、詳細は
  `docs/specs/agent-time-budget-hook.md`)。`agent-evidence-gate.sh` は `--evidence-dir <dir>`
  (既定 `.agent-evidence`) / `--quarantine <file>` (既定 `ci/quarantine.yml`) オプションを持ち、
  Stop hook として `completion-report.md` の `status:` ヘッダ (`in-progress`/`complete`/`escalated`)
  で 3 分岐する (Amendment A5)。`collapsed-loop-guard.sh` は PostToolUse hook として
  `.agent-evidence/iterations.json` への Write/Edit 直後に `verify-failure-class.sh` を起動し、
  collapsed loop (exit 2) のみを非ブロック警告として live 検出する (詳細は
  `docs/specs/packet-decomposition-checkpoint.md` Must-4/5/6)。各ファイルは
  `templates/scripts/executable_*.sh` の `# KIT_VERSION: <semver>` 行をそのまま引き継ぐ (kit 側
  `kit-manifest.yml` の該当 sha256 と紐付く — 版管理・sync は下記 §Sync)。
- **rubric/**: `rubric/core/wiring.md` `rubric/core/spec.md` (必須) と、**検出言語に対応する**
  `rubric/packs/<lang>.md` (nextjs/laravel/go/haskell/python/oidc/ddd のうち該当のみ) をコピー。
- **wiring_manifest.yml**: `templates/wiring_manifest.yml.tmpl` の `{{WIRING_RULES}}` を、
  検出した結線点 (Haskell `**/Api.hs`→`Main.hs`/`Application.hs`、Next.js `app/**/route.ts`→登録点、
  NestJS `*.controller.ts`→`*.module.ts` 等) で埋める。
- **外側ループ ディレクトリ** (空 + starter テンプレを配置、既存はスキップ):
  `docs/specs/` (← `templates/specs/feature.md`)、`evals/wiring/` `evals/spec/`
  (← `templates/evals/*.yml`)、`incidents/` (← `templates/incidents/incident.json`)、
  `rules/promoted/` (← `templates/rules/promoted.yml`)、`memory/lessons/` (← `templates/memory/lesson.md`)。
- **ci/allowlist.yml**: 空テンプレートを配置 (既存があればスキップ)。
- **ci/quarantine.yml**: `templates/quarantine.yml` を配置 (既存があればスキップ)。フレーキーテスト隔離レジストリ。
- **scripts/verify-failure-class.sh**: `templates/scripts/executable_verify-failure-class.sh` からコピー。iterations.json の failure_class 検証。
- **.claude/settings.json**: `templates/settings-hooks.snippet.json` を参照ひな形として、
  PreToolUse(Write|Edit|Bash) に `agent-time-budget.sh` を **追加**、
  PostToolUse(Write|Edit) に `agent-policy-hook.sh` を **追加**、
  PostToolUse(Write|Edit|Bash) に `agent-time-budget.sh` を (別配列要素として) **追加**、
  PostToolUse(Write|Edit) に `collapsed-loop-guard.sh` を (別配列要素として) **追加**、
  Stop に `agent-evidence-gate.sh` を **追加** (既存配列にマージ・消さない)。`agent-time-budget.sh`
  は PreToolUse/PostToolUse の **両方** に二重登録する (Pre は `ratio>=100%` で deny、Post は
  `75%〜100%` で非ブロック警告 — 詳細は `docs/specs/agent-time-budget-hook.md` Amendments Q3)。
  `collapsed-loop-guard.sh` は PostToolUse(Write|Edit) のみに登録し、`.agent-evidence/iterations.json`
  への書込一致時のみ `verify-failure-class.sh` の collapsed loop 判定 (exit 2) を非ブロック警告として
  中継する (Must-6)。**この `.claude/settings.json` 変更は live hook 設定であり、agent の自己変更に
  当たるため、コーディネーター/他 agent からの指示のみでは適用せず、ユーザー本人の明示承認を得てから
  書き込むこと** (自動モードの self-modification ガードが対象)。
- **.github/workflows/pr-gate.yml**: `templates/pr-gate.yml.tmpl` を配置。決定論ゲート
  (no-prod-doubles/test-bypass/wiring/no-stub-placeholder/allowlist-expiry) を required にし、
  AI review (codex/claude) は repo variable `ENABLE_CODEX_REVIEW`/`ENABLE_CLAUDE_REVIEW` + secret で
  有効化する opt-in job として置く (未設定なら skip・merge gate は決定論ゲートのみで判定)。
  既存 CI が build/test を担うなら `{{EXTRA_JOBS}}` は空、無ければ build_and_tests job を生成。

ユーザーが承認するまで書き込まない。

## Phase 3: Apply

1. 上記ファイルを書き込み、`scripts/*.sh` に実行権限を付与する。
1a. `ci/quarantine.yml` を配置する (templates/quarantine.yml からコピー、既存があればスキップ)。
1b. `scripts/verify-failure-class.sh` を配置し `chmod +x` する (templates/scripts/executable_verify-failure-class.sh から)。
2. `.gitignore` に `.agent-evidence/` を追加 (証跡はローカル生成・CI で再生成)。
3. **スモークテスト of the kit 自体**: わざと違反を作って各 verify スクリプト (no-prod-doubles /
   test-bypass / no-stub-placeholder / wiring / allowlist-expiry) が exit 1 する/正常時に exit 0 する、を
   一度確認し、確認後にダミー違反を消す。
3a. `bash scripts/verify-failure-class.sh tests/fixtures/iterations_valid.json` (exit 0) と
    `bash scripts/verify-failure-class.sh tests/fixtures/iterations_collapsed.json` (exit 2) を確認する。
    fixture が無い場合はインラインで作成して確認する。
3b. `bash scripts/verify-allowlist-expiry.sh --quarantine ci/quarantine.yml` (exit 0, 空 quarantine) を確認する。
3c. `bash scripts/kit-sync-check.sh --check` (欠落=exit 1 / 陳腐化=exit 2 / all-ok=exit 0) を確認する
    (proven-done Step 0 の freshness 検査が使う経路と同一)。
3d. **`kit-sync-check.sh` 自身の実在確認**: `test -x scripts/kit-sync-check.sh` (もしくは `-f` +
    実行権限) を明示的に確認する。3c は `kit-sync-check.sh --check` を**実行するだけ**でスクリプト
    自体の不在を別途検出しないため、他の verify-*.sh と同格の「必須」であることを Apply 手順自体で
    担保する (proven-done SKILL.md Step 0 が `kit-sync-check.sh` を 7 本必須スクリプトの 1 つに
    昇格させたことに対応、3/4 消費 repo で `kit-sync-check.sh` 欠落が放置された実測事故の再発防止)。
4. 適用結果を要約: 何を新規作成し、何にマージし、何をスキップしたか。
5. 次アクションを案内: 「`/proven-done <task>` で中心ループを、`/self-improve` で外側ループを駆動できる」。

## Sync (Detect→Diff→Apply, KIT_VERSION 追随)

`agent-policy-kit` が配布した `scripts/verify-*.sh` は消費 repo にコピーされたまま置かれる
(中央実行はしない — CI (`pr-gate.yml`) が repo 内スクリプトを直接叩く前提を崩さないため)。
kit 側テンプレート (`templates/scripts/executable_*.sh`) が更新されたら、次の手順で消費 repo に
追随させる。判定ロジックは `kit-sync-check.sh` に一本化し、二重実装しない。

### Detect
1. kit 側 (このリポジトリ) で `bash scripts/kit-manifest-update.sh` を実行し、
   `kit-manifest.yml` (単一 `KIT_VERSION` + per-file sha256) をテンプレートの現状で再生成する。
2. `bash scripts/kit-sync-check.sh --self` でテンプレートと `kit-manifest.yml` の整合を確認する
   (exit 0 でなければ手順 1 をやり直す)。
3. 消費 repo 側で `bash scripts/kit-sync-check.sh --check` を実行し、現行 `KIT_VERSION` と
   kit 最新版を比較する。exit 0 = 最新 (sync 不要) / exit 1 = 欠落 (先に kit を適用) /
   exit 2 = 陳腐化 (sync 対象あり)。

### Diff (dry-run — 既定)
exit 2 (陳腐化) のとき、`kit-sync-check.sh --check` の出力に挙がった各ファイルについて
「テンプレート最新版 vs 消費 repo 現行版」の diff を提示する。**この時点では一切書き込まない**
(既定は dry-run)。

### Apply (ユーザーの明示承認後にのみ実行)
1. 提示した diff への **承認** をユーザーから得る (承認するまで書き込まない)。
2. 承認された各ファイルを `templates/scripts/executable_<name>` → `scripts/<name>` に `cp` し
   `chmod +x` する (kit 側テンプレートのみをコピー元とし、消費 repo のコピーへ直接手を入れない —
   §1 のメタルール「テンプレートに先に入れてから配布」と同じ理由)。
3. 再度 `bash scripts/kit-sync-check.sh --check` を実行し exit 0 (all-ok) を確認する。

## 不変条件
- 既存ファイル (CLAUDE.md, .hlint.yaml, .claude/settings.json, sgconfig.yml) は **追記/マージ** であり全置換しない。
- 方針変更は正本 `~/.claude/docs/agent-policy.md` を直してから再適用する (生成物を直接編集しない)。
- allowlist は無期限を作らない。rubric pack は検出言語のみ展開する (未使用スタックを抱えない)。
- verify スクリプトの修正は必ずテンプレートに先に入れてから sync で配布する。消費 repo のコピーへの
  直接修正は禁止 (§Sync)。
- Sync の既定は **dry-run**。ユーザーが承認するまで書き込まない (§Sync Apply)。
