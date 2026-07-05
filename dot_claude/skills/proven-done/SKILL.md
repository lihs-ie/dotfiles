---
name: proven-done
description: モック濫用と未配線完了報告を防ぐ三層ループの中心ループを 1 タスクに対して駆動する。spec-curator→topology-mapper→implementer→決定論ゲート→static-verifier→runtime-verifier→spec-grader→done-evaluator(二段門)を役割別モデル(Sonnet床/境界Opus)で順に実行し、レビュー2周→人間エスカレーションで収束させる。証跡(.agent-evidence/)を必ず残し、Done は『real entrypoint から観測可能挙動を実行 assert + done-evaluator が Must を fresh context で意味判定』で決める。トリガーは /proven-done <task> slash command、または『proven-done で実装』『配線まで保証して実装』『未配線を防ぐパイプラインで』『reviewer 付きで実装してエスカレーションまで』等の依頼。前提: ~/.claude/agents/ の spec-curator/topology-mapper/implementer/static-verifier/runtime-verifier/spec-grader/done-evaluator と、対象 repo の AGENTS.md / wiring_manifest.yml / scripts/verify-*.sh。これらが無い repo では先に agent-policy-kit skill で scaffold する。
---

# proven-done

要求を 1 つ受け取り、`~/.claude/docs/agent-policy.md` の二大事故
(本番テストダブル混入 / 未配線完了報告) を防ぎながら **仕様化〜完了判定** まで駆動する三層ループの中心ループ。
外側ループ (失敗事例の eval/rule 昇格) は `/self-improve` が担う。

## 前提チェック (Step 0)

(この Step の後半 (6.) で `.active` 作成と同時に stash-escape 検出用のベースライン記録も行う。)

1. 引数 `<task>` を受け取る。無ければユーザーに 1 行で要求を尋ねる。
2. リポジトリルート (`git rev-parse --show-toplevel`) を確認。
3. このリポジトリに `AGENTS.md` と `wiring_manifest.yml` と、6 本の verify スクリプト
   (`scripts/verify-no-prod-doubles.sh` `scripts/verify-test-bypass.sh` `scripts/verify-wiring.sh`
   `scripts/verify-no-stub-placeholder.sh` `scripts/verify-allowlist-expiry.sh`
   `scripts/verify-failure-class.sh`) が**揃っているか**確認する。**いずれか欠落**なら「先に
   `agent-policy-kit` skill でガードを scaffold してください」と案内し、ユーザー承認の上で
   agent-policy-kit を実行してから続行する。
   揃っていれば `bash scripts/kit-sync-check.sh --check` で各スクリプトの `KIT_VERSION` が
   kit の最新版 (`kit-manifest.yml`) と一致するか (freshness) を検査する。exit 2 (陳腐化) なら
   **警告**して `agent-policy-kit` skill の Sync (Detect→Diff→Apply, dry-run 既定) 実行を促すが、
   ブロックはせず続行する。`scripts/kit-sync-check.sh` 自体が無ければ freshness 検査を skip し、
   その旨を警告する。
4. **spec 前提**: `docs/specs/<feature>.md` が在るか確認する。**無ければ** Step 1 で先に仕様化する
   (`/grill-me` で人間と認識合わせ → spec-curator で正規化)。
5. **既存成果物の退避 (Amendment A4)**: `.active` を書く前に、`.agent-evidence/` 直下に前タスクの
   implementer 成果物 (`iterations.json` / `commands.txt` / `wiring-map.json` / `completion-report.md` /
   `round-N/` / `wiring-waivers.txt`) が残っていれば、`.agent-evidence/_archive/<旧 task_id>/` へ
   退避する (旧 task_id は残置 `.active` の `task=` 行、または `completion-report.md` の spec 参照から
   判定する)。退避しないと次タスクが旧 task_id の `iterations.json` を引き継ぎ、
   `verify-failure-class.sh`・failure_class 分布・freshness 検査が前タスクのデータを誤読する
   (dogfood 走行で topology-mapper が前タスク `verify-wiring-long-lived-branch-blindspot` の残骸と
   期限なし wiring-waiver の残置を実検出した事故に基づく)。
