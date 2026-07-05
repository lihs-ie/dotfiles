# Spec: harness-campaign-fix2-6

<!-- spec-curator が 2026-07-05 proven-done bottleneck audit (実測 6 件) の残り 5 fix を正規化。
     Fix-1 (guard-evasion-gates) は PR #15 で merge 済み — 本 spec は Fix-2..6 のみを対象とする。
     kickoff authority はユーザーの明示指示 (「全部まとめて」) が既に `.agent-evidence/commands.txt`
     に記録済み。詳細は末尾 `## Amendments` 参照。style/granularity の参照元は
     `docs/specs/guard-evasion-gates.md` (Amendments/Work packets 節を含め踏襲)。 -->

## Goal
- proven-done ハーネスの実測ボトルネック 5 件 (subagent stall放置 / kit-sync-check配布断絶 /
  SKILL-corpus内部矛盾 / environment非互換) を、決定論スクリプト・SKILL.md・agent 定義・
  kit テンプレートの正本編集として解消する。
- 各 fix は canonical-first (`dot_claude/skills/agent-policy-kit/templates/scripts/` を正本として
  先に直し、`kit-manifest-update.sh` で manifest 再生成、`kit-sync-check.sh` で自己整合を確認) を守る。
- 5 fix を **1 つの heavy レーン task 内の packet ループ** (P-A/P-B/P-C/P-D/P-E) として実装し、
  `kit_version` の単一バンプ (1.2.0→1.3.0) を最終 packet (P-E) でのみ行う (Fix-1 の 3-packet 先例
  (P12/P3/P4) と同型)。

## Must (満たさなければ done でない)

### Fix-2: subagent stall liveness + budget-resume protocol (P-A)

- [ ] **Must-1 (budget-resume grant 機構)**: `scripts/agent-time-budget.sh` の PreToolUse deny 経路
      (ratio≥1.0) が発火した時点で、hook-private state (`$state_dir_root/<repo-key>/`) に
      **`<task>.resume-grant.pending`** ファイルを書く (existing `<task>.json` private コピーと同じ
      ディレクトリ、リポジトリ working tree の外側)。
      (a) `resume-grant.pending` の内容は `{"task": "<task>", "private_started_at": "<現在の private
          started_at>", "lane": "<lane>", "requested_at": "<ISO8601 UTC>"}`。
      (b) **正当な承認経路は 2 つ (いずれか)**: (i) 人間が `resume-grant.pending` を
          `resume-grant.approved` に **rename/copy** する、(ii) `AskUserQuestion` で人間の承認を得て
          その応答が `.agent-evidence/commands.txt` に記録される (承認記録後、実装/hook 側は
          `resume-grant.approved` を書く)。どちらの経路も **人間の能動的行為を必須**とし、
          hook・orchestrator が自発的に `.approved` を作ってはならない。
      (c) `resume-grant.approved` が存在し、かつその **mtime が `.active` の次回 `started_at`
          再スタンプより前** であることを hook が確認できた場合に限り、**1 回だけ** private コピーの
          `started_at` の再スタンプ (resume) を許可する。再スタンプ適用と同時に `resume-grant.approved`
          を **消費 (削除または `.consumed` にリネーム)** し、以後同じ grant の再利用を拒否する
          (single-use)。
      (d) **self-granting 検出可能性**: `resume-grant.approved` の mtime が `.active` の
          `started_at` 再スタンプ (書込) の **後** である場合 (= 承認より前に再スタンプが起きた =
          orchestrator が先に自分で再スタンプしてから体裁を整えるために grant を後付けした疑い) は
          tamper 同様に **拒否**し (private の古い `started_at` を採用し続ける)、その旨を deny
          メッセージに明記する。この順序検査 (grant が re-stamp に先行する) が
          self-granting 検出の唯一の機械的根拠であり、fixture で両順序を明示的に区別する。
      (e) 上記いずれの grant も無い通常の deny (既存 Must-5 動作) は無変更 (回帰なし)。

- [ ] **Must-2 (SKILL.md stall 検出プロトコル)**: `dot_claude/skills/proven-done/SKILL.md` に
      subagent stall の定義と対応を明文化する。
      (a) **stall の定義**: 次のいずれかが起きた場合を stall とする — (i) subagent (implementer 等)
          の完了報告に Write/Edit/Bash の tool call 証跡が**ゼロ**、かつ orchestrator の `ls`
          実在確認でも**新規ファイルが確認できない** (Step 2.7 の書込プローブと同じ「自己申告を
          信用せず ls で確認する」原則を stall 判定にも適用する)。 (ii) `SendMessage` がエラーを
          返す、または応答が一切無い。
      (b) **2 回連続 stall で 3 回目の spawn をしない**: 同一 packet (packet 未採用時は同一 task の
          Step 3 試行) で stall が **2 回連続**発生したら、`.agent-evidence/resume-packet.md`
          (packet contract = 対象 `musts`/`target_files`/`done_when` + それまでの checkpoint
          findings) を書き、**STOP して人間にエスカレーション**する。3 回目の fresh 起動は行わない
          (E2 incident で 6 連続 stall が起きた反省 — 無限リトライを構造で止める)。
      (c) work-packets.json 採用時は、Step 3 packet ループの機械判定表 (既存 `fail-x2` /
          `agent-dead` / `collapsed-loop` / `packet-over-budget`) に新しい `reason_code`
          **`stall-x2`** を追加する: 条件 = 「同一 `packet_id` で stall (上記 (a)) が 2 回連続」、
          `continuation_decision` = **`escalate`** (`fresh` ではない — 3 回目 spawn をしないため)、
          対応 = `.agent-evidence/resume-packet.md` を書いて STOP。
      (d) packet 未採用 (単発 Step 3) でも同じ stall 定義・2 回連続 STOP ルールを適用する
          (E2 incident は heavy 単発想定でも起こりうるため、packet ループに限定しない)。

