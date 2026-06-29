<!-- GENERATED (dogfood) by agent-policy-kit from dot_claude/docs/agent-policy.md. 直接編集せず正本を直して再適用すること。 -->
# AGENTS.md — dotfiles

このリポジトリで AI エージェント (Claude Code / Codex 等) が守る規約。
強制は hook / CI / reviewer が担い、この文書は意図共有に徹する。正本: `dot_claude/docs/agent-policy.md`。

> **このリポジトリは chezmoi 管理の個人 dotfiles repo (config/docs 主体) である。**
> agent-policy workflow はその収録物の一つ。成果物は markdown / yaml / shell であり runtime app ではない。
> よって「配線 (wiring)」は
> コードの runtime 結線ではなく **skill ↔ agent ↔ template ↔ 正本の参照整合 (meta-wiring)** に
> 読み替える。「real entrypoint での観測可能挙動 assert」は、**verify-*.sh が実際に動く /
> skill が新 agent を参照する / sample repo へ kit を適用して pipeline が 1 周回る** ことで担保する。

## このリポジトリの構成 (Repo layout)
- `dot_claude/` — chezmoi source (`dot_claude/` → `~/.claude/`)
  - `docs/agent-policy.md` — 禁止 / Done When / 証跡 / レビュー基準 / 役割・モデル配分の **単一正本**
  - `agents/` — 9 agent: spec-curator / topology-mapper / implementer / static-verifier /
    runtime-verifier / spec-grader / done-evaluator / failure-miner / harness-maintainer
  - `skills/proven-done/` — `/proven-done <task>` 中心ループ (spec→implement→verify→grade→done)
  - `skills/agent-policy-kit/` — 任意 repo へ Detect→Diff→Apply で scaffold する kit
  - `skills/self-improve/` — 外側ループ (failure-miner → harness-maintainer、incidents→evals→rules 昇格)
- `.github/` — branch rulesets / PR・Issue テンプレ
- repo root の `AGENTS.md` / `wiring_manifest.yml` / `scripts/` / `ci/` — **この repo 自身への dogfood 適用**

## Build / Test / Lint
このリポジトリはコードを持たないため、build/test/lint は次に読み替える:
- `bash scripts/verify-no-prod-doubles.sh` / `verify-test-bypass.sh` / `verify-wiring.sh` /
  `verify-no-stub-placeholder.sh` / `verify-allowlist-expiry.sh` — 決定論ゲート
- `bash scripts/verify-failure-class.sh` — iterations.json の failure_class 検証
- `bash scripts/verify-allowlist-expiry.sh --quarantine ci/quarantine.yml` — quarantine 期限切れ検出
- `chezmoi diff` / `chezmoi apply` — `~/.claude` への反映整合
- sample repo への kit 適用 dry-run — 生成物が実際に動くかの dogfood

## Non-negotiable rules (禁止事項)
- 本番コードに **mock/stub/fake/dummy/spy** を導入しない。テストダブルは次のパスのみ:
  `test/` `tests/` `__tests__/` `spec/` `specs/` `testdata/` `fixtures/` `mocks/` `stubs/` `fakes/`。
- 本番経路に **test-only bypass** (`NODE_ENV === 'test'` 等) を入れない。
- 例外は `ci/allowlist.yml` に **owner / reason / expires_at** 付きで登録する (無期限禁止・期限切れは CI fail)。
- **フレーキーテストは `ci/quarantine.yml` に隔離登録**する (`verify-allowlist-expiry.sh --quarantine` で期限切れ検出)。
- 指定スコープ外を変更しない。既存アーキテクチャ・依存方向・命名規約を尊重する。

## Done when (完了条件)
- 要求挙動が **real public entrypoint から到達可能** (meta-repo では skill/agent/script が起動経路から参照可能)。
- 決定論ゲートが通る / chezmoi 反映が整合する / dogfood pipeline が 1 周する。
- 必要な配線更新が存在する (結線点は `wiring_manifest.yml`)。
- `.agent-evidence/iterations.json` が存在する場合、`failure_class` が 5 値 enum 内で collapsed loop が無い。
- 完了報告に 実行コマンド・artifact・wiring map を含める。

### このリポジトリの結線点 (Wiring points)
- agent 定義 (`dot_claude/agents/*.md`) → orchestrator skill (`proven-done` / `self-improve`) か正本から参照される。
- kit テンプレ (`.../agent-policy-kit/templates/**`) → kit `SKILL.md` の Apply 手順に載る。
- 正本 (`agent-policy.md`) 変更 → 生成 AGENTS テンプレ / orchestrator に追随。
詳細な機械チェックは `wiring_manifest.yml` + `scripts/verify-wiring.sh`。

## Evidence required (完了報告の証跡 → .agent-evidence/)
- changed files / public entrypoint(s) exercised / runtime commands (`commands.txt`)
- artifact paths / `wiring-map.json` / remaining risks
- proven-done 実行中は Stop hook (`scripts/agent-evidence-gate.sh`) が上記の提出を強制する。

## Review guidelines
- 配線漏れ・未結線は **P0/P1**。境界跨ぎ変更で unit test のみを根拠にした done は却下。
- allowlist 外の本番 test double は無条件却下。
- 指摘は具体的コードパス/artifact に紐付ける。証跡不十分なら PASS でなく FAIL。
- レビューは 2 周まで。残れば人間にエスカレーション。
- 次に触れたら reviewer を最上位 (Opus) に昇格: `DI`/`routing`/`auth`/`config`/`migration`/`schema`/`public export`/`background job`/`event subscription`。

## エージェント開発フロー
`/proven-done <task>` で spec-curation→topology→implement→決定論ゲート→runtime-verify→spec-grade→done-evaluator を駆動できる。
`/self-improve` で失敗事例を eval/rule に昇格する外側ループを回せる。