6. `.agent-evidence/` を作り、**実行中マーカー** を立てる。`.agent-evidence/.active` の正規スキーマは
   次の 3 行 (`scripts/agent-time-budget.sh` PreToolUse/PostToolUse hook がこれを parse する前提):
   ```
   task=<task>
   started_at=<ISO8601 UTC、例: 2026-07-02T03:48:11Z>
   lane=<light|heavy>
   ```
   Step 0 の時点ではレーン (light/heavy) が未確定 (Step 1 の spec 出力に依存) のため、ここでは
   `task=<task>` と `started_at=<ISO8601 UTC>` の **2 行のみ** を書く (`lane=` はまだ書かない)。
   `lane=` は Step 1.5 (Two-lane router) でレーン確定後に追記する
   (これがある間だけ Stop hook の証跡ゲートが発火する)。
   同じタイミングで **stash-escape 検出のベースライン記録** (`docs/specs/guard-evasion-gates.md`
   Must-3) も行う: `bash scripts/verify-guard-integrity.sh --record-stash-baseline` を実行し、
   その時点の `git stash list` 全行を `.agent-evidence/stash-baseline.txt` に記録する
   (git stash によるタスク対象ファイルの隠蔽を Step 4/Stop hook の `verify-guard-integrity.sh` が
   後で検出できるようにするため)。
7. TaskCreate で進捗 TODO (Spec/Topology/Implement/Gate/Static/Runtime/SpecGrade/Done) を作る。

> マーカーは**必ず最後に消す** (done でも人間エスカレーションでも)。途中で異常終了して
> `.active` が残った場合に備え、Stop hook のメッセージは解除方法を案内する。

## パイプライン

各段は **Agent tool** で対応する subagent_type を起動し、`model` は下表で上書きする。
spec-curator が `risk.level=high-risk` を返したら、**high-risk フラグ**を立て、
runtime-verifier / spec-grader / done-evaluator を **Opus** に昇格する。

| 段 | subagent_type | 既定 model | high-risk 時 | 成果物 |
|---|---|---|---|---|
| 1 Spec | spec-curator | sonnet | opus | `docs/specs/<feature>.md` |
| 2 Topology | topology-mapper | sonnet | sonnet | `.agent-evidence/impact-map.md` |
| 3 Implement | implementer | sonnet | sonnet | code + `wiring-map.json`/`commands.txt`/`completion-report.md` (root) |
| 4 Gate | (skill が直接 Bash 実行) | — | — | `.agent-evidence/round-<N>/verify-*.log` |
| 5 Static | static-verifier | sonnet | sonnet | `.agent-evidence/round-<N>/static-review.json` |
| 6 Runtime | runtime-verifier | sonnet | opus | `.agent-evidence/round-<N>/runtime-verify.json` |
| 7 SpecGrade | spec-grader | sonnet | opus | `.agent-evidence/round-<N>/spec-review.json` |
| 8 Done | done-evaluator | sonnet | opus | `.agent-evidence/round-<N>/done-eval.json` |

`round-<N>` の `N` は Step 9 の周回カウントと一致し、初回は `round-1`。implementer 成果物
(`completion-report.md`/`commands.txt`/`wiring-map.json`/`iterations.json`/`impact-map.md`/`.active`)
は **`.agent-evidence/` root のまま**変更しない (`scripts/agent-evidence-gate.sh` の参照パスは無変更)。
Step 4 のログは `.agent-evidence/round-<N>/` に同居させるが、ツリー状態スタンプを持たないため
freshness 検査 (`verify-evidence-freshness.sh`) の対象外 (整理上の同居に留まる)。

### iterations.json スキーマ (Step 3 が書き、Step 4/10 が読む)

implementer は `.agent-evidence/iterations.json` に各試行ラウンドを追記する。
**スキーマ正本は implementer.md §iterations.json** — 単一 JSON / append-only /
`phase` 4 値 (`red`/`green`/`refactor`/`pivot`) / `failure_class` は **phase=red のみ必須・
green / refactor は禁止・pivot は任意**。ここに複製は置かない (二重正本はドリフトの温床 —
本 skill と implementer.md のスキーマが乖離した実績があるため参照に統一した)。

`failure_class` enum (5 値):
- `product` — 実装ロジックの誤り (仕様通りに実装できていない)
- `test-oracle` — テスト自体が間違い / spec 不整合
- `harness-env` — 環境・タイミング・非決定性 (flaky と区別: 再現性あり vs なし)
- `flaky` — 非決定的失敗 (CI 環境の順序依存・timing race)
- `wiring-integration` — 配線・結線・DI・route 登録の欠落