- [ ] **Must-3 (grant lifecycle + stall のテスト)**: `tests/run-shell-tests.sh` に Must-1 の grant
      lifecycle (pending 発行 / 承認後 1 回のみ再スタンプ / 消費後の再利用拒否 / self-granting 順序
      検出) を最低 4 ケース、Must-2 の stall 定義相当のテスト (ls 実在確認ベースの判定を模す
      fixture) を最低 1 ケース追加する。

### Fix-3: kit-sync-check DOA repair (P-B)

- [ ] **Must-4 (manifest fallback chain + stripped-name 解決)**: `scripts/kit-sync-check.sh`
      (および正本 `dot_claude/skills/agent-policy-kit/templates/scripts/executable_kit-sync-check.sh`)
      の manifest 解決を次の優先順位に変更する (現状は `dot_claude/skills/agent-policy-kit/kit-manifest.yml`
      の単一ハードコード default のみ — `scripts/kit-sync-check.sh:46` で確認済み):
      (a) 明示 `--manifest <path>` (最優先、現状維持)。
      (b) repo-relative `dot_claude/skills/agent-policy-kit/kit-manifest.yml` (存在すれば)。
      (c) `$HOME/.claude/skills/agent-policy-kit/kit-manifest.yml` (deployed layout — consumer repo
          に `dot_claude/` が無い場合のフォールバック)。
      (d) **stripped-name テンプレート解決** (`--self` モードの `check_path="$manifest_dir/$tmpl"`
          解決に適用): manifest の `template:` フィールドはソース形式 (`executable_` prefix 付き、
          例 `templates/scripts/executable_kit-sync-check.sh`) だが、chezmoi は `executable_`
          prefix のファイルを **prefix を落として** deploy する (dotfiles 全体の chezmoi 規約)。
          よって `$manifest_dir/$tmpl` が存在しなければ、同じディレクトリで `executable_` を
          basename から取り除いた path (`$manifest_dir/$(dirname "$tmpl")/$(basename "$tmpl" | sed
          's/^executable_//')`) を試す。両方とも存在しなければ現行通り missing 扱い。

- [ ] **Must-5 (proven-done SKILL.md Step 0 — 必須化 + exit 1 挙動定義)**:
      `dot_claude/skills/proven-done/SKILL.md` Step 0 (3.) を次のように更新する
      (現状は 6 本の verify スクリプトのみを「欠落なら scaffold 案内」の対象とし、
      `kit-sync-check.sh` は「自体が無ければ freshness 検査を skip し、その旨を警告する」という
      soft-skip 扱いになっている — これが 3/4 消費 repo で kit-sync-check.sh 欠落が放置された
      直接原因):
      (a) 存在確認対象を 6 本から **7 本 (`kit-sync-check.sh` を追加)** にする。7 本のいずれか欠落でも
          「先に `agent-policy-kit` skill でガードを scaffold してください」を案内し、ユーザー承認の
          上で再適用してから続行する (kit-sync-check.sh 欠落は他 6 本と同格の blocking 扱いに昇格)。
      (b) `kit-sync-check.sh --check` の exit code 別挙動を明文化する: exit 0 = fresh (続行) /
          exit 2 (陳腐化) = 警告して sync 実行を促すが続行 (現状維持) / **exit 1 (manifest が
          Must-4 のフォールバック全経路を試しても見つからない) = 警告して freshness 検査を skip し
          続行、ただしサイレントにしない** (stderr の内容を Step 10 の報告にも残す)。
      (c) (a) の 7 本必須化により、exit 1 は「スクリプト自体は存在するが manifest が本当にどこにも
          無い」場合にのみ発生しうる稀なケースになる (通常は $HOME フォールバックで manifest が
          見つかる)。

- [ ] **Must-6 (agent-policy-kit SKILL.md — 必須 scaffold 集合への編入)**:
      `dot_claude/skills/agent-policy-kit/SKILL.md` の Phase 2 の `scripts/:` コピー対象一覧
      (SKILL.md:31-34) は既に `kit-sync-check.sh` を含んでいるが、Phase 3 の smoke test
      (3a/3b/3c、SKILL.md:93-98) には `kit-sync-check.sh` **自身の存在確認**に相当する
      smoke check が無い (3c は `kit-sync-check.sh --check` を実行するだけで、スクリプト不在を
      別途検出しない)。Phase 3 に **3d** を追加し、`test -x scripts/kit-sync-check.sh` (または
      `-f` + 実行権限) を明示的に確認するステップとする (他の verify-*.sh と同格の「必須」であることを
      Apply 手順自体で担保する)。

- [ ] **Must-7 (テスト: consumer-repo simulation fixture)**: `tests/run-shell-tests.sh` に、
      cwd に `dot_claude/` が無く (consumer repo を模す)、`$HOME` を override したシナリオで、
      override 先に **deployed layout** (`$FAKE_HOME/.claude/skills/agent-policy-kit/kit-manifest.yml`
      + `$FAKE_HOME/.claude/skills/agent-policy-kit/templates/scripts/<stripped-name>.sh` ―
      `executable_` prefix 無し) を配置した fixture を追加する。この fixture に対し
      `kit-sync-check.sh --check` (target-dir に manifest の sha256 と一致する vendored コピーを
      用意) と `kit-sync-check.sh --self` (Must-4(d) の stripped-name 解決を経由) の **両方**が
      `HOME=$FAKE_HOME` 環境下で **exit 0** になることを確認する。

### Fix-4+6: SKILL/corpus consolidation (P-C, 同一 packet)

- [ ] **Must-8 (Light lane fast path — 一覧セクション新設)**: `dot_claude/skills/proven-done/SKILL.md`
      の冒頭付近 (前提チェック直後) に「Light lane fast path」節を新設し、light レーンで実行される
      Step を 1 画面で列挙する: **0 → 1 → 1.5 → 2.7 → 3 → 3.5 → 4 → [6 if entrypoint] → 8 → 9 → 10**
      (Step 2/2.5 は heavy-only、Step 5/7 は light で skip — 既存 Step 1.5 の除外規定から導出される
      実際のシーケンスを、読者が除外規定から逆算せずに読めるようにする)。

