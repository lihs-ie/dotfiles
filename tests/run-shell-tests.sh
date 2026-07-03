#!/usr/bin/env bash
# pure bash test runner for shell scripts
# Requires bash (not sh/dash) — arithmetic is bash-specific.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

pass_count=0
fail_count=0

run_test() {
  local name="$1"
  local cmd="$2"
  local expected_exit="$3"
  local actual_exit=0

  eval "$cmd" >/dev/null 2>&1 || actual_exit=$?

  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "PASSED: $name (exit $actual_exit)"
    pass_count=$((pass_count + 1))
  else
    echo "FAILED: $name (expected exit $expected_exit, got $actual_exit)"
    fail_count=$((fail_count + 1))
  fi
}

run_test "verify-failure-class valid" \
  "bash scripts/verify-failure-class.sh tests/fixtures/iterations_valid.json" \
  0

run_test "verify-failure-class collapsed" \
  "bash scripts/verify-failure-class.sh tests/fixtures/iterations_collapsed.json" \
  2

run_test "verify-failure-class triangulation (same failure_class, distinct target_test — not collapsed)" \
  "bash scripts/verify-failure-class.sh tests/fixtures/iterations_triangulation.json" \
  0

run_test "verify-failure-class unknown class" \
  "bash scripts/verify-failure-class.sh tests/fixtures/iterations_unknown_class.json" \
  1

run_test "verify-failure-class green with failure_class" \
  "bash scripts/verify-failure-class.sh tests/fixtures/iterations_green_with_class.json" \
  1

run_test "verify-failure-class missing phase" \
  "bash scripts/verify-failure-class.sh tests/fixtures/iterations_missing_phase.json" \
  1

run_test "verify-allowlist-expiry quarantine valid" \
  "bash scripts/verify-allowlist-expiry.sh --quarantine tests/fixtures/quarantine_valid.yml" \
  0

run_test "verify-allowlist-expiry quarantine expired" \
  "bash scripts/verify-allowlist-expiry.sh --quarantine tests/fixtures/quarantine_expired.yml" \
  1

run_test "verify-allowlist-expiry quarantine gates valid" \
  "bash scripts/verify-allowlist-expiry.sh --quarantine tests/fixtures/quarantine_gates_valid.yml" \
  0

run_test "verify-allowlist-expiry quarantine gates expired" \
  "bash scripts/verify-allowlist-expiry.sh --quarantine tests/fixtures/quarantine_gates_expired.yml" \
  1

run_test "verify-allowlist-expiry quarantine gates missing fields" \
  "bash scripts/verify-allowlist-expiry.sh --quarantine tests/fixtures/quarantine_gates_missing_fields.yml" \
  1

run_test "kit-sync-check --check ok (vendored matches manifest)" \
  "bash scripts/kit-sync-check.sh --check --manifest tests/fixtures/kit-sync/manifest.yml --target-dir tests/fixtures/kit-sync/target_ok" \
  0

run_test "kit-sync-check --check stale (sha256 drift at same KIT_VERSION)" \
  "bash scripts/kit-sync-check.sh --check --manifest tests/fixtures/kit-sync/manifest.yml --target-dir tests/fixtures/kit-sync/target_stale" \
  2

run_test "kit-sync-check --check missing (vendored file absent)" \
  "bash scripts/kit-sync-check.sh --check --manifest tests/fixtures/kit-sync/manifest.yml --target-dir tests/fixtures/kit-sync/target_missing" \
  1

run_test "kit-sync-check --self (real templates vs real kit-manifest.yml)" \
  "bash scripts/kit-sync-check.sh --self --manifest dot_claude/skills/agent-policy-kit/kit-manifest.yml" \
  0

# evidence-stamp.sh: output schema (git_sha / dirty_diff_hash keys, string types)
stamp_output="$(bash scripts/evidence-stamp.sh 2>/dev/null || true)"
if printf '%s' "$stamp_output" | jq -e --arg sha "$(git rev-parse HEAD)" '.git_sha == $sha' >/dev/null 2>&1 \
  && printf '%s' "$stamp_output" | jq -e '.dirty_diff_hash | test("^[0-9a-f]{64}$")' >/dev/null 2>&1; then
  echo "PASSED: evidence-stamp schema (git_sha matches HEAD, dirty_diff_hash is sha256 hex)"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: evidence-stamp schema (git_sha matches HEAD, dirty_diff_hash is sha256 hex)"
  fail_count=$((fail_count + 1))
