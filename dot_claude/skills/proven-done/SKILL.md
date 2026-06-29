---
name: proven-done
description: モック濫用と未配線完了報告を防ぐ三層ループの中心ループを 1 タスクに対して駆動する。spec-curator→topology-mapper→implementer→決定論ゲート→static-verifier→runtime-verifier→spec-grader→done-evaluator(二段門)を役割別モデル(Sonnet床/境界Opus)で順に実行し、レビュー2周→人間エスカレーションで収束させる。証跡(.agent-evidence/)を必ず残し、Done は『real entrypoint から観測可能挙動を実行 assert + done-evaluator が Must を fresh context で意味判定』で決める。トリガーは /proven-done <task> slash command、または『proven-done で実装』『配線まで保証して実装』『未配線を防ぐパイプラインで』『reviewer 付きで実装してエスカレーションまで』等の依頼。前提: ~/.claude/agents/ の spec-curator/topology-mapper/implementer/static-verifier/runtime-verifier/spec-grader/done-evaluator と、対象 repo の AGENTS.md / wiring_manifest.yml / scripts/verify-*.sh。これらが無い repo では先に agent-policy-kit skill で scaffold する。
---

# proven-done

要求を 1 つ受け取り、`~/.claude/docs/agent-policy.md` の二大事故
(本番テストダブル混入 / 未配線完了報告) を防ぎながら **仕様化〜完了判定** まで駆動する三層ループの中心ループ。
外側ループ (失敗事例の eval/rule 昇格) は `/self-improve` が担う。

## 前提チェック (Step 0)

1. 引数 `<task>` を受け取る。無ければユーザーに 1 行で要求を尋ねる。
2. リポジトリルート (`git rev-parse --show-toplevel`) を確認。
3. このリポジトリに `AGENTS.md` と `wiring_manifest.yml` と `scripts/verify-no-prod-doubles.sh`
   が**揃っているか**確認する。**無ければ** 「先に `agent-policy-kit` skill でガードを scaffold
   してください」と案内し、ユーザー承認の上で agent-policy-kit を実行してから続行する。
4. **spec 前提**: `docs/specs/<feature>.md` が在るか確認する。**無ければ** Step 1 で先に仕様化する
   (`/grill-me` で人間と認識合わせ → spec-curator で正規化)。
5. `.agent-evidence/` を作り、**実行中マーカー** を立てる:
   `.agent-evidence/.active` に `task=<task>` と開始時刻を書く
   (これがある間だけ Stop hook の証跡ゲートが発火する)。
6. TaskCreate で進捗 TODO (Spec/Topology/Implement/Gate/Static/Runtime/SpecGrade/Done) を作る。

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
| 3 Implement | implementer | sonnet | sonnet | code + `wiring-map.json`/`commands.txt`/`completion-report.md` |
| 4 Gate | (skill が直接 Bash 実行) | — | — | `verify-*.log` |
| 5 Static | static-verifier | sonnet | sonnet | `static-review.json` |
| 6 Runtime | runtime-verifier | sonnet | opus | `runtime-verify.json` |
| 7 SpecGrade | spec-grader | sonnet | opus | `spec-review.json` |
| 8 Done | done-evaluator | sonnet | opus | `done-eval.json` |

### iterations.json スキーマ (Step 3 が書き、Step 4/10 が読む)

implementer は `.agent-evidence/iterations.json` に各試行ラウンドを追記する。
`scripts/verify-failure-class.sh` がこのファイルを読んで collapsed loop と未知 class を検出する。

```json
{
  "iterations": [
    {
      "round": 1,
      "failure_class": "product | test-oracle | harness-env | flaky | wiring-integration",
      "approach": "アプローチの概要 (1行)",
      "result": "red | green | pivot | escalate",
      "note": "失敗理由 または 達成内容 (1行)"
    }
  ]
}
```

`failure_class` enum:
- `product` — 実装ロジックの誤り (仕様通りに実装できていない)
- `test-oracle` — テスト自体が間違い / spec 不整合
- `harness-env` — 環境・タイミング・非決定性 (flaky と区別: 再現性あり vs なし)
- `flaky` — 非決定的失敗 (CI 環境の順序依存・timing race)
- `wiring-integration` — 配線・結線・DI・route 登録の欠落

### Step 1: Spec curation
`docs/specs/<feature>.md` が無ければ、まず **`/grill-me`** で人間と決定木を解消し、
その合意を `spec-curator` に渡して正規化する (Must/Should/受入条件/Non-goal/risk)。
`risk.level` を読み high-risk フラグを決める。`## Open questions` があればユーザーに確認。

### Step 1.5: Two-lane router — 通常実装 vs 緊急ブロック判定

spec を受け取った後、**2 車線** に分岐する:

**Lane A (通常実装)**: risk が `low` でブロック要因なし → Step 2 へ進む。

**Lane B (緊急ブロック)**: 以下のいずれかに該当したら、実装を開始せず即エスカレーション:
- spec に `high-risk` かつ `migration / schema / public export` が含まれ、承認者不在。
- wiring_manifest.yml のルールが全て `require_one_of` を満たせない。
- `ci/allowlist.yml` に有効な例外が無く、本番 test double が既に混入している。

エスカレーション時は blocking_reasons を列挙し、`.agent-evidence/.active` を削除して停止する。

### Step 2: Topology
`topology-mapper` を起動し Impact Map (入口→中継→出口の wire-map + 必須配線点) を生成、
`.agent-evidence/impact-map.md` に保存。orphan(到達不能になりうる)経路の警告があれば spec に反映。