- [ ] **Must-9 (2 つの実証済み deviation の明文化)**: 2026-07-05 dogfood 走行
      (`incidents/2026-07-05-guard-evasion-dogfood-findings.md` 付記) で done-eval が許容した
      2 つの deviation を SKILL.md に codify する:
      (a) Step 5〜7 (static-verifier / runtime-verifier / spec-grader) は **read-only** かつ各々の
          起動前後で `tree_stamp` が一致する限り **並列起動してよい** (既存の「verifier tree 変異
          ガード」ブロックに追記)。
      (b) work-packets.json 採用時、**最終 packet** (depends_on で他 packet から参照されない末尾
          packet) の checkpoint (static-verifier checkpoint モード呼び出し) は、直後に Step 3(d) の
          フル battery (Step 4〜8) が上位互換で走ることを理由に **省略してよい** (必須ではない —
          省略する場合は `commands.txt` に「checkpoint-<packet_id> folded into full battery」と
          明記する)。

- [ ] **Must-10 (verifier-mutation guard の拡張 — Finding 2)**: 既存の「verifier tree 変異ガード」
      ブロック (SKILL.md Step 4 直後) に、「**orchestrator も、いずれかの verifier が走行中は
      tree・evidence を変異させない**」を追記する (2026-07-05 dogfood Finding 2: orchestrator が
      static-verifier 並走中に `completion-report.md` の status header を sed で書き換え、
      static-verifier が 3-byte 差分の race を検出した事故)。tree_stamp が `.agent-evidence/` を
      含まないため既存 stamp 比較では検出できない盲点である旨も明記する。

- [ ] **Must-11 (agent-policy.md §10 collapsed-loop 定義の整合)**: `dot_claude/docs/agent-policy.md`
      §10 の「自動エスカレーション条件: collapsed loop (末尾3ラウンド同一class)」を、実際の
      `verify-failure-class.sh` の挙動および SKILL.md/implementer.md の定義 (**末尾3 red のみ**
      (green/refactor/pivot は窓に数えない) **かつ同一 `target_test`**) に一致させる (現状の
      §10 は stale — `red` 限定と `target_test` 一致条件を欠く)。

- [ ] **Must-12 (「collapsed loop」用語衝突の解消)**: script が検出する exit-2 シグナル
      (`verify-failure-class.sh`、末尾3 red・同一 failure_class・同一 target_test) にのみ
      「collapsed loop」の呼称を残し、**レビュー 2 周連続で同一指摘が残る**別概念には新呼称
      **「review-loop stall」**を与えて置き換える。対象箇所 (3 箇所、全て確認済み):
      (a) `dot_claude/docs/agent-policy.md` §5 「同一指摘が2周連続 (collapsed loop) なら人間に
          エスカレーション」。
      (b) `dot_claude/skills/proven-done/SKILL.md` Step 9「同一指摘が2周連続 (collapsed loop) なら
          人間にエスカレーション」。
      (c) `dot_claude/agents/done-evaluator.md` 判定原則「同じ未達理由が2周連続で残る (collapsed
          loop) なら `escalate_to_human: true`」。

- [ ] **Must-13 (agent-policy.md §2.5 light row の skip 注記)**: `dot_claude/docs/agent-policy.md`
      §2.5 の two-lane router 表の light 行「対応」列が現状 heavy 行と同じ「Step 2 へ通常進行」に
      なっている (SKILL.md 側は表の下の散文で topology-mapper/static-verifier/spec-grader の skip を
      補足しているが、agent-policy.md 側にはこの補足が無い)。light 行に
      「topology-mapper/static-verifier/spec-grader を skip、runtime-verifier は entrypoint touch
      時のみ」を追記し、SKILL.md との内容一致を回復する。

- [ ] **Must-14 (spec-curator opus column の削除)**: spec-curator は自身が high-risk フラグを
      **生成する側**であり、生成前の自分自身をそのフラグで昇格させることはできない (self-escalation
      不能)。次 2 箇所の spec-curator 行の「high-risk 時」列 (現状 `opus`) を、
      「(生成前のため適用不可 — 常に Sonnet)」に置き換える:
      (a) `dot_claude/skills/proven-done/SKILL.md` パイプライン表 (Step 1 Spec 行)。
      (b) `dot_claude/docs/agent-policy.md` §7 役割表 (仕様化/spec-curator 行)。

- [ ] **Must-15 (SKILL.md の重複 failure_class enum/exit code 削除 + 不変条件圧縮)**:
      `dot_claude/skills/proven-done/SKILL.md` の「iterations.json スキーマ」節で「スキーマ正本は
      implementer.md §iterations.json … ここに複製は置かない」と明言していながら、直後に
      `failure_class` enum (5 値) と `verify-failure-class.sh` の exit code 説明を丸ごと複製している
      (現状ファイル中の該当ブロック — enum 列挙 + exit 1/exit 2 説明)。この複製ブロックを削除し
      「enum と exit code の正本は `implementer.md` §iterations.json および
      `agent-policy.md` §10 を参照」の 1 行ポインタに置き換える。同様に「不変条件」節のうち
      failure_class enum / collapsed loop の詳細再説明になっている箇条書きも、正本参照ポインタに
      圧縮する (時間budget/フレーキー隔離など他の不変条件は圧縮しない)。

- [ ] **Must-16 (Step 3.5 item 3 の自己矛盾解消)**: SKILL.md Step 3.5 の item 3「各 `wired_at` が
      実在の本番呼び出しか grep で抜き取り確認する」は、同ファイル「不変条件」節の「orchestrator の
      手動 grep を当てにしない」と文字通り矛盾する。item 3 を「この確認は `runtime-verifier`
      (Step 6、手順4: `wiring-map.json` の `wired_at` を Grep で裏取り) が担う — orchestrator が
      自ら grep で代替確認しない」という **runtime-verifier.md への参照**に書き換える。

