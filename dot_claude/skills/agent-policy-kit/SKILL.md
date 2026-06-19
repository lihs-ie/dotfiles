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
  `verify-no-stub-placeholder.sh` `verify-allowlist-expiry.sh` `agent-policy-hook.sh`
  `agent-evidence-gate.sh` を `scripts/` にコピー (chmod +x)。
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
- **.claude/settings.json**: PostToolUse(Write|Edit) に `agent-policy-hook.sh` を **追加**、
  Stop に `agent-evidence-gate.sh` を **追加** (既存配列にマージ・消さない)。
- **.github/workflows/pr-gate.yml**: `templates/pr-gate.yml.tmpl` を配置。決定論ゲート
  (no-prod-doubles/test-bypass/wiring/no-stub-placeholder/allowlist-expiry) を required にし、
  AI review (codex/claude) は repo variable `ENABLE_CODEX_REVIEW`/`ENABLE_CLAUDE_REVIEW` + secret で
  有効化する opt-in job として置く (未設定なら skip・merge gate は決定論ゲートのみで判定)。
  既存 CI が build/test を担うなら `{{EXTRA_JOBS}}` は空、無ければ build_and_tests job を生成。

ユーザーが承認するまで書き込まない。

## Phase 3: Apply

1. 上記ファイルを書き込み、`scripts/*.sh` に実行権限を付与する。
2. `.gitignore` に `.agent-evidence/` を追加 (証跡はローカル生成・CI で再生成)。
3. **スモークテスト of the kit 自体**: わざと違反を作って各 verify スクリプト (no-prod-doubles /
   test-bypass / no-stub-placeholder / wiring / allowlist-expiry) が exit 1 する/正常時に exit 0 する、を
   一度確認し、確認後にダミー違反を消す。
4. 適用結果を要約: 何を新規作成し、何にマージし、何をスキップしたか。
5. 次アクションを案内: 「`/proven-done <task>` で中心ループを、`/self-improve` で外側ループを駆動できる」。

## 不変条件
- 既存ファイル (CLAUDE.md, .hlint.yaml, .claude/settings.json, sgconfig.yml) は **追記/マージ** であり全置換しない。
- 方針変更は正本 `~/.claude/docs/agent-policy.md` を直してから再適用する (生成物を直接編集しない)。
- allowlist は無期限を作らない。rubric pack は検出言語のみ展開する (未使用スタックを抱えない)。