`scripts/verify-failure-class.sh` の exit code:
- exit 1 — スキーマ違反 (phase 欠落 / 未知 enum / green・refactor への failure_class 混入)
- exit 2 — collapsed loop (**末尾 3 red** が同一 failure_class **かつ同一 target_test**)。エラーではなく Step 6.5 への routing シグナル

### Step 1: Spec curation
`docs/specs/<feature>.md` が無ければ、まず **`/grill-me`** で人間と決定木を解消し、
その合意を `spec-curator` に渡して正規化する (Must/Should/受入条件/Non-goal/risk)。
`risk.level` を読み high-risk フラグを決める。`## Open questions` があればユーザーに確認。

### Step 1.5: Two-lane router — 実装レーン判定

spec 受け取り後、以下の判定式でレーンを決める (agent-policy.md §2.5 と完全一致):

| レーン | 条件 | 対応 |
|---|---|---|
| **block** | `must_count > 8` OR `estimated_files > 30` OR (`high-risk` AND `boundary_touched=multi`) | implementer 起動なし。topology-mapper → spec-grader DEEPEST で分割推奨 → AskUserQuestion でキックオフ |
| **light** | `low-risk` AND `must_count ≤ 3` AND `estimated_files ≤ 5` AND `boundary_touched=false` | Step 2 へ通常進行。topology-mapper / static-verifier / spec-grader skip。runtime-verifier は entrypoint touch 時のみ |
| **heavy** | それ以外 | Step 2 へ通常進行 (Time budget: heavy=90min) |

- `boundary_touched=multi`: DI / routing / auth / config / migration / schema / public export / background job / event subscription のうち 2 つ以上を跨ぐ。
- **block レーン**: blocking_reasons を列挙し `.agent-evidence/.active` を削除して停止する。implementer は起動しない。topology-mapper と spec-grader DEEPEST を順に起動して spec 分割推奨を出し、`AskUserQuestion(...)` でユーザーにキックオフを委ねる。
- **light レーン**: topology-mapper / static-verifier / spec-grader を skip する。runtime-verifier は entrypoint に touch した場合のみ起動する。
- light/heavy の区別は Time budget 閾値に影響する (light=30min / heavy=90min)。
- レーン確定直後、`.agent-evidence/.active` に `lane=<light|heavy>` を追記すると**同時に**、
  `started_at` を **現在 UTC で再スタンプ**する (Amendment A3。`date -u +%Y-%m-%dT%H:%M:%SZ` を
  再実行し、Step 0 で書いた値を置き換える — grill-me / spec 化に要した人間対話時間を implementer の
  実装 budget から除外するための修正。2026-06-29 事故 (`agent-time-budget-hook` の動機) の対象は
  autonomous 実装ループの暴走であり、人間対話の待ち時間ではないため)。以後 `.active` は
  `task=`/`started_at=`/`lane=` の 3 行になり、`agent-time-budget.sh` hook はこの再スタンプ後の
  時刻を起点に budget 経過率を計算する。
- 同じタイミングで **spec-amend 検出のスタンプ記録** (`docs/specs/guard-evasion-gates.md` Must-1) も
  行う: `lane=` 追記と同時に `.agent-evidence/.active` に `spec_sha256=<sha256(docs/specs/<task>.md)>`
  を 4 行目として追記し、`task=`/`started_at=`/`lane=`/`spec_sha256=` の 4 行構成にする。
  これが `scripts/verify-guard-integrity.sh` の spec-amend サブチェックの基準になり、以後 spec
  ファイルが無断で書き換えられていないかを Step 4/Stop hook が検出できるようにする。

### Step 2: Topology
`topology-mapper` を起動し Impact Map (入口→中継→出口の wire-map + 必須配線点) を生成、
`.agent-evidence/impact-map.md` に保存。orphan(到達不能になりうる)経路の警告があれば spec に反映。