- [ ] **Must-17 (A5 boilerplate — 4 verifier agent への追記)**: 2026-07-05 dogfood 走行で
      static-verifier に対し「header=complete を Step 5 時点で要求」する誤指定があり false-FAIL が
      1 周発生した (Finding 記載の付記)。次 4 ファイルすべてに、`agent-evidence-gate.sh` の
      Amendment A5 semantics を要約する定型句を追加する:
      「`completion-report.md` の `status: complete` は `round-<N>/done-eval.json` が存在して
      初めて正当となる。Step 8 以前 (Step 5/6/7 時点) に `complete` を要求してはならない。」
      (a) `dot_claude/agents/static-verifier.md`
      (b) `dot_claude/agents/runtime-verifier.md`
      (c) `dot_claude/agents/spec-grader.md`
      (d) `dot_claude/agents/done-evaluator.md`

- [ ] **Must-18 (orchestrator-direct-implementation を blocking hook に昇格)**: 2026-07-02
      (`background-subagent-write-reliability.md` 追記「実装2体+orchestrator代筆の三者並行編集」)、
      2026-07-02 (`verifier-tree-mutation.md`)、2026-07-05 (Finding 2 concurrent-edit race) の
      3 件の実測 incident が、orchestrator が implementer に委譲せず自ら本番コード/証跡を編集する
      failure mode を documented (prose-only) rule として既に指摘済みだが、機械的な hook 検出は
      まだ存在しない (`scripts/agent-policy-hook.sh` を確認済み — 現状は no-prod-doubles/
      test-bypass の per-edit チェックのみで、orchestrator 属性の判別ロジックは無い)。
      `agent-policy.md` §6 昇格しきい値表の「false negative のコストが高い → CI gate / hook へ昇格」
      に基づき、3 件目の occurrence を根拠に **新規 blocking (exit 2) チェック**を追加する:
      (a) `scripts/agent-policy-hook.sh` (と正本 `executable_agent-policy-hook.sh`) に、
          `.agent-evidence/.active` が存在し (proven-done 実行中) かつ編集対象ファイルが本番パス
          (既存 `verify-no-prod-doubles.sh` と同じ test 系ディレクトリ除外規約) である場合の
          orchestrator-direct-implementation 検出ロジックを追加する。**検出に用いる具体的な
          discriminator (orchestrator 発行の tool call と subagent 発行の tool call を区別する
          hook payload 上のフィールド) は実装時に確認・確定し、`commands.txt` に採用した signal と
          その根拠を明記する** (下記 Open questions Q1 参照 — 本 Must は「機構を追加すること」を
          必須とし、discriminator の具体設計は implementer 裁量に委ねる)。
      (b) 違反検出時は exit 2 でブロックし、`ci/allowlist.yml` に `rule: orchestrator-direct-implementation`
          (owner/reason/expires_at 付き) のエントリで escape できることを既存 `no-prod-doubles`
          ルールと同じパターンで実装・文書化する。

### Fix-5: environment portability (P-D)

- [ ] **Must-19 (portable.sh テンプレート新設)**: `dot_claude/skills/agent-policy-kit/templates/scripts/executable_portable.sh`
      を新設し (canonical-first)、次 2 関数を提供する:
      (a) `portable_timeout <seconds> <cmd...>` — `gtimeout` (GNU coreutils on macOS) → `timeout`
          → perl `alarm` ベースの fallback、の優先順で解決する。
      (b) `portable_http_probe <url>` — `curl` → `wget` → `python3 -c 'urllib...'` の優先順で
          解決する。
      対応する repo-local `scripts/portable.sh` (kit sync 経由の vendored コピー) を追加する。

- [ ] **Must-20 (runtime-verifier.md — portable helper 使用指示)**: `dot_claude/agents/runtime-verifier.md`
      に、smoke/probe 実行時は `portable_timeout`/`portable_http_probe` (`scripts/portable.sh`
      を source して使う) を使い、**裸の `timeout`/`curl` を直接呼ばない**ことを明記する
      (native-trace (~14 回) / alpha-mind で `timeout`/`curl` command-not-found により
      runtime-verifier probe が壊れた実測障害への対処)。

- [ ] **Must-21 (spec-curator.md — lane-capability rule)**: `dot_claude/agents/spec-curator.md` に、
      受入条件のコマンドは **実行可能な lane を名指しする**ルールを追加する: keychain / entitlement
      に依存する挙動 (シミュレータ/CLI からは検証不能) は、app-hosted lane (実機/実 app 起動を伴う
      lane) に割り当てることを spec の受入条件自体に明記しなければならない、とする
      (2026-07-03 incident 相当の firebaseauth-hostless-test-keychain 障害 — 消費 repo 側の
      incident であり本 dotfiles repo には incident ファイルが無いため、外部提供エビデンスとして
      引用する)。

- [ ] **Must-22 (portable helper のテスト)**: `tests/run-shell-tests.sh` に `portable_timeout`/
      `portable_http_probe` それぞれ最低 1 ケース (優先コマンドが無い環境を模した fixture で
      fallback 経路が機能することを確認) を追加する。

### 全 fix 共通 (P-E)

- [ ] **Must-23 (canonical-first + kit_version 単一バンプ)**:
      (a) P-A〜P-D で編集/新設した各テンプレート (`executable_agent-time-budget.sh` /
          `executable_kit-sync-check.sh` / `executable_agent-policy-hook.sh` (新設)
          `executable_portable.sh`) は、P-A〜P-D の時点では **`# KIT_VERSION:` 行を 1.2.0 のまま
          変更しない** (`kit-manifest-update.sh` が全テンプレート間で単一 KIT_VERSION を要求するため
          — `scripts/kit-manifest-update.sh:60-65` で確認済み)。P-E で **全 16 テンプレート**
          (既存 15 本 + 新設 `executable_portable.sh`) の `# KIT_VERSION:` 行を一括で `1.3.0` に
          揃えてから `bash scripts/kit-manifest-update.sh` を **1 回だけ**実行する。
      (b) `kit-manifest.yml` の `kit_version` が `1.2.0` から `1.3.0` へ変わり、`files:` エントリ
          総数が 15→16 になることを、値の直接比較 + `^  [A-Za-z0-9_.-]*\.sh:` 行数の `-eq 16`
          assertion で確認する (`docs/specs/guard-evasion-gates.md` Must-7(b) の falsifiable
          style を踏襲)。
      (c) 対応する repo-local `scripts/agent-time-budget.sh` / `scripts/kit-sync-check.sh` /
          `scripts/agent-policy-hook.sh` / `scripts/portable.sh` (新規) が、テンプレートとバイト
          一致する (`bash scripts/kit-sync-check.sh --self` と `--check` の両方が exit 0)。
      (d) `dot_claude/skills/agent-policy-kit/SKILL.md` の Phase 2 scaffold コピー対象一覧に
          `portable.sh` を追加する。

