# Spec: agent-policy-kit-sync

<!-- spec-curator が /grill-me 合意 (2026-07-02) から正規化。 -->

## Goal
- agent-policy-kit が scaffold する `scripts/verify-*.sh` の消費 repo コピーは維持したまま、
  「配布後ドリフト」を **検知可能・機械的に解消可能** にする。
- 具体的には (1) テンプレートスクリプトへの `KIT_VERSION` 埋め込みとバージョン manifest、
  (2) kit への sync モード (Detect→Diff→Apply、dry-run default)、
  (3) `proven-done` Step 0 の前提チェック拡張、(4) 「テンプレート先修正・コピー直修正禁止」の
  メタルール明文化、(5) 実測済みドリフト (verify-failure-class.sh 未配備 5 repo /
  verify-wiring.sh 3 世代分岐 / working-tree blind spot 3 repo) の解消、を実現する。
- 実行方式は **中央実行への切替ではなく vendored コピー + sync**
  (CI (`pr-gate.yml`) が repo 内スクリプトを直接叩く前提を崩さない)。

## Must (満たさなければ done でない)
- [ ] **Must-1 (KIT_VERSION 埋め込み)**: `dot_claude/skills/agent-policy-kit/templates/scripts/executable_*.sh`
      の全ファイル (8 本: agent-policy-hook / agent-evidence-gate / verify-no-prod-doubles /
      verify-test-bypass / verify-wiring / verify-no-stub-placeholder / verify-allowlist-expiry /
      verify-failure-class) が `# KIT_VERSION: <semver>` 行 (shebang 直後) を含み、かつ
      `dot_claude/skills/agent-policy-kit/templates/scripts/KIT_VERSIONS.yml` に
      同ディレクトリの各スクリプトファイル名 → semver のエントリが存在し、
      埋め込み値と manifest の値が完全一致する。
- [ ] **Must-2 (sync モード)**: `dot_claude/skills/agent-policy-kit/SKILL.md` に既存の
      Detect→Diff→Apply 3 phase 流儀に従う sync 手順が明文化され、以下を全て満たす:
      (a) 消費 repo 側 `scripts/verify-*.sh` の現行 `KIT_VERSION` とテンプレート最新版を比較して
      diff を提示する、(b) **既定は dry-run** (提示のみで書込まない)、
      (c) 書込はユーザーの明示承認後にのみ実行する。
- [ ] **Must-3 (proven-done Step 0 拡張)**: `dot_claude/skills/proven-done/SKILL.md` の
      Step 0 前提チェックが、現状の `verify-no-prod-doubles.sh` 単体存在確認から、
      6 本の verify スクリプト (verify-no-prod-doubles / verify-test-bypass / verify-wiring /
      verify-no-stub-placeholder / verify-allowlist-expiry / verify-failure-class) 全ての存在確認、
      および各スクリプトの `KIT_VERSION` が manifest の最新値と一致するか (freshness) の検査に拡張され、
      欠落または陳腐化時に警告して `agent-policy-kit` の sync 実行を促す文言を含む。
- [ ] **Must-4 (メタルール明文化)**: 「verify スクリプトの修正は必ず dotfiles テンプレートに先に入れて
      から sync で配布する。消費 repo のコピーへの直接修正は禁止」と同義の一文が、
      (a) `dot_claude/docs/agent-policy.md` (正本)、
      (b) `dot_claude/skills/agent-policy-kit/templates/AGENTS.md.tmpl.literal` (消費 repo 配布テンプレート)、
      (c) dotfiles root `AGENTS.md` (正本 (a) からの dogfood 再生成物)
      の 3 ファイル全てに存在する。(c) は (a) の再生成で得ること (root AGENTS.md を独立に手編集しない —
      これは本 spec が解消しようとしているドリフト構造と同種のため)。
- [ ] **Must-5 (5 消費 repo への配備)**: alpha-mind / am-wt-auditlog / native-trace / recall-paper /
      cloudflare-workers-hs の各 repo で、
      (a) `scripts/verify-failure-class.sh` が存在し (現状 0/5)、
      (b) `scripts/verify-wiring.sh` が working-tree blind spot 修正
      (committed diff が空のとき working-tree 変更にフォールバックする分岐。
      dotfiles 側 `templates/scripts/executable_verify-wiring.sh` の該当ロジックと同等) を含む。