**heavy レーンでは** (light/block では評価しない)、topology-mapper が Impact Map 生成と
**同一呼び出し内**で (追加の Agent 呼び出しを発生させずに) 発火条件式
`must_count >= 4 OR estimated_files >= 10 OR layers_touched >= 3` を評価し、成立すれば
`packet_id`/`musts`/`target_files`/`done_when`/`depends_on` の 5 フィールドを持つ `packets[]` 分解案
(producer-before-consumer 順序) を最終応答テキストとして返す (Must-1)。`.agent-evidence/impact-map.md`
には新設フィールド `layers_touched` (変更が跨ぐ層数) を含める。分解案の**採否確定は Step 2.5 (後述)
で orchestrator が行い**、採用時は `.agent-evidence/work-packets.json` として永続化し
`decomposition_adopted` を確定する (topology-mapper 自身は提案のみ)。

### Step 2.5: 実測 file 数での再 triage + packet 分解の採否確認

**heavy レーンでのみ実行する** (Step 2 の「heavy レーンでは (light/block では評価しない)」と同じ区分)。
light レーンは Step 1.5 で topology-mapper 自体を skip するため `.agent-evidence/impact-map.md` が
存在せず、本 Step も skip する (light の定義上 `estimated_files ≤ 5` で block/packet 分解いずれの
発火閾値にも届かないため、skip しても機能的損失はない)。

topology-mapper が Step 2 で生成した `.agent-evidence/impact-map.md` の **Public entrypoints /
Wiring points that MUST follow the change / Blast radius** 各節に列挙された変更対象・結線先ファイルを
数え上げ、重複を除いた総数を **実測 `estimated_files`** として算出する (spec-curator が Step 1 で
Risk 節に書いた `estimated_files: <N> (basis: ...)` は Step 2 実行前の当て推量であり、ここでの実測値に
置き換える)。

1. **block 閾値の再判定**: 実測 `estimated_files` が Step 1.5 の block レーンと同一の閾値
   (`estimated_files > 30`) を超えたら、Step 1.5 の block レーンと**同じ手順**を取る:
   `blocking_reasons` を列挙し `.agent-evidence/.active` を削除して停止する (implementer は起動しない)。
   分割提案は Step 1.5 block レーン同様、topology-mapper と spec-grader DEEPEST を順に起動して
   `AskUserQuestion(...)` でユーザーにキックオフを委ねる。
2. **packet 分解採否の確定 (Must-1 の解決)**: Must-1 の発火条件式
   `must_count >= 4 OR estimated_files >= 10 OR layers_touched >= 3` を、この実測 `estimated_files`
   (と spec-curator の `must_count`、`impact-map.md` の `layers_touched`) で**再判定**する
   (spec-curator の初期見積りではなく、この Step 2.5 の実測値を採用する)。
   - 成立する場合、Step 2 で topology-mapper が最終応答テキストとして返した `packets[]` 分解案を
     `.agent-evidence/work-packets.json` として永続化し、`decomposition_adopted: true` を書き込む
     (Step 2 の「採否確定は Step 2.5 (後述) で orchestrator が行い」を解決)。
   - 成立しない場合は `decomposition_adopted: false` を記録する (`work-packets.json` は作らなくてよい)。
     Step 3 は通常の単発フローで進める。
3. block にも該当せず packet 分解も不採用の場合は、そのまま Step 2.7 (書込プローブ) へ進む。

### Step 2.7: 書込プローブ (implementer 起動前の harness-env 検出 — 実測で必要と判明)
background subagent は permission prompt を出せず、Write/Edit が **auto-deny で無音消失**しうる。
この状態で implementer を起動すると「テスト green・git status 出力付き」の完了報告が返るのに
**実ディスクへの書込はゼロ**という最悪形態の未配線報告が量産される (2026-07-02 に implementer 2 周分・
計 ~25 分 + 255k tokens が書込消失で空回りした実証事故)。これを implementer 起動前に 1 tool call で検出する:

1. orchestrator が **使い捨て subagent (最小 tools = Write のみ)** を起動し、
   `.agent-evidence/.write-probe` に 1 行 (probe token + タイムスタンプ) を書かせて即終了させる。
2. orchestrator 自身が `ls -la .agent-evidence/.write-probe` を実行し、tool result で **実在を確認**する
   (subagent の自己申告を根拠にしない — 消失を自覚できないのが本事故の核心)。
3. **不在なら harness-env** (permission auto-deny / 書込消失) と判定し、**implementer を起動しない**。
   `AskUserQuestion(...)` で permission 設定 (acceptEdits / settings allow) の修正をユーザーに求めて停止する。