- [ ] **Must-24 (最終フル回帰 + AGENTS.md 整合確認)**: `bash tests/run-shell-tests.sh` が
      P-A〜P-E の全追加ケースを含めて **fail 0** で終了する。加えて `dot_claude/docs/agent-policy.md`
      (正本) の今回変更点 (§2.5/§5/§6/§7/§10) が root `AGENTS.md` に未反映であること
      (kit 再適用まで自動反映されない既知の drift — Fix-1 と同型) を完了報告の残リスクに明記する。

## Should (望ましいが必須でない)

- Must-1 の `resume-grant.pending`/`.approved` は `.active` 削除 (Step 10) と同時にディスク肥大防止の
  クリーンアップ対象に含める (guard-evasion-gates.md Should の private コピークリーンアップと同様)。
- Must-18 の orchestrator-direct-implementation 検出ロジックが定まったら、`POLICY VIOLATION`
  メッセージにどの signal で検出したかを 1 行で明示する (診断可読性)。
- Fix-5 の `portable_http_probe` は将来的に HTTP メソッド/ヘッダ指定にも対応させる (v1 は GET 専用の
  疎通確認で十分)。

## 受入条件 (acceptance — Must の確認方法)

- Must-1 →
  ```
  # (a)(b) pending 発行 + 人間承認後の 1 回のみ再スタンプ + 消費後の再利用拒否
  bash scripts/agent-time-budget.sh --evidence-dir <deny帯 fixture> --state-dir <scratch> <<< '{"hook_event_name":"PreToolUse", ...}'
  test -f <scratch>/<repo-key>/<task>.resume-grant.pending
  # 人間承認を模す: mv <scratch>/.../<task>.resume-grant.pending <scratch>/.../<task>.resume-grant.approved
  bash scripts/agent-time-budget.sh --evidence-dir <再スタンプ済み .active fixture> --state-dir <scratch> <<< '{"hook_event_name":"PreToolUse", ...}'
  test $? -eq 0   # 1回目の resume は許可される
  test ! -f <scratch>/.../<task>.resume-grant.approved   # 消費済み (single-use)
  # 同じ .approved を再利用しようとしても (既に削除済みのため) tamper 扱いに戻る
  bash scripts/agent-time-budget.sh --evidence-dir <再度書き換えた .active fixture> --state-dir <scratch> <<< '{"hook_event_name":"PreToolUse", ...}'
  test $? -eq 2

  # (d) self-granting 順序検出: .approved の mtime が re-stamp 書込より後 (= 後付け) の fixture
  #     は拒否される
  bash scripts/agent-time-budget.sh --evidence-dir <approved-mtime-after-restamp fixture> --state-dir <scratch> <<< '{"hook_event_name":"PreToolUse", ...}'
  test $? -eq 2
  ```

- Must-2 →
  ```
  grep -qi "stall" dot_claude/skills/proven-done/SKILL.md
  grep -q "resume-packet.md" dot_claude/skills/proven-done/SKILL.md
  grep -q "stall-x2" dot_claude/skills/proven-done/SKILL.md   # 機械判定表への追加
  ```

- Must-3 →
  ```
  test "$(grep -ci 'resume-grant' tests/run-shell-tests.sh)" -ge 4
  test "$(grep -ci 'stall' tests/run-shell-tests.sh)" -ge 1
  bash tests/run-shell-tests.sh; test $? -eq 0
  ```

- Must-4 →
  ```
  # HOME override + cwd に dot_claude/ が無い環境で --self が stripped-name 解決を経て exit 0
  HOME=<fake home (deployed layout, executable_ prefix 無し)> \
    bash scripts/kit-sync-check.sh --self --manifest "$HOME/.claude/skills/agent-policy-kit/kit-manifest.yml"
  test $? -eq 0
  ```

- Must-5 →
  ```
  grep -A5 "kit-sync-check.sh --check" dot_claude/skills/proven-done/SKILL.md | grep -q "exit 1"
  test "$(grep -c 'kit-sync-check.sh' dot_claude/skills/proven-done/SKILL.md)" -ge 2   # 7本リスト内 + exit1挙動記述
  ```

- Must-6 →
  ```
  grep -A3 "3c\." dot_claude/skills/agent-policy-kit/SKILL.md | grep -qi "kit-sync-check"
  grep -q "3d\." dot_claude/skills/agent-policy-kit/SKILL.md
  ```

- Must-7 →
  ```
  HOME=<fake home> bash scripts/kit-sync-check.sh --check \
    --manifest "$HOME/.claude/skills/agent-policy-kit/kit-manifest.yml" --target-dir <vendored copies dir>
  test $? -eq 0
  HOME=<fake home> bash scripts/kit-sync-check.sh --self \
    --manifest "$HOME/.claude/skills/agent-policy-kit/kit-manifest.yml"
  test $? -eq 0
  ```

- Must-8 →
  ```
  grep -q "Light lane fast path" dot_claude/skills/proven-done/SKILL.md
  grep -q "0 → 1 → 1.5 → 2.7 → 3 → 3.5 → 4" dot_claude/skills/proven-done/SKILL.md
  ```

- Must-9 →
  ```
  grep -qi "並列起動してよい" dot_claude/skills/proven-done/SKILL.md
  grep -qi "folded into full battery\|full battery.*上位互換" dot_claude/skills/proven-done/SKILL.md
  ```