### Step 3: Implement
`implementer` に **Goal / Context / Constraints / Done When / Evidence Required** の 5 スロットを
spec + Impact Map から埋めて渡す。**wire-first** (呼び出し側 placeholder を先に結線) を徹底させる。
実装者は **TDD (RED→GREEN→Refactor)** で進め、同一アプローチの「実装↔テスト失敗」は **最大 3 回で approach pivot を強制**し、
pivot を 2 回 (= 3 アプローチ) 試しても未達なら未完としてエスカレーションする (試行/pivot 履歴は commands.txt)。
実装中は PostToolUse の policy hook が編集ごとにガード(no-prod-doubles / test-bypass)を回し、違反は exit 2 でブロックされる。
実装者は wiring-map.json / commands.txt / completion-report.md を残す。

### Step 3.5: Implementer 完了ガード (skill が直接確認 — 実測で必要と判明)
実装者は **大規模タスクで整形/テストに budget を取られ、結線を残したまま早期終了する**ことがある
(関数は実装したが呼び出し側の placeholder を置換し忘れる)。fitness hook も verify-wiring の
ファイル共変更検査も、この data-flow の未配線は捕捉できない。よって skill が機械的に確認する:
1. 実装者の報告が **途中終了**(「次に…する」で終わる)なら、未完を明示して **Step 3 へ差し戻す**(周回に数えない)。
2. `bash scripts/verify-no-stub-placeholder.sh` で placeholder stub (`err501`/`notImplemented`/`todo!()` 等) の
   残置を検出 → 差し戻す。
3. 各 `wired_at` が **実在の本番呼び出し**か grep で抜き取り確認する (定義/ export 宣言行ではない)。

### Step 4: Deterministic gates (skill が直接実行)
```
bash scripts/verify-no-prod-doubles.sh    > .agent-evidence/verify-no-prod-doubles.log 2>&1
bash scripts/verify-test-bypass.sh        > .agent-evidence/verify-test-bypass.log 2>&1
bash scripts/verify-wiring.sh             > .agent-evidence/verify-wiring.log 2>&1
bash scripts/verify-no-stub-placeholder.sh > .agent-evidence/verify-no-stub-placeholder.log 2>&1
```
いずれか非ゼロ終了なら、その出力を implementer に戻して Step 3 へ(周回にカウントしない)。

### Step 5: Static verify
`static-verifier` を起動し、test double / bypass / placeholder / allowlist / 証跡 / scope を機械検査、
`static-review.json` に保存。FAIL なら Step 3 へ。

### Step 6: Runtime verify (**観測可能挙動の実行 assert は必須・省略不可**)
`runtime-verifier` を起動。build/wiring/entrypoint 到達を実行で確認し、配線 rubric (`rubric/core/wiring.md`
+ 検出言語の pack) を判定する。**最重要**: spec の受入条件にある「real entrypoint での観測可能挙動」を
**実際に実行して assert** する (例: `POST /v1/x` を叩き body が非空)。これが「実装したが未配線」を WHY に
よらず捕捉する唯一の確実なネット。build が通るだけ・unit が緑なだけでは PASS にしない。
orchestrator が手動代替で**省略してはならない**。FAIL なら Step 3 へ。

### Step 7: Spec grade
`spec-grader` を起動し、spec の Must/Non-goal/契約を `rubric/core/spec.md` (+pack) で照合、`spec-review.json` に保存。
Must 未達・Non-goal 侵犯・契約破壊は FAIL → Step 3 へ。

### Step 8: Done — 二段門
- **① 構造ゲート**: `.agent-evidence/` に completion-report.md / commands.txt / wiring-map.json が
  非空で揃うか (Stop hook `agent-evidence-gate.sh` が強制。skill 側でも確認)。
- **② 意味ゲート**: `done-evaluator` を **fresh context** で起動し、spec の Must × evidence bundle を
  照合させ `done-eval.json` を得る。`continue` なら blocking_reasons を implementer に戻して Step 3 へ。

### Step 9: 収束 (最大 2 周)
1. Step 5〜8 のいずれかが FAIL / `continue` を返したら、blocking findings を集めて `implementer` に戻し、
   Step 3〜8 をやり直す (これで 1 周)。
2. **2 周終えても残る**、または `done-eval.json.escalate_to_human=true`、または同一指摘が 2 周連続
   (collapsed loop) なら **人間にエスカレーション**: 未解決の blocking findings と artifact パスを提示して停止する。
3. done-evaluator が `done` → 成功。

### Step 10: 後始末と報告
- `.agent-evidence/.active` を **削除** する。
- ユーザーへ 3 セクションで返す: **対応した内容** (entrypoint 到達を明記) / **変更ファイル一覧**
  (wiring-map.json と対応付け) / **エスカレーション事項** (残リスク・人間判断が要る点・未実行 smoke 等)。
- 失敗/補正があれば `incidents/` に記録し、`/self-improve` での昇格を促す。

## 不変条件
- テストが緑なだけで「完了」と言わない。wiring map と real entrypoint 到達を示してから完了とする。
- **完了の最終根拠は「real entrypoint を実行し観測可能挙動を assert した」+「done-evaluator が Must を
  fresh context で done と判定した」こと。** build 成功・ユニット緑は弱い近似。
- 実装者の早期終了 (結線が後手順のまま中断) を Step 3.5 で検出し差し戻す。orchestrator の手動 grep を当てにしない。
- reviewer の指摘は必ずコードパス/artifact/Must 番号に紐付ける。抽象的懸念だけで pass/fail しない。
- 本番パスの test double / test-bypass は allowlist 以外は無条件で差し戻す。