4. **実在確認できたら** probe ファイル (`.agent-evidence/.write-probe`) を削除してから Step 3 へ進む。

### Step 3: Implement
`implementer` に **Goal / Context / Constraints / Done When / Evidence Required** の 5 スロットを
spec + Impact Map から埋めて渡す。**wire-first** (呼び出し側 placeholder を先に結線) を徹底させる。
実装者は **TDD (RED→GREEN→Refactor)** で進め、同一アプローチの「実装↔テスト失敗」は **最大 3 回で approach pivot を強制**し、
pivot を 2 回 (= 3 アプローチ) 試しても未達なら未完としてエスカレーションする (試行/pivot 履歴は commands.txt)。
実装中は PostToolUse の policy hook が編集ごとにガード(no-prod-doubles / test-bypass)を回し、違反は exit 2 でブロックされる。
実装者は wiring-map.json / commands.txt / completion-report.md を残す。

### Step 3 の packet ループ分岐 (`work-packets.json` 採用時)

`.agent-evidence/work-packets.json` が存在し `decomposition_adopted: true` の場合、Step 3 は
**packet ループ**へ分岐する (通常の単発 Step 3 の代わりに、`packets[]` を `depends_on` の
producer-before-consumer 順に 1 packet ずつ処理する):

(a) packet 毎に implementer を起動する。既定は **`SendMessage` による同一 implementer への継続**
    (packet contract = 対象 packet の `musts`/`target_files`/`done_when` + 前 packet の checkpoint
    findings)。fresh 起動・escalation を挟むかどうかの**継続判定は後述の機械判定表による**
    (enum のみで判定し、抽象裁量は禁止。判定表本体の定義は Must-3)。

    **継続判定の機械判定表 (Must-3)**: 判定入力は全て決定論的 (checkpoint JSON の `verdict` 履歴 /
    UTC タイムスタンプ / exit code) であり、抽象裁量は使わない。

    | reason_code | 条件 | continuation_decision | 対応 |
    |---|---|---|---|
    | (既定・reason_code なし) | 上記いずれにも該当しない | `continue` | `SendMessage` で同一 implementer に次 packet + checkpoint findings を渡す |
    | `fail-x2` | 同一 `packet_id` の checkpoint `verdict` が **FAIL 2 回連続** | `fresh` | findings 付き packet contract を再発行して新規 implementer を起動する (新規起動前に旧 agent の生死確認を行う — 既存 Step 3.5 のルールを適用) |
    | `agent-dead` | `SendMessage` エラー / 応答なし | `fresh` | 同上 (新規 implementer 起動) |
    | `collapsed-loop` | checkpoint 時点の `verify-failure-class.sh` が exit 2 | `escalate` | **fresh ではなく** 既存 **Step 6.5 oracle-change branch** へ routing する |
    | `packet-over-budget` | packet 経過時間 > **`1.5 ×`** (レーン budget ÷ packet 数) | `escalate` | 残 packet の再分解提案、または `AskUserQuestion(...)` でユーザーにエスカレーション (fresh 継続はしない) |

    **上記 4 つの `reason_code` 以外の理由での `fresh` 起動・`escalate` は禁止**である
    (抽象裁量による fresh 起動・escalation の排除)。判定結果 (`checkpoint_verdict_history` /
    `continuation_decision` / `reason_code` / `reason_detail`) は orchestrator が
    `.agent-evidence/checkpoint-<packet_id>.json` に追記する (static-verifier.md の 2 段階書込を参照)。
(b) 各 packet 完了ごとに決定論ゲート 5 本 (`verify-no-prod-doubles.sh` / `verify-test-bypass.sh` /
    `verify-wiring.sh` / `verify-no-stub-placeholder.sh` / `verify-failure-class.sh`) を
    **累積 diff に対して**実行する。既存スクリプト群は引数無し実行で常に committed∪working-tree
    の累積差分を見るため (`verify-wiring.sh` 含む)、packet 対象ファイルへの引数絞り込みは
    **行わない** (Step 4 と同一の引数無し形式。packet を跨いだ未配線 (cross-packet wiring 欠落) を
    検出するため、対象ファイルを絞ると見逃す)。`commands.txt` に記録されるコマンドが Step 4 と
    同一の引数無し形式であることを acceptance で確認する。
