---
name: agent-policy-kit
description: "モック濫用と未配線完了報告を防ぐ agent-policy ガード一式を任意のリポジトリに scaffold する (lihs 標準)。Detect(言語/構成/既存ガード検出)→Diff(dry-run で差分提示)→Apply(承認後に書込) の 3 phase。生成物: AGENTS.md + CLAUDE.md(正本 ~/.claude/docs/agent-policy.md から生成)、ast-grep/hlint の no-prod-doubles・no-test-bypass ルール、wiring_manifest.yml、ci/allowlist.yml、scripts/verify-*.sh、PostToolUse 追加 hook(agent-policy-hook.sh)、Stop hook 証跡ゲート(agent-evidence-gate.sh)、.github/workflows/pr-gate.yml。言語は package.json/cabal/go.mod/composer.json/pyproject/Cargo で機械検出し言語パックを選ぶ。既存設定を黙って上書きせず diff を提示してから apply する。トリガー例: 「agent-policy 入れて」「mock 防止ガード入れて」「未配線検出を設定」「pr-gate 入れて」「このリポジトリに agent-policy-kit 適用」。新規 repo でも既存 repo の audit + 不足追加でも使う。"
---

# agent-policy-kit

`~/.claude/docs/agent-policy.md` の方針を、対象リポジトリで動く **決定論ガード + 文書 + merge gate**
に変換して scaffold する。`github-repo-rules` と同じく **Detect → Diff → Apply** で、
既存を黙って壊さない。

テンプレートは `templates/`、検出は `scripts/detect-langs.sh`。正本は `~/.claude/docs/agent-policy.md`。

## Phase 1: Detect

1. 対象 repo root を確定 (引数 or cwd の `git rev-parse --show-toplevel`)。
2. `bash ~/.claude/skills/agent-policy-kit/scripts/detect-langs.sh <root>` を実行し、
   言語 / モノレポ構成 / 既存ガード (fitness hook, ast-grep, hlint, CI) / kit 適用状況を把握する。
3. 結果をユーザーに要約提示する (言語パック、結線点の候補、既存 CI との重複)。

## Phase 2: Diff (dry-run)

apply する各ファイルについて「新規 / 既存と差分 / スキップ」を提示する。特に注意:

- **AGENTS.md / CLAUDE.md**: 正本 + 検出した `{{REPO_LAYOUT}}` `{{BUILD_TEST_LINT}}`
  `{{TEST_DOUBLE_DIRS}}` `{{WIRING_POINTS}}` `{{SMOKE_COMMANDS}}` を埋めて生成。
  CLAUDE.md が既存なら **末尾に「## Agent Policy」節を追記** (全置換しない)。
- **ast-grep**: `.ast-grep/rules/` に `no-prod-doubles.yml` `no-test-bypass.yml` を追加。
  `sgconfig.yml` の `ruleDirs` が既にそのディレクトリを指していれば設定変更不要。
- **hlint**: Haskell があれば backend の既存 `.hlint.yaml` に
  `templates/hlint/no-prod-doubles.yaml` の内容を **MERGE** (検出した *.Mock/*.Fake モジュールを enumerate)。
- **scripts/**: `verify-no-prod-doubles.sh` `verify-test-bypass.sh` `verify-wiring.sh`
  `verify-allowlist-expiry.sh` `agent-policy-hook.sh` `agent-evidence-gate.sh` を `scripts/` にコピー (chmod +x)。
- **wiring_manifest.yml**: `templates/wiring_manifest.yml.tmpl` の `{{WIRING_RULES}}` を、
  検出した結線点 (例: Haskell の `**/Api.hs`→`Main.hs`/`Application.hs`、Next.js の
  `app/**/route.ts`→登録点、NestJS の `*.controller.ts`→`*.module.ts`) で埋める。
- **ci/allowlist.yml**: 空テンプレートを配置 (既存があればスキップ)。
- **.claude/settings.json**: PostToolUse(Write|Edit) に `agent-policy-hook.sh` を **追加** (既存 hook を消さない)、
  Stop に `agent-evidence-gate.sh` を **追加**。既存配列にマージする。
- **.github/workflows/pr-gate.yml**: `templates/pr-gate.yml.tmpl` を配置。既存 CI が build/test を
  担うなら `{{EXTRA_JOBS}}` は空、無ければ build_and_tests job を生成して埋める。

ユーザーが承認するまで書き込まない。

## Phase 3: Apply

1. 上記ファイルを書き込み、`scripts/*.sh` に実行権限を付与する。
2. `.gitignore` に `.agent-evidence/` を追加 (証跡はローカル生成・CI で再生成)。
3. **スモークテスト of the kit 自体**: わざと違反を作って各 verify スクリプトが exit 1 する/
   正常時に exit 0 する、を一度確認し、確認後にダミー違反を消す。
4. 適用結果を要約: 何を新規作成し、何にマージし、何をスキップしたか。
5. 次アクションを案内: 「`/agent-dev <task>` で実装パイプラインを駆動できる」。

## 不変条件
- 既存ファイル (CLAUDE.md, .hlint.yaml, .claude/settings.json, sgconfig.yml) は **追記/マージ** であり全置換しない。
- 方針変更は正本 `~/.claude/docs/agent-policy.md` を直してから再適用する (生成物を直接編集しない)。
- allowlist は無期限を作らない。