fi

run_test "verify-evidence-freshness no-round-dir (first run)" \
  "bash scripts/verify-evidence-freshness.sh --evidence-dir tests/fixtures/evidence-freshness/no-round-dir" \
  0

run_test "verify-evidence-freshness mismatch (stale tree_stamp fixture)" \
  "bash scripts/verify-evidence-freshness.sh --evidence-dir tests/fixtures/evidence-freshness/mismatch" \
  1

# verify-evidence-freshness mismatch output: offending file path must be listed
mismatch_output="$(bash scripts/verify-evidence-freshness.sh --evidence-dir tests/fixtures/evidence-freshness/mismatch 2>&1 || true)"
if printf '%s' "$mismatch_output" | grep -q "round-1/static-review.json"; then
  echo "PASSED: verify-evidence-freshness mismatch output lists offending file"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: verify-evidence-freshness mismatch output lists offending file"
  fail_count=$((fail_count + 1))
fi

# verify-evidence-freshness match: git_sha/dirty_diff_hash depend on the live tree state at test
# time, so build the round dir dynamically from evidence-stamp.sh's own output rather than a
# static fixture.
match_evidence_dir="$(mktemp -d)"
mkdir -p "$match_evidence_dir/round-1"
printf '{"tree_stamp": %s}' "$(bash scripts/evidence-stamp.sh)" > "$match_evidence_dir/round-1/static-review.json"
run_test "verify-evidence-freshness match (live tree stamp)" \
  "bash scripts/verify-evidence-freshness.sh --evidence-dir '$match_evidence_dir'" \
  0
rm -rf "$match_evidence_dir"

# verify-evidence-freshness: checkpoint-<packet_id>.json (packet ループ, round-* とは別名前空間) は
# 故意に古い tree_stamp を持っていても freshness 検査の対象外である (round-*/ のみ走査するため)。
# round-* が無い場合とある場合の両方で exit 0 のままであることを確認する
# (docs/specs/packet-decomposition-checkpoint.md Must-2 受入)。
run_test "verify-evidence-freshness checkpoint-*.json ignored (no round-* dir)" \
  "bash scripts/verify-evidence-freshness.sh --evidence-dir tests/fixtures/evidence-freshness/checkpoint-no-round" \
  0

run_test "verify-evidence-freshness checkpoint-*.json ignored (round-* dir present)" \
  "bash scripts/verify-evidence-freshness.sh --evidence-dir tests/fixtures/evidence-freshness/checkpoint-with-round" \
  0

# --- agent-time-budget.sh (PreToolUse/PostToolUse hook) ---
# started_at は相対生成できない (時刻依存) ため、テスト実行時に GNU/BSD 両対応の date で
# 動的に .active fixture を生成する (docs/specs/agent-time-budget-hook.md Must-6)。
iso8601_seconds_ago() {
  local seconds="$1"
  local epoch=$(( $(date -u +%s) - seconds ))
  if date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ
  fi
}

write_time_budget_fixture() {
  # $1=dir  $2=seconds ago  $3=lane (空なら lane 行を省略 -> hook 側で heavy default になることを検証)
  local dir="$1" seconds_ago="$2" lane="$3"
  mkdir -p "$dir"
  {
    echo "task=agent-time-budget-hook-fixture"
    echo "started_at=$(iso8601_seconds_ago "$seconds_ago")"
    if [ -n "$lane" ]; then echo "lane=$lane"; fi
  } > "$dir/.active"
}

time_budget_fixture_dir="tests/fixtures/time-budget"
mkdir -p "$time_budget_fixture_dir/no-active"
rm -f "$time_budget_fixture_dir/no-active/.active"
write_time_budget_fixture "$time_budget_fixture_dir/heavy-50" 2700 "heavy"    # 45min/90min = 50%
write_time_budget_fixture "$time_budget_fixture_dir/heavy-82" 4440 "heavy"   # 74min/90min ~= 82% (warn band)
write_time_budget_fixture "$time_budget_fixture_dir/heavy-110" 5940 "heavy"  # 99min/90min = 110% (deny band)
write_time_budget_fixture "$time_budget_fixture_dir/lane-missing" 4500 ""    # 75min, lane 行なし -> heavy 基準なら 83.3%(warn) / light 基準なら 250%(deny)