(c) `static-verifier` を **checkpoint モード**で 1 回起動し (`packet_id`/`target_files`/`musts` を渡す)、
    `.agent-evidence/checkpoint-<packet_id>.json` に保存する (`round-<N>/` とは別名前空間)。
(d) 全 packet 完了後、既存のフル battery (Step 4〜8) を **task 全体で 1 回だけ**実行する
    (毎 packet フル battery は行わない — 二段門の意味論を変更しない)。
(e) Step 9 の収束ループで差し戻しが発生した場合、**該当 Must を含む packet のみを再オープン**する
    (`work-packets.json` の `packets[].musts` を索引に機械的に対応付ける。Amendment A2 で確定済み。
    task 全体をやり直さない)。

`work-packets.json` が存在しない、または `decomposition_adopted: false` の場合は、この分岐を通らず
従来通りの単発 Step 3 (上記) を実行する。

### Step 3.5: Implementer 完了ガード (skill が直接確認 — 実測で必要と判明)
実装者は **大規模タスクで整形/テストに budget を取られ、結線を残したまま早期終了する**ことがある
(関数は実装したが呼び出し側の placeholder を置換し忘れる)。fitness hook も verify-wiring の
ファイル共変更検査も、この data-flow の未配線は捕捉できない。よって skill が機械的に確認する:
1. 実装者の報告が **途中終了**(「次に…する」で終わる)なら、未完を明示して **Step 3 へ差し戻す**(周回に数えない)。
2. `bash scripts/verify-no-stub-placeholder.sh` で placeholder stub (`err501`/`notImplemented`/`todo!()` 等) の
   残置を検出 → 差し戻す。
3. 各 `wired_at` が **実在の本番呼び出し**か grep で抜き取り確認する (定義/ export 宣言行ではない)。
4. **差し戻しは排他選択**: 「`SendMessage` による既存 implementer の再開」か「新規 implementer 起動」の
   **どちらか一方のみ**を選ぶ。新規起動の前に **旧 agent の継続作業有無 (生死) を必ず確認**する。
   並行 implementer は 2026-07-02 に premature-done レース (証跡が配線に先行) を起こした実証済み事故原因 —
   implementer 2 体 + orchestrator 代筆の三者並行編集は禁止する。
5. **報告と実ディスクが矛盾したら、捏造と断定する前に harness-env (書込消失) を先に切り分ける**。
   Step 2.7 の書込プローブを再実行して判定し、probe が失敗するなら harness-env (permission auto-deny) 確定。
   差し戻し文言も **harness-env 可能性を前提に**書く (モデル非難に向かわない — 実際は環境事故のことがある)。

### Step 4: Deterministic gates (skill が直接実行)
`round-<N>` は今周回の番号 (初回は `round-1`)。ログ出力先ディレクトリを先に作る:
```
mkdir -p .agent-evidence/round-<N>
bash scripts/verify-no-prod-doubles.sh    > .agent-evidence/round-<N>/verify-no-prod-doubles.log 2>&1
bash scripts/verify-test-bypass.sh        > .agent-evidence/round-<N>/verify-test-bypass.log 2>&1
bash scripts/verify-wiring.sh             > .agent-evidence/round-<N>/verify-wiring.log 2>&1
bash scripts/verify-no-stub-placeholder.sh > .agent-evidence/round-<N>/verify-no-stub-placeholder.log 2>&1
bash scripts/verify-failure-class.sh         > .agent-evidence/round-<N>/verify-failure-class.log 2>&1
bash scripts/verify-guard-integrity.sh       > .agent-evidence/round-<N>/verify-guard-integrity.log 2>&1
bash tests/run-shell-tests.sh                > .agent-evidence/round-<N>/run-shell-tests.log 2>&1
```
`verify-guard-integrity.sh` は spec-amend (無断での spec 書き換え) と stash-escape (git stash による
タスク対象ファイルの隠蔽) を検出する (`docs/specs/guard-evasion-gates.md` Must-2/Must-4)。
`tests/run-shell-tests.sh` は Must-8 の guard 回帰スイート (spec-amend/stash-escape/active-tamper の
全 fixture ケース) を含む repo 全体のシェルテストを毎 round 自動実行する。
いずれか非ゼロ終了なら、その出力を implementer に戻して Step 3 へ(周回にカウントしない)。
`verify-failure-class.sh` が exit 2 (collapsed loop) を返した場合、実装ループを継続せず **Step 6.5** の oracle-change branch に進む。

