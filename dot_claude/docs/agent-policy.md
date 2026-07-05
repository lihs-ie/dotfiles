# Agent Policy 正本 (lihs standard)

> このファイルは **正本 (single source of truth)** です。
> `agent-policy-kit` skill が、ここから各リポジトリの `AGENTS.md` と `CLAUDE.md` の
> Agent Policy 節を **生成** します。リポジトリ側の文書を直接手で書き換えず、
> 方針を変えるときはこの正本を直してから kit を再適用してください。
>
> 設計思想:
> **「AI に守ってほしいルールは、文書に書くだけでなく、必ず hook・CI・review artifact の
> どれかに変換する」**。この文書は *意図共有* に徹し、*強制* は hook / CI / reviewer が担う。
> built-in Explore / Plan subagent は CLAUDE.md を読み飛ばすため、中核ルールは必ず
> 決定論ガード (hook / CI) と独立 reviewer に二重化する。
>
> 開発フローは **三層ループ** で構成する:
> - **内側**: 実装 → 静的/動的検証 → 証拠収集 → 自動修正
> - **中間**: 独立 verifier / grader が配線ミス・仕様違反を検知して implementer に差し戻す
> - **外側**: 失敗事例・レビュー指摘を eval / rule / hook / test に昇格させる自己改善 (§6)

---

## 0. このポリシーが防ぐ二大事故

1. **本番コードへのテストダブル混入** — production path に mock/stub/fake/dummy/spy を置く。
2. **未配線の完了報告** — ユニットレベルでは動くが、route/export/DI/migration/event 購読などの
   *結線* が欠けたまま「完了しました」と報告する。

どちらも「モデルが最短で “それっぽく完了した状態” を作りに行く」ことから起きる。
テストが緑であることは弱い近似仕様に過ぎず、終了条件にしてはならない。

---

## 1. Non-negotiable rules (禁止事項)

- **本番コードに mock/stub/fake/dummy/spy 実装を導入しない。**
- テストダブルが許されるのは次のパスのみ:
  `test/`, `tests/`, `__tests__/`, `spec/`, `specs/`, `testdata/`, `fixtures/`, `mocks/`, `stubs/`, `fakes/`。
- **本番経路に test-only bypass を置かない** (`NODE_ENV === 'test'` 分岐、`if test then …`、
  テスト用ショートサーキット、TODO bypass 等で本番ロジックを迂回しない)。
- 生成コード (`generated/`, gRPC stub 等) や legitimate な "stub" は
  **owner と expiry を持つ allowlist** (`ci/allowlist.yml`) でのみ許可する。無期限 allowlist は禁止。
- 指定された **Scope 外** のファイルを変更しない。spec の Non-goals に挙げた変更を勝手に入れない。
- 既存アーキテクチャ (層構成・依存方向・命名規約) を尊重する。不要な refactor / 将来用抽象化を足さない。
- **フレーキーテストは `ci/quarantine.yml` に隔離登録**し、無期限隔離は禁止 (`verify-allowlist-expiry.sh --quarantine` で期限切れを検出)。
- **verify スクリプトの修正は必ず `agent-policy-kit` の `templates/scripts/` にテンプレートに先に入れてから
  sync (Detect→Diff→Apply, dry-run 既定) で配布する。消費 repo に配布された `scripts/verify-*.sh`
  コピーへの直接修正は禁止** (テンプレートと乖離した直修正はドリフトの温床であり、次回 sync で
  黙って上書きされる/されない、が repo ごとに異なる不整合を生む)。

## 2. 上流 — 仕様の正規化 (Spec layer)

実装の前に、要求を **検証可能な仕様** へ落とす。これが無いと「何を満たせば done か」が曖昧になり、
未配線・仕様逸脱の温床になる。

- 人間との **認識合わせは `/grill-me`** で行う (決定木を 1 つずつ解消する)。
- 合意を **spec-curator** が `docs/specs/<feature>.md` に正規化する。必須項目:
  - **Must** — 満たさなければ done でない受入条件。各 Must は *機械検証可能* な形にする。
  - **Should** — 望ましいが必須でない。
  - **受入条件 (acceptance)** — Must を「どのコマンド/挙動で確認するか」に翻訳したチェックリスト。
  - **Non-goals** — 今回やらないこと (scope 外・将来課題)。