run_test "agent-time-budget: .active 無し -> allow (PreToolUse)" \
  "echo '{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{}}' | bash scripts/agent-time-budget.sh --evidence-dir $time_budget_fixture_dir/no-active" \
  0

run_test "agent-time-budget: PreToolUse 50% -> allow, no warning" \
  "echo '{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{}}' | bash scripts/agent-time-budget.sh --evidence-dir $time_budget_fixture_dir/heavy-50" \
  0

run_test "agent-time-budget: PostToolUse 50% -> allow, no warning" \
  "echo '{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{}}' | bash scripts/agent-time-budget.sh --evidence-dir $time_budget_fixture_dir/heavy-50" \
  0

post_warn_exit=0
post_warn_output="$(echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{}}' | bash scripts/agent-time-budget.sh --evidence-dir "$time_budget_fixture_dir/heavy-82" 2>&1 1>/dev/null)" || post_warn_exit=$?
if [ "$post_warn_exit" -eq 2 ] && printf '%s' "$post_warn_output" | grep -Eiq 'heavy|warn|警告'; then
  echo "PASSED: agent-time-budget PostToolUse 82% (warn band) -> exit 2 with lane/warning hint"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget PostToolUse 82% (warn band) -> exit 2 with lane/warning hint (exit=$post_warn_exit, out=$post_warn_output)"
  fail_count=$((fail_count + 1))
fi

pre_deny_exit=0
pre_deny_output="$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' | bash scripts/agent-time-budget.sh --evidence-dir "$time_budget_fixture_dir/heavy-110" 2>&1 1>/dev/null)" || pre_deny_exit=$?
if [ "$pre_deny_exit" -eq 2 ] \
  && printf '%s' "$pre_deny_output" | grep -q "time-budget-exceeded.md" \
  && printf '%s' "$pre_deny_output" | grep -q "Step 10"; then
  echo "PASSED: agent-time-budget PreToolUse 110% -> exit 2 (deny) with time-budget-exceeded.md/Step 10 guidance"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget PreToolUse 110% -> exit 2 (deny) with time-budget-exceeded.md/Step 10 guidance (exit=$pre_deny_exit, out=$pre_deny_output)"
  fail_count=$((fail_count + 1))
fi

run_test "agent-time-budget: PreToolUse 110% but Write under .agent-evidence/ -> exception allow" \
  "echo '{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"'\"\$PWD\"'/.agent-evidence/time-budget-exceeded.md\"}}' | bash scripts/agent-time-budget.sh --evidence-dir $time_budget_fixture_dir/heavy-110" \
  0

lane_missing_exit=0
lane_missing_output="$(echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{}}' | bash scripts/agent-time-budget.sh --evidence-dir "$time_budget_fixture_dir/lane-missing" 2>&1 1>/dev/null)" || lane_missing_exit=$?
if [ "$lane_missing_exit" -eq 2 ] && printf '%s' "$lane_missing_output" | grep -qi 'heavy'; then
  echo "PASSED: agent-time-budget lane 欠落は heavy 扱い (75min/90min warn band, PostToolUse exit 2)"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget lane 欠落は heavy 扱い (75min/90min warn band, PostToolUse exit 2) (exit=$lane_missing_exit, out=$lane_missing_output)"
  fail_count=$((fail_count + 1))
fi

missing_event_exit=0
missing_event_output="$(echo '{"tool_name":"Bash","tool_input":{}}' | bash scripts/agent-time-budget.sh --evidence-dir "$time_budget_fixture_dir/heavy-110" 2>&1 1>/dev/null)" || missing_event_exit=$?
if [ "$missing_event_exit" -eq 0 ] && printf '%s' "$missing_event_output" | grep -qi 'hook_event_name'; then
  echo "PASSED: agent-time-budget hook_event_name 欠落 -> fail-safe allow (exit 0) + stderr 診断"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget hook_event_name 欠落 -> fail-safe allow (exit 0) + stderr 診断 (exit=$missing_event_exit, out=$missing_event_output)"
  fail_count=$((fail_count + 1))
fi