- Must-10 →
  ```
  grep -A6 "verifier tree 変異ガード" dot_claude/skills/proven-done/SKILL.md | grep -qi "orchestrator も"
  ```

- Must-11 →
  ```
  grep -A2 "自動エスカレーション条件" dot_claude/docs/agent-policy.md | grep -q "red"
  grep -A2 "自動エスカレーション条件" dot_claude/docs/agent-policy.md | grep -q "target_test"
  ```

- Must-12 →
  ```
  grep -q "review-loop stall" dot_claude/docs/agent-policy.md
  grep -q "review-loop stall" dot_claude/skills/proven-done/SKILL.md
  grep -q "review-loop stall" dot_claude/agents/done-evaluator.md
  # script が検出する exit-2 signal の呼称は維持される (誤って両方消していないことの確認)
  grep -q "collapsed loop" dot_claude/agents/implementer.md
  ```

- Must-13 →
  ```
  grep -A3 "light.*low-risk" dot_claude/docs/agent-policy.md | grep -qi "topology-mapper.*skip\|skip.*topology-mapper"
  ```

- Must-14 →
  ```
  grep -A2 "spec-curator" dot_claude/skills/proven-done/SKILL.md | grep -qi "適用不可\|self-escalation"
  grep -A2 "spec-curator" dot_claude/docs/agent-policy.md | grep -qi "適用不可\|self-escalation"
  ```

- Must-15 →
  ```
  ! grep -q "^\`failure_class\` enum (5 値):" dot_claude/skills/proven-done/SKILL.md
  grep -q "implementer.md §iterations.json" dot_claude/skills/proven-done/SKILL.md
  grep -q "agent-policy.md §10" dot_claude/skills/proven-done/SKILL.md
  ```

- Must-16 →
  ```
  grep -A3 "wired_at.*実在" dot_claude/skills/proven-done/SKILL.md | grep -qi "runtime-verifier"
  ```

- Must-17 →
  ```
  for f in static-verifier runtime-verifier spec-grader done-evaluator; do
    grep -qi "done-eval.json.*存在\|status: complete.*Step 8" dot_claude/agents/$f.md || exit 1
  done
  ```

- Must-18 →
  ```
  grep -qi "orchestrator-direct-implementation" scripts/agent-policy-hook.sh
  grep -qi "orchestrator-direct-implementation" dot_claude/skills/agent-policy-kit/templates/scripts/executable_agent-policy-hook.sh
  # fixture: 本番パス Write + .agent-evidence/.active 実行中 + (implementer 委譲状態の proxy) -> exit 2
  echo '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"<production file>"}}' \
    | bash scripts/agent-policy-hook.sh; test $? -eq 2
  # allowlist escape
  grep -q "orchestrator-direct-implementation" ci/allowlist.yml   # (ドキュメントコメントのパターン追加)
  ```

- Must-19 →
  ```
  test -f dot_claude/skills/agent-policy-kit/templates/scripts/executable_portable.sh
  grep -q "portable_timeout" dot_claude/skills/agent-policy-kit/templates/scripts/executable_portable.sh
  grep -q "portable_http_probe" dot_claude/skills/agent-policy-kit/templates/scripts/executable_portable.sh
  test -f scripts/portable.sh
  ```

- Must-20 →
  ```
  grep -qi "portable_timeout\|portable_http_probe" dot_claude/agents/runtime-verifier.md
  grep -qi "裸の.*timeout\|直接呼ばない" dot_claude/agents/runtime-verifier.md
  ```

- Must-21 →
  ```
  grep -qi "lane-capability\|app-hosted lane" dot_claude/agents/spec-curator.md
  grep -qi "keychain\|entitlement" dot_claude/agents/spec-curator.md
  ```

- Must-22 →
  ```
  test "$(grep -ci 'portable_timeout' tests/run-shell-tests.sh)" -ge 1
  test "$(grep -ci 'portable_http_probe' tests/run-shell-tests.sh)" -ge 1
  bash tests/run-shell-tests.sh; test $? -eq 0
  ```

- Must-23 →
  ```
  pre_version="1.2.0"
  bash scripts/kit-manifest-update.sh
  post_version="$(grep '^kit_version:' dot_claude/skills/agent-policy-kit/kit-manifest.yml | sed -E 's/^kit_version: *"?([^"]*)"?/\1/')"
  test "$post_version" = "1.3.0" && test "$post_version" != "$pre_version"
  test "$(grep -c '^  [A-Za-z0-9_.-]*\.sh:' dot_claude/skills/agent-policy-kit/kit-manifest.yml)" -eq 16
  bash scripts/kit-sync-check.sh --self  --manifest dot_claude/skills/agent-policy-kit/kit-manifest.yml
  bash scripts/kit-sync-check.sh --check --manifest dot_claude/skills/agent-policy-kit/kit-manifest.yml
  grep -q "portable.sh" dot_claude/skills/agent-policy-kit/SKILL.md
  ```

- Must-24 →
  ```
  bash tests/run-shell-tests.sh; test $? -eq 0
  ```

全コマンド exit 0 (Must-18 の exit 2 fixture / Must-1(c 後半)(d) の exit 2 fixture は意図した非ゼロ)。

## Non-goals (今回やらない)

- **5 消費 repo (alpha-mind / am-wt-auditlog / native-trace / recall-paper / cloudflare-workers-hs)
  への今回 fix のロールアウト** — merge 後の別タスク (kit sync)。
- **CI ワークフローの新規導入**。
- **新規 verifier agent の追加**。
- **deliberate-waiver (期限付き waiver 運用ポリシー) の変更**。
- **empirical-prompt-tuning (プロンプト再チューニング)** — 別タスク。
- **done-evaluator.md 以外の agent への「review-loop stall」以外の用語変更**。
- **Must-18 の orchestrator/subagent 判別 discriminator の Claude Code 側実装** (hook payload の
  仕様自体の変更) — implementer は既存 payload から判別可能な signal のみを使う。判別不能と判明した
  場合は Open questions Q1 に従いエスカレーションする (代替 hook 設計を独断で発明しない)。

## Risk