- spec-curator は `real_entrypoint` に対象サービスの inbound route を記録し、その下流呼び出し route を
  inbound と取り違えない (サービス A が下流 B を HTTP で叩く構成で、A の real_entrypoint を B の route と混同しない)。
- **risk 分類**: 次のいずれかに触れるなら `high-risk`。reviewer/verifier を最深ティアに昇格する (§7):
  `DI` / `routing` / `auth` / `config` / `migration` / `schema` / `public export` /
  `background job` / `event subscription`。
- `proven-done` の phase 1 はこの spec を **前提に読む**。spec が無ければ spec-curation を先に行う。

## 2.5 Two-lane router — 実装レーン判定

spec 受け取り後、以下の判定式でレーンを決める (proven-done Step 1.5):

| レーン | 条件 | 対応 |
|---|---|---|
| **block** | `must_count > 8` OR `estimated_files > 30` OR (`high-risk` AND `boundary_touched=multi`) | 実装を開始せず即エスカレーション |
| **light** | `low-risk` AND `must_count ≤ 3` AND `estimated_files ≤ 5` AND `boundary_touched=false` | Step 2 へ通常進行 |
| **heavy** | それ以外 | Step 2 へ通常進行 (Time budget は heavy=90min) |

- `boundary_touched=multi`: DI / routing / auth / config / migration / schema / public export / background job / event subscription のうち 2 つ以上を跨ぐ。
- block レーンは blocking_reasons を列挙し `.agent-evidence/.active` を削除して停止する。
- light/heavy の区別は Time budget 閾値に影響する (light=30min / heavy=90min)。

## 3. Done when (完了条件) — 二段門

次を **すべて** 満たして初めて「完了」と呼べる。最終確認は **二段門** で行う:

- **① 構造ゲート** (`scripts/agent-evidence-gate.sh`, Stop hook): 証跡 (§4) が非空で揃っているか。
- **② 意味ゲート** (`done-evaluator` agent, fresh context): spec の **Must × evidence bundle** を照合し、
  `done | continue` を返す。`continue` なら未達理由を添えて implementer に差し戻す。
  自己反省ではなく **別コンテキスト** の判定であること (§7 の done-evaluator)。

満たすべき実体:

- 要求された挙動が **real public entrypoint から到達可能** である
  (ローカル関数を直しただけで route/export/container/provider/main に載っていない状態は未完了)。
- **観測可能挙動を real entrypoint で実行して assert** した (build 成功・unit 緑は弱い近似に過ぎない)。
- テスト成功は exit code / "SUCCEEDED" 表示だけで判断せず、**実行件数 N>0 かつ failure 0** を確認する (0 件実行 = 成功ではない)。テストランナーは失敗ありでも exit 0 を返しうる (例: Xcode の xcodebuild は failedTests>0 でも exit 0)。**構造化結果 (xcresult / JUnit XML 等) の `failedTests>0` / `result≠passed` を一次判定**にし、gate は xcresulttool 等で parse して fail closed にする。
- working-tree 状態で回す決定論ゲートは未コミット変更も検査対象に含める (committed diff が空 = OK と即断しない)。
- implementer の `completion-report.md` の `Done When` には **runtime-final gate** (例: full E2E gate / integration test) の `rc=0` 確認を含める。SPM/unit + fast-gate (lint) のみで done と主張してはならない (app 起動 crash / 配線漏れ / build 連鎖エラーは unit/lint 経路では検出不能)。Orchestrator は Step 3.5 完了ガードで最終 gate の rc を確認するか、その省略を明示する責任を持つ。harness-env (Xcode 26 clone-parallel 不安定等) で full E2E gate が不安定な場合は直列 fallback / 単独 sim 実行で代替確認し、その経緯を `.agent-evidence/<task>/ESCALATION-*.md` に残す。
- build / lint / typecheck / unit / contract / integration・smoke が通る。
- 必要な **配線更新** が存在する:
  - **構造配線**: `route` / `export` / `container` / `provider` / `main` / `module` / `migration` /
    `config` / `event subscription` / `background job registration`。
  - **データフロー配線**: 新規シンボルが本番呼び出し箇所から実参照される。placeholder
    (`[]` / `Nothing` / `undefined` / `err501` / リテラル) を残さない。
