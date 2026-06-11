# Agent Policy 正本 (lihs standard)

> このファイルは **正本 (single source of truth)** です。
> `agent-policy-kit` skill が、ここから各リポジトリの `AGENTS.md` と `CLAUDE.md` の
> Agent Policy 節を **生成** します。リポジトリ側の文書を直接手で書き換えず、
> 方針を変えるときはこの正本を直してから kit を再適用してください。
>
> 設計思想 (ai-workflow.md より):
> **「AI に守ってほしいルールは、文書に書くだけでなく、必ず hook・CI・review artifact の
> どれかに変換する」**。この文書は *意図共有* に徹し、*強制* は hook / CI / reviewer が担う。
> built-in Explore / Plan subagent は CLAUDE.md を読み飛ばすため、中核ルールは必ず
> 決定論ガード (hook / CI) と独立 reviewer に二重化する。

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
- 指定されたスコープ外のファイルを変更しない。
- 既存アーキテクチャ (層構成・依存方向・命名規約) を尊重する。

## 2. Done when (完了条件)

次を **すべて** 満たして初めて「完了」と呼べる:

- 要求された挙動が **real public entrypoint から到達可能** である
  (ローカル関数を直しただけで route/export/container/provider/main に載っていない状態は未完了)。
- **観測可能挙動を real entrypoint で実行 assert した。** 「build/unit が緑」は弱い近似仕様であり
  終了条件にしてはならない。要求が産む出力 (例: レスポンスの findings が非空) を real entrypoint 経由の
  test or smoke で**実際に観測**し assert すること。これが「実装したが未配線」を WHY によらず捕捉する。
- build / lint / typecheck / unit / contract / integration・smoke が通る。
- 必要な **配線更新** が存在する。2 種を含む:
  - **構造の結線**: `route` / `export` / `container` / `provider` / `main` / `module` / `migration` /
    `config` / `event subscription` / `background job registration`。
  - **data-flow / call-site の結線**: 新規実装した関数・値が本番の呼び出し箇所から実際に参照され、
    placeholder (`[]` / `Nothing` / `undefined` / `err501` / 固定リテラル) が残っていない。
    *(実測: 別ファイルに関数を実装したが呼び出し側 placeholder を置換し忘れる事故が最頻。整形/テストに
    budget を取られ「結線は後の手順」のまま早期終了して起きる。wire-first = 結線を最初に通す。)*
- 完了報告に **実行コマンド・生成 artifact・wiring map** が含まれる
  (wiring map は新規 export/top-level シンボルを漏れなく列挙し各々の実呼び出し箇所を記す)。

## 3. Evidence required (完了報告に必須の証跡)

完了報告 (`.agent-evidence/completion-report.md`) には次を必ず含める:

- **Changed files** — 変更ファイル一覧。
- **Public entrypoint(s) exercised** — どの公開入口を経由して挙動に到達したか。
- **Runtime command(s) executed** — 実行したコマンド (`commands.txt`)。
- **Artifact paths** — build/test/smoke ログ等の成果物パス。
- **Wiring map** (`wiring-map.json`) — 変更したシンボルと、それを結線した登録点の対応表。
- **Remaining risks / assumptions** — 未解消の前提・残リスク。

## 4. Review guidelines (レビュー基準)

- **配線漏れ・未結線は P0 もしくは P1** として扱う。
- 変更が境界を跨ぐのに **ユニットテストのみ** を根拠にした "done" は却下する。
- allowlist 外の本番パス mock/stub/fake/dummy/spy は無条件で却下する。
- 指摘は **必ず具体的なコードパスまたは artifact に紐付ける** (抽象的懸念だけで pass/fail を出さない)。
- 証跡が不十分なら PASS ではなく **FAIL ("missing evidence")** を返す。
- レビューループは **2 周まで**。それでも FAIL が残るなら人間にエスカレーションする
  (終わりのない AI 同士の往復はコンテキスト汚染とコスト増を招く)。

### 重大度を最上位 reviewer に自動昇格させる変更領域

次のいずれかに触れたら、Integration / Final reviewer を最上位 tier (Opus) に引き上げる:

`DI` / `routing` / `auth` / `config` / `migration` / `schema` / `public export` /
`background job` / `event subscription`。

---

## 5. 役割とモデル配分

| 役割 | 目的 | 権限 | モデル |
|---|---|---|---|
| Planner | 要求を Task Contract に落とす。リスク分類・完了条件固定 | Read, Search | Sonnet (高リスクは Opus) |
| Explorer | 影響範囲・entrypoint・配線点の把握 | Read-only | Haiku |
| Implementer | 実装・テスト更新・証跡作成 | Read, Write, Run | Sonnet |
| Integration Verifier | build/smoke/route/export/DI の確認 | Read, Run | Sonnet (境界跨ぎは Opus) |
| Reviewer Static | ルール違反・パス検査・証跡有無の確認 | Read-only | Haiku |
| Reviewer Integration | 配線漏れ・証跡検証 | Read-only | Sonnet |
| Reviewer Final | 実装妥当性・配線漏れ・重大バグ判定 | Read-only | Opus |

実装の固定スロット (Implementer に毎回渡す): **Goal / Context / Constraints / Done When / Evidence Required**。

---

## 6. 強制レイヤ (この文書を実行可能にする変換先)

| ルール | 強制点 |
|---|---|
| 本番 test double 禁止 | ast-grep / hlint ルール + `scripts/fitness/hook.sh` (PostToolUse, exit 2) + CI policy job |
| test-only bypass 禁止 | ast-grep ルール + fitness hook + CI policy job |
| 構造の wiring 追随 | `wiring_manifest.yml` + `scripts/verify-wiring.sh` (ファイル共変更検査) + CI policy job |
| data-flow wiring (placeholder 未置換 / 未配線) | **挙動 assert** (Done When の観測可能挙動を Step 5 integration-verifier が real entrypoint で実行 assert) + `scripts/verify-no-stub-placeholder.sh` (stub 残置検出) + agent-dev Step 3.5 完了ガード |
| 証跡提出 | `.agent-evidence/` + Stop hook (agent-dev 実行中マーカー時のみ発火) |
| merge gate | GitHub required checks (`pr-gate.yml`) + artifacts + `GITHUB_STEP_SUMMARY` |

> **注 (実測の教訓)**: `verify-wiring.sh` は「`when` の file を変えたら `require_one_of` の file も変えよ」という
> **ファイル共変更**ヒューリスティックで、コードの**実参照を見ない**。よって「関数を実装したが呼び出し側の
> placeholder (`= []` 等) を置換し忘れた」data-flow の未配線は **原理的に捕捉できない**。この種の未配線は
> 言語非依存で確実な **real entrypoint の挙動 assert** (上表 data-flow 行) で捕える。grep ベースの orphan 検出は
> 多行呼び出し等で誤検出が多く採用しない。

---

## 7. リポジトリ固有スロット (kit が埋める)

以下は `agent-policy-kit` が各リポジトリの言語・構成を検出して `AGENTS.md` に展開する:

- `{{REPO_LAYOUT}}` — モジュール / アプリ構成。
- `{{BUILD_TEST_LINT}}` — build / test / lint / typecheck コマンド。
- `{{TEST_DOUBLE_DIRS}}` — テストダブルを許可するディレクトリ (既定は §1 の一覧)。
- `{{WIRING_POINTS}}` — このリポジトリの結線点 (例: cabal exposed-modules, Next.js route, DI container)。
- `{{SMOKE_COMMANDS}}` — startup / changed-boundary smoke コマンド (v1 は宣言のみ可)。
