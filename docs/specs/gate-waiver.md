# Spec: gate-waiver

<!-- spec-curator が /grill-me 合意 (2026-07-02) から正規化。 -->

## Goal
- 「ゲート自体が環境起因で恒久的に通せない」ケース (例: recall-paper adr-017 の Xcode 26 sim 回帰で
  `full-e2e-gate` が恒久 rc=1 → 代替検証でユーザー判断 done) を、非監査のアドホック判断のまま
  closed させず、**期限付き・承認記録付き・代替検証証跡必須** の正規手続き (waiver) として
  `ci/quarantine.yml` の `gates:` 節に記録可能にする。
- 既存の CI 穴 (`pr-gate.yml` テンプレートが `verify-allowlist-expiry.sh` を `--quarantine`
  無しでしか呼ばず、`ci/quarantine.yml` の expiry が CI で未執行) を修繕する。
- spec-grader / done-evaluator が、有効な waiver + 代替検証証跡がある場合に限り、対象ゲートの
  FAIL を blocking から除外できるようにする (waiver 無し・期限切れ・代替証跡無しは従来通り FAIL)。

## Must (満たさなければ done でない)
- [ ] **Must-1 (quarantine.yml gates: スキーマ追加)**:
      `dot_claude/skills/agent-policy-kit/templates/quarantine.yml` (テンプレート) と
      `ci/quarantine.yml` (本 repo の実ファイル) の両方に、既存 `entries:` と並列の `gates:` 節
      (既定値 `gates: []`) が追加され、以下のスキーマがコメントとして両ファイルに記載される:
      ```yaml
      gates:
        - gate: <対象ゲートのスクリプト/コマンド名>
          evidence_url: <環境起因の証拠 (issue URL / incident パス)>
          substitute_verification: <代替検証手段の具体記述>
          owner: <人名>
          expires_at: "YYYY-MM-DD"   # 無期限禁止
          approved_by: <承認者>
          approved_at: "YYYY-MM-DD"
      ```
      2 ファイルのスキーマコメントは (フィールド名・順序が) 完全一致する。
- [ ] **Must-2 (verify-allowlist-expiry.sh の gates: 対応)**:
      `dot_claude/skills/agent-policy-kit/templates/scripts/executable_verify-allowlist-expiry.sh`
      の awk が、`--quarantine <file>` 指定時に既存の `entries:` の `- test:` (および `- rule:`) に
      加えて `gates:` の `- gate:` エントリも走査し、(a) `expires_at` の欠落/期限切れ、(b)
      `evidence_url` の欠落、(c) `substitute_verification` の欠落、(d) `approved_by` の欠落を
      それぞれ独立した violation として検出する。既存 `entries:` (test:/rule:) の挙動
      (走査対象・出力・exit code) は一切変更しない。本 repo の vendored コピー
      `scripts/verify-allowlist-expiry.sh` はテンプレート修正後に sync され、テンプレートと
      完全同一内容になる (このリポジトリの `scripts/verify-*.sh` への直接修正は禁止という
      既存メタルールに従う)。
- [ ] **Must-3 (spec-grader.md / done-evaluator.md の waiver 判定手順)**:
      `dot_claude/agents/spec-grader.md` と `dot_claude/agents/done-evaluator.md` の両方に、
      以下を満たす waiver 判定手順が追加される:
      (a) 対象ゲートが FAIL または未実行でも、`ci/quarantine.yml` の `gates:` に
      **期限内 (`expires_at` >= 実行日) の該当 `gate` エントリがあり**、かつ
      **`substitute_verification` に記述された代替検証の実行証跡が evidence bundle
      (`.agent-evidence/` 配下) に存在する** 場合に限り、そのゲートの FAIL を blocking に
      しない旨の記述がある。
      (b) waiver 無し・期限切れ・代替検証証跡無しのいずれかなら、従来通り (waiver 適用前と
      同じ) FAIL/continue 判定になる旨の記述がある。
      (c) 両ファイルの Output JSON スキーマ (spec-grader は `spec-review.json`、done-evaluator は
      `done-eval.json`) に、適用した waiver を参照するフィールド (キー名に `waiver` を含む) が
      追加されている。