- spec の **Must を全て満たし、Non-goals を侵さない**。
- `.agent-evidence/iterations.json` の `failure_class` が全て有効な 5 値 enum (`product` / `test-oracle` / `harness-env` / `flaky` / `wiring-integration`) であり、collapsed loop (末尾 3 ラウンド同一 class) が存在しない。
- 完了報告に **実行コマンド・生成 artifact・wiring map** が含まれる。

## 4. Evidence required (完了報告に必須の証跡)

完了報告 (`.agent-evidence/completion-report.md`) には次を必ず含める:

- **Changed files** — 変更ファイル一覧。
- **Public entrypoint(s) exercised** — どの公開入口を経由して挙動に到達したか。
- **Runtime command(s) executed** — 実行したコマンド (`commands.txt`)。
- **Artifact paths** — build/test/smoke ログ等の成果物パス。
- **Wiring map** (`wiring-map.json`) — 変更したシンボルと、それを結線した登録点の対応表。
- **Spec 参照** — 満たした `docs/specs/<feature>.md` のパスと、各 Must の充足根拠。
- **Remaining risks / assumptions** — 未解消の前提・残リスク。
- **iterations.json** (`failure_class` 記録) — TDD サイクルごとの試行ログ。

## 5. Review — rubric と基準

判定は **rubric** に沿って行う。rubric は kit が repo に scaffold する:

- **core rubric (言語不受・必須)**:
  - `rubric/core/wiring.md` — 入口/中継/出口/設定/起動/逆流/回帰 の配線到達を機械検証で yes/no。
  - `rubric/core/spec.md` — Must 達成/Non-goal 順守/API 互換/mock 禁止/依存制約/文書整合/証拠品質/可逆性。
- **stack pack (検出言語のみ opt-in)**: `rubric/packs/<lang>.md` (Next.js read-back, Laravel feature,
  Go arch+fuzz, Haskell exposed-modules, OIDC PKCE, DDD aggregate 境界 等)。

レビュー基準:

- **配線漏れ・未結線は P0 もしくは P1** として扱う。
- 変更が境界を跨ぐのに **ユニットテストのみ** を根拠にした "done" は却下する。
- allowlist 外の本番パス mock/stub/fake/dummy/spy は無条件で却下する。
- 指摘は **必ず具体的なコードパスまたは artifact に紐付ける** (抽象的懸念だけで pass/fail を出さない)。
- 証跡が不十分なら PASS ではなく **FAIL ("missing evidence")** を返す。
- レビューループは **2 周まで**。それでも FAIL が残る/同一指摘が 2 周連続 (collapsed loop) なら
  人間にエスカレーションする (終わりのない AI 同士の往復はコンテキスト汚染とコスト増を招く)。
- implementer が **同一 test / spec に対し 3 回連続 RED → fix → RED** した場合、orchestrator は
  spec-grader を DEEPEST_MODEL で再起動し、(a) test pyramid 層違反 (unit で表現できる挙動を E2E
  に置いていないか) (b) 環境非決定性 (timing/order/UserDefaults 汚染) (c) spec 自体の inconsistency
  を一次評価項目として **spec amend 提案** を能動的に出させる。implementer のさらなる try-and-error
  を黙認しない (collapsed loop は spec の問題である可能性が高い)。
- implementer は spec が `public` / `open` API シグネチャ不変を Must としている場合、変更前に
  spec amend を要求し orchestrator にエスカレーションする。事後修正 (Round N で破壊 → Round N+1
  で復元) は禁止。public API の互換破壊は spec 改訂 → 同意 → 実装の順で進める。
- implementer は TDD サイクルごとに `.agent-evidence/iterations.json` に `failure_class` を記録する義務がある。`failure_class` 未記録の試行は **証跡不十分** として static-verifier が FAIL にする。

## 6. 外側ループ — 自己改善 (failure-mining → promotion)

失敗を「その場の会話」で終わらせず、durable artifact に昇格する。`/self-improve` で駆動する。