> **verifier tree 変異ガード (Step 5〜8 の各 verifier に適用)**: orchestrator は各 verifier
> (static-verifier / runtime-verifier / spec-grader / done-evaluator) の起動前後で
> `bash scripts/evidence-stamp.sh` を実行して比較し、verifier による working tree・index の変異を
> 検出したら (前後 stamp 不一致、または verdict JSON の `self_stamp_before`≠`self_stamp_after`)
> 該当 verdict を**無効化して差し戻す** (verifier は read-only であるべきで、2026-07-02 に
> static-verifier が `git checkout` で未コミット差分を破棄した実証事故がある — 詳細は
> `incidents/2026-07-02-verifier-tree-mutation.md`)。

### Step 5: Static verify
`static-verifier` を起動し、test double / bypass / placeholder / allowlist / 証跡 / scope を機械検査、
`tree_stamp` (evidence-stamp.sh の出力) を埋め込んで `.agent-evidence/round-<N>/static-review.json` に保存。
FAIL なら Step 3 へ。

### Step 6: Runtime verify (**観測可能挙動の実行 assert は必須・省略不可**)
`runtime-verifier` を起動。build/wiring/entrypoint 到達を実行で確認し、配線 rubric (`rubric/core/wiring.md`
+ 検出言語の pack) を判定する。**最重要**: spec の受入条件にある「real entrypoint での観測可能挙動」を
**実際に実行して assert** する (例: `POST /v1/x` を叩き body が非空)。これが「実装したが未配線」を WHY に
よらず捕捉する唯一の確実なネット。build が通るだけ・unit が緑なだけでは PASS にしない。
orchestrator が手動代替で**省略してはならない**。FAIL なら Step 3 へ。

### Step 6.5: Oracle-change branch

runtime-verifier が FAIL を返し、かつ `.agent-evidence/round-<N>/spec-review.json` に
`oracle_change_suspected: true` が含まれる場合:

1. **spec-grader を DEEPEST_MODEL で再起動**し、(a) test pyramid 層違反、(b) 環境非決定性、(c) spec 自体の inconsistency を一次評価させ **spec amend 提案** を出させる。
2. spec amend 提案がある場合は **`AskUserQuestion(...)` を用いてユーザーに提示して承認を得る** (implementer の try-and-error を続けない)。
3. **amend 承認直後**、spec を書き換える**前**に `.agent-evidence/oracle-change-approval.json`
   (フィールド: `spec_path` / `old_spec_sha256` / `new_spec_sha256` / `approved_at` (ISO8601 UTC) /
   `approval_summary`) を書く (`docs/specs/guard-evasion-gates.md` Must-1)。これが唯一の正当な
   spec amend 経路であることを `scripts/verify-guard-integrity.sh` の spec-amend サブチェックが
   前提とする。
4. amend 承認後は spec-curator で spec を更新し、`.agent-evidence/.active` の `spec_sha256=` を
   新しい spec のハッシュに再記録してから、Step 1 から再開する (周回カウントはリセット)。
5. 3 周連続で oracle_change_suspected が出る場合は **collapsed oracle loop** として人間エスカレーション。

### Step 7: Spec grade
`spec-grader` を起動し、spec の Must/Non-goal/契約を `rubric/core/spec.md` (+pack) で照合、
`tree_stamp` を埋め込んで `.agent-evidence/round-<N>/spec-review.json` に保存。
Must 未達・Non-goal 侵犯・契約破壊は FAIL → Step 3 へ。