- level: high-risk
- must_count: 24 (block レーン閾値 `> 8` を超過するが、下記 `## Amendments` の通りユーザー明示
  kickoff (`.agent-evidence/commands.txt` 記録済み) により block レーンの human sign-off 要件は
  **既に充足**している。Fix-1 (guard-evasion-gates.md, spec-grader DEEPEST recommendation B) と同型の
  「single heavy-lane task + packet ループ」で解消する。)
- boundary_touched: multi
  - **event subscription**: `PreToolUse`/`PostToolUse` hook (`agent-time-budget.sh`,
    `agent-policy-hook.sh`) の判定ロジック拡張。
  - **config**: `ci/allowlist.yml` への新規 `rule` 追加、hook-private state ディレクトリへの新規
    ファイル種別 (`resume-grant.pending`/`.approved`) 追加。
  - **public export相当**: `dot_claude/skills/agent-policy-kit/templates/scripts/**` +
    `kit-manifest.yml` は 5 消費 repo に配布される公開契約であり、本 fix 群は将来の sync で全消費
    repo に波及する。
- estimated_files: 23 (basis:
  - `Glob scripts/*.sh` → 既存 15 本中 3 本 (`agent-time-budget.sh` / `kit-sync-check.sh` /
    `agent-policy-hook.sh`) を編集 + 新規 1 本 (`portable.sh`)。
  - `Glob dot_claude/skills/agent-policy-kit/templates/scripts/*.sh` → 既存 15 本中同じ 3 本を編集 +
    新規 1 本 (`executable_portable.sh`)。
  - `dot_claude/skills/agent-policy-kit/kit-manifest.yml` (P-E で再生成、15→16 エントリ)。
  - `dot_claude/skills/proven-done/SKILL.md` / `dot_claude/skills/agent-policy-kit/SKILL.md` /
    `dot_claude/docs/agent-policy.md` (3 本、Fix-2/3/4/6 が共通して編集)。
  - `Glob dot_claude/agents/*.md` → 既存 9 本中 5 本を編集 (`done-evaluator.md` / `static-verifier.md`
    / `runtime-verifier.md` / `spec-grader.md` / `spec-curator.md`)。
  - `ci/allowlist.yml` (新規 rule 例のドキュメント追記、1 本)。
  - `tests/run-shell-tests.sh` (1 本、全 fix が追記)。
  - `Glob tests/fixtures/**` → 既存 fixture ツリーの粒度 (`tests/fixtures/kit-sync/` が
    manifest.yml + target_ok/ + target_stale/ + templates/ の 4 要素等) を踏まえ、Fix-2 (resume-grant
    lifecycle)・Fix-3 (consumer-repo simulation)・Fix-6(k) (orchestrator-direct-implementation)・
    Fix-5 (portable helpers) の新規 fixture ツリーを 4 単位として計上。
  合計 4(scripts) + 4(kit templates と manifest) + 3(SKILL/docs) + 5(agents) + 1(allowlist) +
  1(run-shell-tests.sh) + 4(fixture trees) = 22、Fix-6(h)/(i) の SKILL.md 内部圧縮作業に伴う
  参照整合確認 (新規ファイルではないが Grep 対象拡張の可能性) を保守的に +1 して 23。
  root `AGENTS.md` は生成物のため直接編集対象に含めない (Fix-1 と同型の drift のみ — 下記残存リスク
  参照)。)
- escalate_to_opus: true
- 理由:
  - Fix-2/Fix-4(c)/Fix-6(k) は **稼働中の PreToolUse/PostToolUse/Stop hook** の判定ロジックを拡張する
    (false-positive は以後の全タスクの完了主張・進行を無条件でブロックしうる、Fix-1 と同型の
    harness-infrastructure コスト)。
  - kit テンプレートは 5 消費 repo に配布される公開契約であり、本 fix 群のバグは sync 経路で他 repo にも
    伝播する。
  - `must_count=24` は block レーン閾値 (`must_count > 8`) を明確に超過し、`high-risk` かつ
    `boundary_touched=multi` の組も成立するため、二重に block レーン条件に該当する。
    **2026-07-05 kickoff で人間が「全部まとめて」実行を明示指示 (`.agent-evidence/commands.txt` に
    記録済み) しており、Fix-1 の recommendation B (single heavy-lane task + packet ループ) と同じ
    解消パターンを適用する。** 下記 `## Work packets` / `## Amendments` 参照。
- Time budget の現実:
  - heavy レーン budget (90 分) を **本 campaign 全体では確実に超過する** (5 fix・24 Must・23
    ファイルの規模)。P-A〜P-E は個々の packet が **resume point** として設計されており、
    time-budget 強制ジャンプ (Step 10) が発生した場合は次セッションで未完了 packet から再開できる。
  - **P-A (Fix-2) を最初の packet に置く** — budget-resume 機構自体がこの campaign の再開性を担保する
    ため、他 packet より先に landing させる (P-A が未着手のまま time budget を使い切ると、後続
    packet の再開判断が Must-1 の grant 機構に頼れなくなる)。
- 残存リスク (本 spec の Must 外、対応は別タスク):
  - root `AGENTS.md` は `dot_claude/docs/agent-policy.md` から生成される。本 fix で正本を編集しても
    kit apply/dogfood 再実行までは自動反映されない (Fix-1 と同型の drift)。完了報告に明記すること。
  - `dot_claude/agents/done-evaluator.md` の kit スクリプトフォールバック説明 (「`~/.claude/skills/
    agent-policy-kit/templates/scripts/` の同名テンプレート (`executable_` prefix 付き) を実行して
    よい」) は、Must-4 で修正する `kit-sync-check.sh` の manifest 解決とは**別箇所**で同型の
    「chezmoi が `executable_` prefix を剥がして deploy する」事実を見落としている (deployed layout
    では prefix 付きファイルは実在しない)。本 spec のスコープ外 (done-evaluator.md はこの campaign の
    Must-17 で別の追記はするが、この特定の記述は変更しない) だが、次回の corpus 監査候補として記録
    する。

## Work packets