# --- verify-wiring.sh: long-lived branch blind-spot (BASE_REF 未設定は committed ∪ working-tree
# を常に union する。BASE_REF 明示時は committed のみの現行意味論を完全維持) ---
setup_verify_wiring_long_lived_branch_fixture() {
  # 一時 git repo を組み立てる: base commit (wiring_manifest.yml 最小構成) -> feature commit
  # (committed diff base...HEAD を非空にする、wiring rule の when にはマッチしない無関係な変更)。
  # working-tree-only の変更 (when にマッチする untracked file) は呼び出し側で追加する。
  # 出力: "<repo_dir><TAB><base_commit_sha>"
  local repo_dir
  repo_dir="$(mktemp -d)"
  (
    cd "$repo_dir"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    # verify-wiring.sh の base 解決 (`git symbolic-ref refs/remotes/origin/HEAD`) が
    # 「origin remote 未設定」で fatal (非0) にならないよう、symbolic ref のみ用意する
    # (実 ref を指す必要はない — verify-wiring.sh 側は `git rev-parse --verify` で
    # 存在しなければ HEAD~1 フォールバックに落ちる想定の経路を使う)。
    git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    mkdir -p src docs
    cat > wiring_manifest.yml <<'YAML'
rules:
  - id: test-rule
    when: "src/**"
    require_one_of:
      - "docs/**"
    reason: "test fixture: src changes require docs wiring"
YAML
    echo "base" > README.md
    git add wiring_manifest.yml README.md
    git commit -q -m "base commit"
    echo "feature change (unrelated to wiring rule)" >> README.md
    git add README.md
    git commit -q -m "feature commit"
  ) >/dev/null
  printf '%s\t%s' "$repo_dir" "$(git -C "$repo_dir" rev-parse HEAD~1)"
}

verify_wiring_script="$REPO_ROOT/scripts/verify-wiring.sh"
wiring_fixture="$(setup_verify_wiring_long_lived_branch_fixture)"
wiring_fixture_dir="${wiring_fixture%%$'\t'*}"
wiring_fixture_base_sha="${wiring_fixture##*$'\t'}"

# working-tree-only 変更: when ("src/**") にマッチする untracked file。require_one_of
# ("docs/**") は満たさない。
echo "untracked working-tree change" > "$wiring_fixture_dir/src/new.txt"

wiring_unset_exit=0
wiring_unset_output="$(cd "$wiring_fixture_dir" && unset BASE_REF CLAUDE_PROJECT_DIR && bash "$verify_wiring_script" 2>&1)" || wiring_unset_exit=$?
if [ "$wiring_unset_exit" -eq 1 ] \
  && printf '%s' "$wiring_unset_output" | grep -q "POLICY VIOLATION" \
  && printf '%s' "$wiring_unset_output" | grep -q "test-rule"; then
  echo "PASSED: verify-wiring BASE_REF unset + committed diff 非空でも working-tree-only 変更を検査する (長寿命ブランチ盲点修正, exit 1)"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: verify-wiring BASE_REF unset + committed diff 非空でも working-tree-only 変更を検査する (長寿命ブランチ盲点修正, exit 1) (exit=$wiring_unset_exit, out=$wiring_unset_output)"
  fail_count=$((fail_count + 1))
fi

wiring_explicit_exit=0
wiring_explicit_output="$(cd "$wiring_fixture_dir" && BASE_REF="$wiring_fixture_base_sha" bash "$verify_wiring_script" 2>&1)" || wiring_explicit_exit=$?
if [ "$wiring_explicit_exit" -eq 0 ] \
  && printf '%s' "$wiring_explicit_output" | grep -q "verify-wiring: OK" \
  && ! printf '%s' "$wiring_explicit_output" | grep -q "POLICY VIOLATION"; then
  echo "PASSED: verify-wiring BASE_REF 明示時は working-tree-only 変更を検査しない (committed のみの現行意味論維持, exit 0)"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: verify-wiring BASE_REF 明示時は working-tree-only 変更を検査しない (committed のみの現行意味論維持, exit 0) (exit=$wiring_explicit_exit, out=$wiring_explicit_output)"
  fail_count=$((fail_count + 1))
fi

rm -rf "$wiring_fixture_dir"

# --- agent-evidence-gate.sh: Amendment A5 3-branch (in-progress/complete/escalated) + Must-5 waiver ---
AEG_BASE="tests/fixtures/agent-evidence-gate"