- [ ] **Must-6 (版一致・ドリフト 0)**: Must-5 の sync 適用後、5 消費 repo それぞれの
      `scripts/verify-*.sh` (6 本) の `KIT_VERSION` が、dotfiles 側
      `templates/scripts/KIT_VERSIONS.yml` の対応エントリと完全一致する (30 チェック全て一致)。

## Should (望ましいが必須でない)
- sync 実行結果 (diff サマリ・適用/スキップ内訳) を証跡として残す (`.agent-evidence/` 相当、または
  sync 実行ログ)。
- `KIT_VERSION` は semver とし、変更履歴を manifest 内または CHANGELOG に記録する。
- sync diff 提示時に「テンプレート側のみの変更」か「消費 repo 側で意図的に発生した独自差分
  (incident 修正の直当て等)」かを区別するヒントを出す (recall-paper の 2026-06-13 補正 2 のような
  ケースを sync が黙って上書きしないようにする)。
- `agent-policy-hook.sh` / `agent-evidence-gate.sh` (hook 系テンプレート) にも同じ
  `KIT_VERSION` 管理を将来的に拡張できる形にしておく (本 spec の Must-3 対象は verify-*.sh のみ)。

## 受入条件 (acceptance — Must の確認方法)
- Must-1 →
  `for f in dot_claude/skills/agent-policy-kit/templates/scripts/executable_*.sh; do grep -q '^# KIT_VERSION: ' "$f" || echo "MISSING: $f"; done`
  の出力が空。かつ `dot_claude/skills/agent-policy-kit/templates/scripts/KIT_VERSIONS.yml` の
  各エントリ値と対応スクリプトの埋め込み値が (diff や jq/yq 比較で) 全一致。
- Must-2 →
  `grep -n "Sync" dot_claude/skills/agent-policy-kit/SKILL.md` がヒットし、同セクション内に
  `dry-run` の語と「承認」を要求する文言 (既存の「ユーザーが承認するまで書き込まない」と同義) の
  両方が存在する。
- Must-3 →
  `dot_claude/skills/proven-done/SKILL.md` の Step 0 節に、6 本の verify スクリプト名全てと
  `KIT_VERSION` の語が共に出現する (grep で機械判定可能)。
- Must-4 →
  `grep -q "テンプレートに先に入れてから" dot_claude/docs/agent-policy.md` /
  `grep -q "テンプレートに先に入れてから" dot_claude/skills/agent-policy-kit/templates/AGENTS.md.tmpl.literal` /
  `grep -q "テンプレートに先に入れてから" AGENTS.md`
  の 3 コマンド全てが一致行を返す (exit 0 相当)。
- Must-5 → 5 repo それぞれのローカルクローンで
  `test -f scripts/verify-failure-class.sh` (exit 0) と
  `grep -q "working-tree" scripts/verify-wiring.sh`
  (working-tree フォールバック分岐の存在を示すキーワード一致、exit 0) の 2 コマンド。
  5 repo × 2 = 10 コマンド全て exit 0。
- Must-6 → 5 repo それぞれで
  `diff <(grep '^# KIT_VERSION:' <consumer-repo>/scripts/verify-wiring.sh) <(grep '^# KIT_VERSION:' dot_claude/skills/agent-policy-kit/templates/scripts/executable_verify-wiring.sh)`
  相当を 6 スクリプト分実行し、全て差分なし (5 repo × 6 script = 30 チェック全一致)。

## Non-goals (今回やらない)
- 中央実行への切替 (verify スクリプトを消費 repo に置かず外部から呼ぶ形式)。CI (`pr-gate.yml`) が
  repo 内スクリプトを直接叩く前提と非互換のため不採用。
- git submodule / package manager (npm 等) 化によるテンプレート配布。
- `no-new-evidence` 検知の新規導入 (既存の time-budget 不変条件のスコープ外)。
- テンプレート変更の**承認なし自動 push/apply** (sync は必ず dry-run → 人間承認 → apply の順)。
- 列挙された 5 repo 以外への新規展開・新規消費 repo の発掘。
- `scripts/verify-*.sh` 以外の kit 生成物 (AGENTS.md 本体の生業ルール以外の節、ast-grep/hlint ルール、
  rubric、wiring_manifest.yml テンプレート) への sync モード対象拡張 (本 spec のスコープは
  verify-*.sh 群の版管理 + メタルール明文化に限定)。