`.agent-evidence/commands.txt` に記録済みのユーザー明示 kickoff (「全部まとめて」) と、
`docs/specs/guard-evasion-gates.md` の spec-grader DEEPEST recommendation B 先例を踏襲し、
**single heavy-lane task 内の Step-3 work-packets.json パケットループ**として次の 5 パケットで
実装する (5 fix を個別 task に分割しない理由は上記先例と同じ: 各パケットが独立に high-risk かつ
`boundary_touched=multi` になり得るため block レーンを回避できず、human sign-off を 5x に増やし、
producer-before-consumer 順序と `kit_version` 単一バンプの atomicity を壊すのみ)。

- **P-A** = Fix-2 (Must-1/Must-2/Must-3)。
  スコープ: `scripts/agent-time-budget.sh` の resume-grant 機構、`proven-done/SKILL.md` の stall
  プロトコル、対応する kit テンプレート編集、grant lifecycle + stall のテスト。
  depends_on: []
- **P-B** = Fix-3 (Must-4/Must-5/Must-6/Must-7)。
  スコープ: `scripts/kit-sync-check.sh` の manifest fallback + stripped-name 解決、
  `proven-done/SKILL.md` Step 0 の 7 本必須化、`agent-policy-kit/SKILL.md` Phase 3 smoke check 追加、
  consumer-repo simulation fixture。
  depends_on: [P-A] (同一 implementer・同一ファイル群 (SKILL.md) のため sequential)
- **P-C** = Fix-4+6 (Must-8〜Must-18)。
  スコープ: SKILL.md の light lane fast path・deviation 明文化・verifier-mutation guard 拡張、
  agent-policy.md の §10/§5/§2.5/§7 修正、4 verifier agent への A5 boilerplate、
  agent-policy-hook.sh の orchestrator-direct-implementation blocking 化。
  depends_on: [P-A, P-B]
- **P-D** = Fix-5 (Must-19〜Must-22)。
  スコープ: `portable.sh` テンプレート新設、runtime-verifier.md/spec-curator.md への追記、
  portable helper のテスト。
  depends_on: [P-A, P-B, P-C]
- **P-E** = kit_version 単一バンプ (1.2.0→1.3.0) + 最終フル回帰 + agent-policy.md/AGENTS.md
  整合確認 (Must-23/Must-24)。
  depends_on: [P-A, P-B, P-C, P-D]

P-A〜P-D の各 `done_when` は、**`kit_version` バンプが P-E まで意図的に据え置かれる** (テンプレート
`# KIT_VERSION:` 行は 1.2.0 のまま、`kit-manifest.yml` も無変更) ことを Non-goal として明示的に
宣言しなければならない。この transient window では `bash scripts/kit-sync-check.sh --self` が
**stale (sha256 drift, exit 1) を返すことが期待される正常な中間状態**である
(`docs/specs/guard-evasion-gates.md` の P12/P3 (Fix-1) と同じパターン — P-E の Must-23 で一括解消する
までは意図的な不整合として許容する)。

## Open questions (あれば)

- **Q1 (Must-18 の orchestrator/subagent discriminator)**: `agent-policy-hook.sh` の
  orchestrator-direct-implementation 検出には、hook payload 上で「orchestrator (main context) が
  発行した tool call」と「Task tool で起動された subagent が発行した tool call」を区別する決定論的
  フィールドが必要だが、そのようなフィールドが Claude Code の PreToolUse/PostToolUse payload に
  実在するかは本 spec 作成時点で未確認 (`scripts/agent-policy-hook.sh`/`scripts/agent-time-budget.sh`
  の既存実装は `hook_event_name`/`tool_name`/`tool_input` のみを参照しており、agent 種別フィールドの
  使用実績が repo 内に無い)。implementer は Step 3 でこれを調査し、(a) 使える discriminator が
  あればそれを採用し `commands.txt` に根拠を記録する、(b) 無ければ検出範囲を「証拠として確認可能な
  proxy (例: `.agent-evidence/.active` の `lane=` 確定後、対応する packet の checkpoint/実装 delegate
  記録が一切無いまま本番パスへの Write/Edit が発生した」等)」に narrow する設計判断を行い、
  その判断も `commands.txt` に記録する。いずれの場合も human 判断を要するほど不確実なら
  `AskUserQuestion` でエスカレーションする (Must-18 自体は「機構を追加すること」を要求するのみで、
  discriminator の具体設計は spec レベルでは未確定のまま残す)。

## Amendments

- **kickoff authority (2026-07-05)**: 本 campaign (Fix-2..6 の一括実装) は、ユーザーの明示指示が
  既に `.agent-evidence/commands.txt` に記録済みである:
  > `# KICKOFF AUTHORITY: user message 2026-07-05 「なんで全部まとめてやらないのよ」 — explicit
  > instruction to batch the remaining approved campaign into one run; recorded here as the
  > block-lane human kickoff approval artifact.`
  これにより、上記 `## Risk` の block レーン該当 (`must_count=24 > 8` および
  `high-risk AND boundary_touched=multi`) に対する human sign-off は **spec-curation の時点で既に
  充足**している。`docs/specs/guard-evasion-gates.md` の Amendments (spec-grader DEEPEST
  recommendation B 採用、single heavy-lane task + packet ループ) と同じ解消パターンを、5 fix 全体に
  対して 1 回だけ適用する (Fix ごとに個別の block-lane 承認を取り直さない)。
- **Fix-1 の位置づけ**: `docs/specs/guard-evasion-gates.md` (Fix-1) は PR #15 で merge 済みであり、
  本 spec は Fix-2〜6 のみを対象とする。Fix-1 が導入した機構 (`verify-guard-integrity.sh`、
  hook-private state ディレクトリ `$HOME/.claude/state/agent-time-budget/`、`kit_version=1.2.0`・
  15 テンプレート) を前提として本 spec の Must を組み立てている (`scripts/agent-time-budget.sh` の
  `--state-dir` 機構は Fix-1 で既に導入済みであり、Must-1 の resume-grant はこれと同じディレクトリ
  規約に相乗りする)。