- **入力**: `incidents/` (本番異常・レビュー指摘・補正データ)。
- **failure-miner**: incident をクラスタ化し、再発防止の **eval 候補 / rule 候補** を出す。
- **harness-maintainer**: 候補を hooks / lints / tests / docs / 正本へ **昇格** する。
- **保存位置 (repo 内に commit)**: `docs/specs/` `evals/wiring/` `evals/spec/` `incidents/`
  `rules/promoted/` `memory/lessons/`。コードと一緒に PR で review でき、repo 固有文脈を保てる。

### 昇格しきい値

| 条件 | 昇格先 |
|---|---|
| 同じ指摘が 2 回出た | `CLAUDE.md` / `AGENTS.md` (正本経由) に短文化 |
| 同じ failure class が 3 回出た | `evals/` に eval を作成 |
| false negative のコストが高い | CI gate / hook へ昇格 |
| 静的に確実に判定できる | lint / grep / arch test (ast-grep/hlint) へ昇格 |
| 実行時しか判定できない | smoke / E2E / runtime-verifier rubric へ昇格 |
| 人の補正データが十分たまった | rubric と fixture を拡張 |
| false positive が多い | memory に戻す / matcher を narrow に再設計 (rollback) |

`memory/lessons/` の 1 lesson 1 file。一行要約 + trigger + verified facts + general rule + promotion status。
誤りと判明した lesson は削除し、重複は新規作成せず更新する。

---

## 7. 役割とモデル配分 (9 agent、read-only 4 体が iterations.json を参照)

> **DEEPEST_MODEL = `opus`** — 最深ティア (長時間・横断メタ推論) に使うモデル。
> (2026-06-22 に fable から切り替え済み)。下表の「最深」はこの値を指す。

モデルは **境界 (risk 区分) で段階化** する。床は Sonnet、境界跨ぎ (high-risk, §2) は Opus、
外側ループのメタ作業は DEEPEST_MODEL。

| 段 | 役割 | 目的 | 権限 | モデル (low / high-risk) |
|---|---|---|---|---|
| 仕様化 | **spec-curator** | grill-me 合意を Must/Should/受入/Non-goal + risk に正規化 → `docs/specs/` | Read, Search, Write(specs) | Sonnet / Opus |
| 影響調査 | **topology-mapper** | 入口→中継→出口の wire-map・call graph・配線点列挙 (旧 explorer 吸収) | Read-only | Sonnet |
| 実装 | **implementer** | 最小 diff・wire-first・テスト更新・証跡作成 | Read, Write, Run | Sonnet |
| 静的検証 | **static-verifier** | test double / bypass / allowlist / 証跡 / scope の機械検査 | Read-only | Sonnet |
| 動的検証 | **runtime-verifier** | real entrypoint 実行 assert + 配線 rubric (+stack pack) | Read, Run | Sonnet / Opus |
| 仕様監査 | **spec-grader** | spec Must/Non-goal/契約を rubric で照合 (+stack pack) | Read-only | Sonnet / Opus |
| 完了判定 | **done-evaluator** | fresh context で Must × evidence を照合し done/continue | Read-only | Sonnet / Opus |
| 自己改善 | **failure-miner** | incident をクラスタ化し eval/rule 候補を出す | Read-only | Sonnet / **最深** (多数 incident 集約時) |
| ルール昇格 | **harness-maintainer** | 候補を hooks/lints/tests/docs/正本へ昇格 | Read, Write | **最深** |

実装の固定スロット (implementer に毎回渡す): **Goal / Context / Constraints / Done When / Evidence Required**。
**書くのは 1 体、読むのは多体、判定は独立** — 並列化するのは探索・レビュー・証拠収集側。実ファイル更新は implementer に集中させる。

**per-edit hook が重い言語の大タスク分割**: PostToolUse fitness hook が編集ごとに重い検証 (Haskell の
`cabal test` 等) を走らせる言語では、1 implementer に多ファイル変更を負わせると hook コストで budget を
使い切り、結線/テスト完了直前で **早期終了**しやすい (incident: record field 追加漏れが runtime thunk
crash)。3 ファイル以上を跨ぐ Haskell タスクは **型/DTO 定義・本番配線・テスト追加を別 implementer に分割**
(互いにファイル衝突しない範囲で) し、各 implementer の scope を小さく保つ。早期終了の形跡があれば
orchestrator は実装を肩代わりせず、build/test/grep で実ファイル状態を確認し残件だけ再 dispatch する
(実装の正は緑テストではなく real entrypoint 到達)。