- [ ] **Must-4 (pr-gate.yml テンプレートへの quarantine expiry step 追加)**:
      `dot_claude/skills/agent-policy-kit/templates/pr-gate.yml.tmpl.literal` の `policy` job の
      `steps:` に、`bash scripts/verify-allowlist-expiry.sh --quarantine ci/quarantine.yml` を
      実行する新規 step が追加される (既存の `Allowlist not expired` step とは別の独立 step)。
      新規 step は `policy` job 内・`Upload policy evidence` step より前に位置する
      (アップロードされる evidence に含まれる実行順序)。
- [ ] **Must-5 (kit-manifest 再生成)**:
      Must-2 のテンプレート修正後、`dot_claude/skills/agent-policy-kit/kit-manifest.yml` が
      `scripts/kit-manifest-update.sh` で再生成され、(a) `kit_version` は `"1.1.0"` のまま
      不変、(b) `verify-allowlist-expiry.sh` エントリの `sha256` のみが更新前の値
      (`dc126ee9c774a209aaee786ceb5785fdb90f60b43bc23dc08fe4e86481732709`) と異なる新しい値に
      変わり、(c) 他の全エントリ (12 本) の `sha256` は不変。
- [ ] **Must-6 (TDD: gates: フィクスチャ + テストケース追加)**:
      `tests/fixtures/` に `gates:` エントリ入りの quarantine yml を 3 種
      (valid / expired / missing-fields のセマンティクスをそれぞれ表す) 追加し、
      `tests/run-shell-tests.sh` にそれぞれに対応するテストケース (計 3 件以上) を追加する。
      既存の 2 件 (`quarantine_valid.yml` / `quarantine_expired.yml`, 共に `entries:` のみで
      `gates:` を持たない) のテストケースは変更なしで通り続ける (exit code 不変:
      valid → 0 / expired → 1)。

## Should (望ましいが必須でない)
- waiver エントリの `gate` 値は、対象ゲートを起動する実際のスクリプトパス/コマンド名
  (例 `full-e2e-gate` や `bash scripts/xxx.sh`) と文字列一致させ、spec-grader /
  done-evaluator が機械的に照合しやすくする。
- `spec-review.json` / `done-eval.json` の waiver 参照フィールドに、適用した `gates:` エントリの
  `evidence_url` と `substitute_verification` の実行証跡パス (`.agent-evidence/` 内) の両方を
  含める。
- `verify-allowlist-expiry.sh` の gates: violation メッセージに、欠落しているフィールド名
  (`evidence_url` / `substitute_verification` / `approved_by` / `expires_at`) を個別に列挙し、
  棚卸し担当者が一目で対応できるようにする。

## 受入条件 (acceptance — Must の確認方法)
- Must-1 →
  `grep -q '^gates: \[\]' dot_claude/skills/agent-policy-kit/templates/quarantine.yml` と
  `grep -q '^gates: \[\]' ci/quarantine.yml` の両方が exit 0。かつ両ファイルから
  `- gate:` を含むスキーマコメント行以降 7 行 (`evidence_url` / `substitute_verification` /
  `owner` / `expires_at` / `approved_by` / `approved_at`) を抽出し `diff` した結果が空
  (フィールド名・順序が完全一致)。
- Must-2 →
  `bash scripts/verify-allowlist-expiry.sh --quarantine tests/fixtures/quarantine_gates_valid.yml`
  が exit 0、`--quarantine tests/fixtures/quarantine_gates_expired.yml` と
  `--quarantine tests/fixtures/quarantine_gates_missing_fields.yml` が共に非 0 exit。
  加えて既存回帰:
  `bash scripts/verify-allowlist-expiry.sh --quarantine tests/fixtures/quarantine_valid.yml` が
  exit 0、`--quarantine tests/fixtures/quarantine_expired.yml` が非 0 exit (Must-6 導入前と
  同じ結果)。加えて `diff dot_claude/skills/agent-policy-kit/templates/scripts/executable_verify-allowlist-expiry.sh scripts/verify-allowlist-expiry.sh`
  (shebang/`KIT_VERSION` 行を除く本体) が空 (テンプレートと vendored コピーが同期済み)。