### Step 8: Done — 二段門
- **① 構造ゲート**: `.agent-evidence/` root に completion-report.md / commands.txt / wiring-map.json が
  非空で揃うか (Stop hook `agent-evidence-gate.sh` が強制。skill 側でも確認)。加えて
  `bash scripts/verify-evidence-freshness.sh` **と** `bash scripts/verify-guard-integrity.sh` の
  双方を実行し **exit 0 必須**とする。非ゼロ (印不一致・stale、または spec-amend/stash-escape の
  POLICY VIOLATION) の場合は done-evaluator を起動せず、該当 verifier (static-verifier/runtime-verifier/
  spec-grader のうち `.agent-evidence/round-<N>/` の該当 `*.json` を現在のツリーで再実行する
  (done-evaluator に stale 裁量での棚上げを許さない)。`agent-evidence-gate.sh` (Stop hook) も
  `status: complete` 分岐で `verify-guard-integrity.sh` を in-place 直接実行しており
  (round-log の走査だけに頼らない)、これと重複してでも Step 8 側で明示チェックすることで
  Stop hook を経由しない呼び出し経路 (テスト/手動実行) でも同じ保証を得る。
- **② 意味ゲート**: `done-evaluator` を **fresh context** で起動し、`.agent-evidence/round-<N>/` の
  最新 round のみを対象に spec の Must × evidence bundle を照合させ `done-eval.json` を得る。
  `continue` なら blocking_reasons を implementer に戻して Step 3 へ。

### Step 9: 収束 (最大 2 周) + Time budget 強制

1. Step 5〜8 のいずれかが FAIL / `continue` を返したら、blocking findings を集めて `implementer` に戻し、
   Step 3〜8 をやり直す (これで 1 周)。(`work-packets.json` 採用時は Step 3 packet ループ分岐の (e) に
   従い、blocking findings に対応する Must を含む packet のみを再オープンする — task 全体はやり直さない)
2. **2 周終えても残る**、または `done-eval.json.escalate_to_human=true`、または同一指摘が 2 周連続
   (collapsed loop) なら **人間にエスカレーション**: 未解決の blocking findings と artifact パスを提示して停止する。
3. done-evaluator が `done` → 成功。

**Time budget 強制** (context 枯渇防止):

以下のいずれかに該当したら、現在 step に関わらず **Step 10 (後始末と報告)** に強制ジャンプする:
- context 窓の残り **20% 以下** になった。
- **wall clock 経過時間** が閾値を超えた: light タスクで **30 分** (light=30min)、heavy タスクで **90 分** (heavy=90min)。
- **no-new-evidence**: 直近 **20 分間** に新たな証拠・進展が一切得られていない (同じ blocking finding を繰り返しているだけ)。

強制ジャンプ時は blocking findings と現在状態を `.agent-evidence/time-budget-exceeded.md` に書いてから停止し、
`AskUserQuestion(...)` でユーザーに状況を提示してエスカレーションする。
翌セッションは `time-budget-exceeded.md` を読んで Step 3 から再開できる。
context 20% 閾値を下回る前に警告を出し、ユーザーに続行 or 停止を選ばせることが望ましい。

### Step 10: 後始末と報告
- `.agent-evidence/.active` を **削除** する。
- ユーザーへ 3 セクションで返す: **対応した内容** (entrypoint 到達を明記) / **変更ファイル一覧**
  (wiring-map.json と対応付け) / **エスカレーション事項** (残リスク・人間判断が要る点・未実行 smoke 等)。
- 失敗/補正があれば `incidents/` に記録し、`/self-improve` での昇格を促す。
- `.agent-evidence/iterations.json` が存在する場合、**failure_class 分布** (各 class の出現回数) をサマリに含める。

## 不変条件
- テストが緑なだけで「完了」と言わない。wiring map と real entrypoint 到達を示してから完了とする。
- **完了の最終根拠は「real entrypoint を実行し観測可能挙動を assert した」+「done-evaluator が Must を
  fresh context で done と判定した」こと。** build 成功・ユニット緑は弱い近似。
- 実装者の早期終了 (結線が後手順のまま中断) を Step 3.5 で検出し差し戻す。orchestrator の手動 grep を当てにしない。
- reviewer の指摘は必ずコードパス/artifact/Must 番号に紐付ける。抽象的懸念だけで pass/fail しない。
- 本番パスの test double / test-bypass は allowlist 以外は無条件で差し戻す。
- `iterations.json` の `failure_class` は 5 値 enum のみ。未知 class は verify-failure-class.sh が exit 1 で検出する。
- collapsed loop (末尾 3 **red** ラウンド同一 failure_class **かつ同一 target_test** — green/refactor/pivot は窓に数えない) は Step 6.5 oracle-change branch に自動誘導する。verify-failure-class.sh が exit 2 で検出する。
- context 窓 20% 以下で Step 10 に強制ジャンプし `time-budget-exceeded.md` を残す。翌セッションで再開可能にする。
- フレーキーテスト (`failure_class=flaky`) を 2 回以上検出したら `ci/quarantine.yml` への隔離エントリ追加を implementer に義務付ける。