## Risk
- level: high-risk
- escalate_to_opus: true
- 理由:
  - **config**: `KIT_VERSION` manifest と `scripts/verify-*.sh` は 5 消費 repo の CI
    (`pr-gate.yml` の決定論ゲート) が直接消費する設定物であり、sync の実装ミスは複数 repo の
    merge gate を静かに壊しうる。
  - **public export 相当**: `templates/` 配下は kit が外部 repo に配布する「公開契約」であり、
    版管理・sync ロジックの破損は 5 repo に同時波及する (変更行数は小さくても blast radius が広い)。
  - Must-5/6 は dotfiles 単体の PR では完結せず、5 つの外部 repo それぞれで sync 実行 → 承認 → apply
    が必要になる。two-lane router 上、dotfiles 側の実装 (Must-1〜4) と外部 repo への展開 (Must-5〜6)
    は **実質的に別タスク/別セッション** になる可能性が高く、1 タスクとして扱うと
    `estimated_files` が両者合算で 30 を超え block レーン相当になりうる (下記 Open questions 参照)。

## Open questions (あれば)
- **Q1 (バージョニング粒度)**: `KIT_VERSION` は 8 スクリプト共通の単一 kit バージョンを一括更新する
  方式か、スクリプトごとに独立採番する方式か。Must-3 の freshness 判定 (「manifest の最新値と一致」)
  の意味がこの選択に依存するため、実装前に人間判断が必要。
- **Q2 (sync 実行単位)**: Must-5/6 (5 repo への実配備) は、本 spec に基づく **1 回の実装タスク**として
  dotfiles 側セッションからリモート操作すべきか、それとも各消費 repo 内で `agent-policy-kit` sync を
  個別に (別タスクとして) 実行する運用か。前者なら 5 repo へのローカルアクセス手段
  (クローンパス一覧など) の確定が必要、後者なら Must-5/6 は本 spec から切り出し
  「rollout tracking」用の別 spec/issue にすべきかもしれない。
- **Q3 (「red-only版」の定義)**: 合意文中の「verify-failure-class.sh (red-only版)」が、
  現行 `templates/scripts/executable_verify-failure-class.sh` (collapsed-loop 判定を red phase
  のみでカウントする現行仕様) を指すのか、それとも green/refactor/pivot 判定分岐自体を持たない
  簡略版を別途新設する意図か、確認が必要。本 spec は前者 (現行テンプレートをそのまま配備) と
  仮定して Must-5 を書いている。
- **Q4 (manifest ファイル形式・置き場所)**: `KIT_VERSIONS.yml` というファイル名・
  `templates/scripts/` 直下という配置は spec-curator の提案であり、既存の kit 構成規約
  (テンプレートは `templates/<category>/` に置く) との整合を実装者/reviewer が確認すること。

## Amendments (2026-07-02 grill-me — 全 Open questions ユーザー承認済み)

- **Q1 決定**: kit 全体で**単一 KIT_VERSION** + manifest に **per-file sha256** の二層構造。
  freshness 判定 = KIT_VERSION 一致、改変・陸列検知 = sha256。
- **Q2 決定 (spec 分割)**: block レーン判定 (high-risk × 境界跨ぎ) に従い分割する。
  - **Task A = Must-1〜4** (dotfiles 内完結): 本 spec の実装対象。/proven-done heavy レーンで dogfood。
    verify-wiring.sh の **best-of 合流** (recall-paper 版の「BASE_REF 明示時は working-tree を見ない」
    + dotfiles 版の「untracked も見る」を意味論検証の上テンプレートに統合) も Task A に含む。
  - **Task B = Must-5〜6** (5 消費 repo への rollout): 別タスクに切り出し。各 repo で
    dry-run → ユーザー承認 → apply の対話型作業。Task A 完了が前提。
- **Q3 決定**: 「red-only 版」= 現行 `templates/scripts/executable_verify-failure-class.sh`
  (2026-07-02 修正済み: phase 必須 / failure_class は red のみ必須・green/refactor 禁止・pivot 任意 /
  collapsed loop は末尾 3 red で判定)。簡略版の新設はしない。
- **Q4 決定**: manifest は kit 直下 `dot_claude/skills/agent-policy-kit/kit-manifest.yml`
  (単一 KIT_VERSION + per-file sha256)。