run_test "agent-evidence-gate missing-done-eval -> block (done-eval.json)" \
  "err=\$(bash scripts/agent-evidence-gate.sh --evidence-dir $AEG_BASE/missing-done-eval < /dev/null 2>&1 1>/dev/null); ec=\$?; [ \"\$ec\" -eq 2 ] && printf '%s' \"\$err\" | grep -q 'done-eval.json'" \
  0

run_test "agent-evidence-gate missing-done-eval-escalated -> allow" \
  "bash scripts/agent-evidence-gate.sh --evidence-dir $AEG_BASE/missing-done-eval-escalated < /dev/null" \
  0

run_test "agent-evidence-gate in-progress-allow (A5, commands.txt non-empty) -> allow" \
  "bash scripts/agent-evidence-gate.sh --evidence-dir $AEG_BASE/in-progress-allow < /dev/null" \
  0

run_test "agent-evidence-gate in-progress-no-commands (A5) -> block" \
  "bash scripts/agent-evidence-gate.sh --evidence-dir $AEG_BASE/in-progress-no-commands < /dev/null" \
  2

run_test "agent-evidence-gate normal-done -> allow" \
  "bash scripts/agent-evidence-gate.sh --evidence-dir $AEG_BASE/normal-done < /dev/null" \
  0

run_test "agent-evidence-gate missing-core-evidence -> block (regression)" \
  "bash scripts/agent-evidence-gate.sh --evidence-dir $AEG_BASE/missing-core-evidence < /dev/null" \
  2

run_test "agent-evidence-gate gate-violation-unwaived -> block (POLICY VIOLATION)" \
  "err=\$(bash scripts/agent-evidence-gate.sh --evidence-dir $AEG_BASE/gate-violation-unwaived < /dev/null 2>&1 1>/dev/null); ec=\$?; [ \"\$ec\" -eq 2 ] && printf '%s' \"\$err\" | grep -q 'POLICY VIOLATION'" \
  0

run_test "agent-evidence-gate gate-violation-waived (期限内 waiver) -> allow" \
  "bash scripts/agent-evidence-gate.sh --evidence-dir $AEG_BASE/gate-violation-waived --quarantine $AEG_BASE/gate-violation-waived/quarantine.yml < /dev/null" \
  0

run_test "agent-evidence-gate gate-violation-expired-waiver -> block" \
  "bash scripts/agent-evidence-gate.sh --evidence-dir $AEG_BASE/gate-violation-expired-waiver --quarantine $AEG_BASE/gate-violation-expired-waiver/quarantine.yml < /dev/null" \
  2

# --- collapsed-loop-guard.sh (Must-6): PostToolUse live collapsed-loop 検出 ---
CLG_BASE="tests/fixtures/collapsed-loop-guard"

clg_collapsed_exit=0
clg_collapsed_output="$(echo '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/'"$CLG_BASE"'/collapsed/iterations.json"}}' \
  | bash scripts/collapsed-loop-guard.sh --evidence-dir "$CLG_BASE/collapsed" 2>&1 1>/dev/null)" || clg_collapsed_exit=$?
if [ "$clg_collapsed_exit" -eq 2 ] && printf '%s' "$clg_collapsed_output" | grep -Eiq 'collapsed|collapse'; then
  echo "PASSED: collapsed-loop-guard collapsed fixture -> exit 2 with collapsed warning"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: collapsed-loop-guard collapsed fixture -> exit 2 with collapsed warning (exit=$clg_collapsed_exit, out=$clg_collapsed_output)"
  fail_count=$((fail_count + 1))
fi

run_test "collapsed-loop-guard healthy fixture -> allow" \
  "echo '{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"'\"\$PWD\"'/$CLG_BASE/healthy/iterations.json\"}}' | bash scripts/collapsed-loop-guard.sh --evidence-dir $CLG_BASE/healthy" \
  0

run_test "collapsed-loop-guard tool_name=Bash -> no-op allow" \
  "echo '{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{}}' | bash scripts/collapsed-loop-guard.sh --evidence-dir $CLG_BASE/collapsed" \
  0

run_test "collapsed-loop-guard hook_event_name 欠落 -> fail-safe allow" \
  "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"'\"\$PWD\"'/$CLG_BASE/collapsed/iterations.json\"}}' | bash scripts/collapsed-loop-guard.sh --evidence-dir $CLG_BASE/collapsed" \
  0

echo ""
echo "Results: $pass_count passed, $fail_count failed"
exit $fail_count