---

## 8. 強制レイヤ (この文書を実行可能にする変換先)

| ルール | 強制点 |
|---|---|
| 本番 test double 禁止 | ast-grep / hlint ルール + `scripts/agent-policy-hook.sh` (PostToolUse, exit 2) + CI policy job |
| test-only bypass 禁止 | ast-grep ルール + PostToolUse hook + CI policy job |
| placeholder stub 残置禁止 | `scripts/verify-no-stub-placeholder.sh` + 実行 assert (runtime-verifier) + CI |
| wiring 追随 (構造) | `wiring_manifest.yml` + `scripts/verify-wiring.sh` + CI policy job |
| wiring 追随 (データフロー) | runtime-verifier の **real entrypoint 実行 assert** (ファイル共変更検査では捕捉不可) |
| Done = 二段門 | ① `scripts/agent-evidence-gate.sh` (Stop, 構造) + ② `done-evaluator` agent (意味) |
| spec-amend / stash-escape 検出 (proven-done 完了迂回対策) | `scripts/verify-guard-integrity.sh` (Step 4 battery + `agent-evidence-gate.sh` の in-place 直接実行、waiver 不能) |
| 仕様/配線 rubric | `rubric/core/*.md` + `rubric/packs/<lang>.md` (検出言語のみ) を reviewer が参照 |
| 証跡提出 | `.agent-evidence/` + Stop hook (proven-done 実行中マーカー時のみ発火) |
| failure_class 記録義務 | `scripts/verify-failure-class.sh` (exit 1: 未知 class / exit 2: collapsed loop) + static-verifier |
| フレーキー隔離 | `ci/quarantine.yml` + `scripts/verify-allowlist-expiry.sh --quarantine` + CI policy job |
| merge gate | GitHub required checks (`pr-gate.yml`: 決定論ゲート必須 + AI review opt-in) + artifacts + `GITHUB_STEP_SUMMARY` |

> CI の AI review (Codex / Claude) は **secret がある repo でのみ有効化する opt-in job** とし、
> merge gate は決定論ゲート + build/test + smoke の required check だけで判定する (secret 無し repo でも CI が通る)。

---

## 9. リポジトリ固有スロット (kit が埋める)

以下は `agent-policy-kit` が各リポジトリの言語・構成を検出して `AGENTS.md` に展開する:

- `{{REPO_LAYOUT}}` — モジュール / アプリ構成。
- `{{BUILD_TEST_LINT}}` — build / test / lint / typecheck コマンド。
- `{{TEST_DOUBLE_DIRS}}` — テストダブルを許可するディレクトリ (既定は §1 の一覧)。
- `{{WIRING_POINTS}}` — このリポジトリの結線点 (例: cabal exposed-modules, Next.js route, DI container)。
- `{{SMOKE_COMMANDS}}` — startup / changed-boundary smoke コマンド (v1 は宣言のみ可)。

---

## 10. iterations.json プロトコル

implementer が TDD サイクルで使う試行ログ。`verify-failure-class.sh` が監視する。

### failure_class enum (5値固定)
| class | 意味 |
|---|---|
| `product` | 実装ロジックの誤り |
| `test-oracle` | テスト自体が間違い / spec 不整合 |
| `harness-env` | 環境・タイミング・非決定性 (再現性あり) |
| `flaky` | 非決定的失敗 (CI 環境の順序依存・timing race) |
| `wiring-integration` | 配線・結線・DI・route 登録の欠落 |

### 自動エスカレーション条件
- **collapsed loop** (末尾 3 ラウンド同一 class) → Step 6.5 oracle-change branch へ自動誘導。
- **flaky が 2 ラウンド以上** → `ci/quarantine.yml` への隔離エントリ追加を義務付け。
- **context 窓 20% 以下** → Step 10 に強制ジャンプし `time-budget-exceeded.md` を残す。