- Must-3 →
  `grep -q waiver dot_claude/agents/spec-grader.md && grep -q waiver dot_claude/agents/done-evaluator.md`、
  `grep -q substitute_verification dot_claude/agents/spec-grader.md && grep -q substitute_verification dot_claude/agents/done-evaluator.md`、
  `grep -q expires_at dot_claude/agents/spec-grader.md && grep -q expires_at dot_claude/agents/done-evaluator.md`
  の 3 コマンド全てが exit 0。加えて両ファイルの ```` ```json ```` Output フェンス内に
  `waiver` を含むキーが存在する
  (`sed -n '/```json/,/```/p' dot_claude/agents/spec-grader.md | grep -q '"waiver' ` および
  done-evaluator.md 側も同様に exit 0)。
- Must-4 →
  `grep -n "verify-allowlist-expiry.sh --quarantine ci/quarantine.yml" dot_claude/skills/agent-policy-kit/templates/pr-gate.yml.tmpl.literal`
  がヒットし、そのヒット行番号が `grep -n "Upload policy evidence" dot_claude/skills/agent-policy-kit/templates/pr-gate.yml.tmpl.literal`
  の (`policy` job 内の) 行番号より小さい。
- Must-5 →
  `grep '^kit_version:' dot_claude/skills/agent-policy-kit/kit-manifest.yml` が
  `kit_version: "1.1.0"` を返す。`bash scripts/kit-sync-check.sh --self` と
  `bash scripts/kit-sync-check.sh --check` が共に exit 0 (manifest ⇔ template ⇔ 本 repo
  vendored コピーの三者が完全一致)。かつ `git diff` で
  `dot_claude/skills/agent-policy-kit/kit-manifest.yml` の変更行が
  `verify-allowlist-expiry.sh:` エントリの `sha256:` 行のみであること (他 12 エントリと
  `kit_version:` 行に diff が無い)。
- Must-6 →
  `test -f tests/fixtures/quarantine_gates_valid.yml && test -f tests/fixtures/quarantine_gates_expired.yml && test -f tests/fixtures/quarantine_gates_missing_fields.yml`
  が exit 0。`bash tests/run-shell-tests.sh` が exit 0 (新規 3 ケース + 既存 2 ケース全て pass)。
  かつ `grep -c "quarantine gates" tests/run-shell-tests.sh` (追加した新規テストケースの
  識別文字列、または同義の一意な文字列) が 3 以上。

## Non-goals (今回やらない)
- `ci/allowlist.yml` (test double 例外) 側のスキーマ変更。waiver は `ci/quarantine.yml` の
  `gates:` のみが対象。
- ゲートの **自動 waiver 発行**。`approved_by` / `approved_at` は常に人間が手で記入する
  (spec-grader / done-evaluator / 他のどの agent も waiver エントリを自動生成・自動承認しない)。
- 5 消費 repo (alpha-mind / am-wt-auditlog / native-trace / recall-paper /
  cloudflare-workers-hs) の実際に scaffold 済みの `.github/workflows/pr-gate.yml` への rollout。
  本 spec は dotfiles 側テンプレート (`templates/pr-gate.yml.tmpl.literal`) と本 repo の
  dogfood 適用 (vendored `scripts/verify-allowlist-expiry.sh` の sync) までを対象とする。
- `pr-gate.yml.tmpl.literal` の Must-4 で述べた quarantine expiry step 追加以外の変更
  (他 job の追加・既存 step の書き換え等)。

## Risk
- level: high-risk
- escalate_to_opus: true
- 理由:
  - **config**: `ci/quarantine.yml` のスキーマ拡張と、`pr-gate.yml` テンプレートへの新規
    required step 追加という、CI ゲート構成そのものを変更する。
  - **public export**: `dot_claude/skills/agent-policy-kit/templates/**` は 5 消費 repo に
    配布される kit の公開契約であり、awk / schema のバグは複数 repo の merge gate に
    静かに波及しうる (agent-policy-kit-sync spec と同種の blast radius)。
  - **schema**: `gates:` エントリのフィールド名は spec-grader / done-evaluator が直接パースする
    契約であり、フィールド名の drift は waiver 判定の誤動作 (本来 blocking であるべき FAIL を
    誤って非 blocking にする false-negative) に直結する。
  - Must-3 の変更は「ゲート FAIL を blocking にしない」という **緩和方向** の判定ロジック変更
    であるため、実装ミスの影響は「壊れた変更が done と誤判定される」という最も重大な失敗
    モードに直結する。
  - 参考: config + public export + schema の 3 領域に跨るため、2-lane router の block 条件
    (`high-risk AND boundary_touched=multi`) に該当する可能性が高い。実装着手前に
    orchestrator が Step 1.5 でレーン判定 (block/heavy) を行うこと。

## Open questions (あれば)
- なし (grill-me で schema フィールド・検証対象・Non-goal は確定済み)。
