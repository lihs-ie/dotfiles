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

# --- verify-failure-class.sh: Must-7 UTC タイムスタンプ規律 (future / regressed) ---
# started_at は相対生成できない (時刻依存) ため、テスト実行時刻基準で動的に fixture を生成する
# (静的コミット禁止。agent-time-budget-hook Must-6 の iso8601_seconds_ago パターンを踏襲)。
iso8601_offset() {
  # $1 = 秒オフセット (負なら過去、正なら未来)
  local offset="$1"
  local epoch=$(( $(date -u +%s) + offset ))
  if date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ
  fi
}

future_ts_dir="$(mktemp -d)"
cat > "$future_ts_dir/iterations.json" <<JSON
{
  "schema_version": "1.0",
  "task_id": "fixture-future-timestamp",
  "iterations": [
    {"n": 1, "started_at": "$(iso8601_offset -300)", "phase": "red", "failure_class": "product", "target_test": "t1"},
    {"n": 2, "started_at": "$(iso8601_offset 600)", "phase": "red", "failure_class": "product", "target_test": "t2"}
  ]
}
JSON

future_exit=0
future_output="$(bash scripts/verify-failure-class.sh "$future_ts_dir/iterations.json" 2>&1)" || future_exit=$?
if [ "$future_exit" -eq 1 ] && printf '%s' "$future_output" | grep -qi "future"; then
  echo "PASSED: verify-failure-class future timestamp (started_at > now+5min) -> exit 1"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: verify-failure-class future timestamp (started_at > now+5min) -> exit 1 (exit=$future_exit, out=$future_output)"
  fail_count=$((fail_count + 1))
fi
rm -rf "$future_ts_dir"

regress_ts_dir="$(mktemp -d)"
cat > "$regress_ts_dir/iterations.json" <<JSON
{
  "schema_version": "1.0",
  "task_id": "fixture-regressed-timestamp",
  "iterations": [
    {"n": 1, "started_at": "$(iso8601_offset -300)", "phase": "red", "failure_class": "product", "target_test": "t1"},
    {"n": 2, "started_at": "$(iso8601_offset -1200)", "phase": "red", "failure_class": "product", "target_test": "t2"}
  ]
}
JSON

regress_exit=0
regress_output="$(bash scripts/verify-failure-class.sh "$regress_ts_dir/iterations.json" 2>&1)" || regress_exit=$?
if [ "$regress_exit" -eq 1 ] && printf '%s' "$regress_output" | grep -Eiq "regress|逆行"; then
  echo "PASSED: verify-failure-class regressed timestamp (逆行) -> exit 1"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: verify-failure-class regressed timestamp (逆行) -> exit 1 (exit=$regress_exit, out=$regress_output)"
  fail_count=$((fail_count + 1))
fi
rm -rf "$regress_ts_dir"

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

# --- kit-sync-check.sh: Must-4 manifest fallback chain + stripped-name resolution, Must-5(b) exit-1
# non-silent message, Must-7 consumer-repo deployed-layout simulation
# (docs/specs/harness-campaign-fix2-6.md P-B). Static fixture tree (no time dependency):
# tests/fixtures/kit-sync-deployed/fake-home/.claude/skills/agent-policy-kit/ (deployed layout,
# executable_ prefix stripped from the template file on disk, manifest's template: field keeps the
# source-form executable_ prefix as the real manifest always does).
KIT_SYNC_DEPLOYED_FAKE_HOME="$REPO_ROOT/tests/fixtures/kit-sync-deployed/fake-home"
KIT_SYNC_DEPLOYED_MANIFEST="$KIT_SYNC_DEPLOYED_FAKE_HOME/.claude/skills/agent-policy-kit/kit-manifest.yml"
KIT_SYNC_DEPLOYED_VENDORED="$REPO_ROOT/tests/fixtures/kit-sync-deployed/vendored"

run_test "kit-sync-check --check consumer-repo deployed layout (Must-7) -> exit 0" \
  "HOME=$KIT_SYNC_DEPLOYED_FAKE_HOME bash scripts/kit-sync-check.sh --check --manifest $KIT_SYNC_DEPLOYED_MANIFEST --target-dir $KIT_SYNC_DEPLOYED_VENDORED" \
  0

run_test "kit-sync-check --self consumer-repo deployed layout stripped-name resolution (Must-4(d)) -> exit 0" \
  "HOME=$KIT_SYNC_DEPLOYED_FAKE_HOME bash scripts/kit-sync-check.sh --self --manifest $KIT_SYNC_DEPLOYED_MANIFEST" \
  0

# Must-4(b)/(c): manifest fallback chain WITHOUT an explicit --manifest flag. cwd is a scratch dir
# without dot_claude/ (consumer repo, simulated via CLAUDE_PROJECT_DIR override — no git repo needed
# since kit-sync-check.sh performs no git operations itself), HOME points at the deployed-layout
# fixture -> resolves via the $HOME fallback (c) and succeeds via stripped-name resolution (d).
kit_sync_consumer_repo="$(mktemp -d)"
kit_sync_fallback_exit=0
kit_sync_fallback_output="$(cd "$kit_sync_consumer_repo" && CLAUDE_PROJECT_DIR="$kit_sync_consumer_repo" HOME="$KIT_SYNC_DEPLOYED_FAKE_HOME" bash "$REPO_ROOT/scripts/kit-sync-check.sh" --self 2>&1 1>/dev/null)" || kit_sync_fallback_exit=$?
if [ "$kit_sync_fallback_exit" -eq 0 ]; then
  echo "PASSED: kit-sync-check manifest fallback chain (Must-4(b)/(c), no explicit --manifest, cwd without dot_claude/) -> resolves via \$HOME deployed layout, exit 0"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: kit-sync-check manifest fallback chain (Must-4(b)/(c), no explicit --manifest, cwd without dot_claude/) -> resolves via \$HOME deployed layout, exit 0 (exit=$kit_sync_fallback_exit, out=$kit_sync_fallback_output)"
  fail_count=$((fail_count + 1))
fi
rm -rf "$kit_sync_consumer_repo"

# Must-5(b): manifest missing via every fallback path (no repo-relative, no $HOME deployed, no
# explicit --manifest) -> exit 1, and the message must name the fallback paths tried (not silent —
# distinguishes from a plain "not found: <default path>" message).
kit_sync_no_manifest_home="$(mktemp -d)"
kit_sync_no_manifest_repo="$(mktemp -d)"
kit_sync_no_manifest_exit=0
kit_sync_no_manifest_output="$(cd "$kit_sync_no_manifest_repo" && CLAUDE_PROJECT_DIR="$kit_sync_no_manifest_repo" HOME="$kit_sync_no_manifest_home" bash "$REPO_ROOT/scripts/kit-sync-check.sh" --self 2>&1 1>/dev/null)" || kit_sync_no_manifest_exit=$?
if [ "$kit_sync_no_manifest_exit" -eq 1 ] \
  && printf '%s' "$kit_sync_no_manifest_output" | grep -qi "repo-relative" \
  && printf '%s' "$kit_sync_no_manifest_output" | grep -qi "deployed"; then
  echo "PASSED: kit-sync-check manifest missing via all fallback paths (Must-5(b)) -> exit 1 with non-silent message naming both paths tried"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: kit-sync-check manifest missing via all fallback paths (Must-5(b)) -> exit 1 with non-silent message naming both paths tried (exit=$kit_sync_no_manifest_exit, out=$kit_sync_no_manifest_output)"
  fail_count=$((fail_count + 1))
fi
rm -rf "$kit_sync_no_manifest_home" "$kit_sync_no_manifest_repo"

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

# Must-5(d) 回帰: private コピーが実 $HOME を触らないよう、また 4 fixture が全て
# task=agent-time-budget-hook-fixture を共有していても互いの private コピーが衝突しないよう、
# fixture ごとに専用の scratch --state-dir を割り当てる (同一 fixture 内の複数呼び出しは .active が
# 変化しないため private コピーとの不一致 (tamper) が起きず安全に共有できる)。
time_budget_state_dir_no_active="$(mktemp -d)"
time_budget_state_dir_50="$(mktemp -d)"
time_budget_state_dir_82="$(mktemp -d)"
time_budget_state_dir_110="$(mktemp -d)"
time_budget_state_dir_lane_missing="$(mktemp -d)"

run_test "agent-time-budget: .active 無し -> allow (PreToolUse)" \
  "echo '{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{}}' | bash scripts/agent-time-budget.sh --evidence-dir $time_budget_fixture_dir/no-active --state-dir $time_budget_state_dir_no_active" \
  0

run_test "agent-time-budget: PreToolUse 50% -> allow, no warning" \
  "echo '{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{}}' | bash scripts/agent-time-budget.sh --evidence-dir $time_budget_fixture_dir/heavy-50 --state-dir $time_budget_state_dir_50" \
  0

run_test "agent-time-budget: PostToolUse 50% -> allow, no warning" \
  "echo '{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{}}' | bash scripts/agent-time-budget.sh --evidence-dir $time_budget_fixture_dir/heavy-50 --state-dir $time_budget_state_dir_50" \
  0

post_warn_exit=0
post_warn_output="$(echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{}}' | bash scripts/agent-time-budget.sh --evidence-dir "$time_budget_fixture_dir/heavy-82" --state-dir "$time_budget_state_dir_82" 2>&1 1>/dev/null)" || post_warn_exit=$?
if [ "$post_warn_exit" -eq 2 ] && printf '%s' "$post_warn_output" | grep -Eiq 'heavy|warn|警告'; then
  echo "PASSED: agent-time-budget PostToolUse 82% (warn band) -> exit 2 with lane/warning hint"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget PostToolUse 82% (warn band) -> exit 2 with lane/warning hint (exit=$post_warn_exit, out=$post_warn_output)"
  fail_count=$((fail_count + 1))
fi

pre_deny_exit=0
pre_deny_output="$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' | bash scripts/agent-time-budget.sh --evidence-dir "$time_budget_fixture_dir/heavy-110" --state-dir "$time_budget_state_dir_110" 2>&1 1>/dev/null)" || pre_deny_exit=$?
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
  "echo '{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"'\"\$PWD\"'/.agent-evidence/time-budget-exceeded.md\"}}' | bash scripts/agent-time-budget.sh --evidence-dir $time_budget_fixture_dir/heavy-110 --state-dir $time_budget_state_dir_110" \
  0

lane_missing_exit=0
lane_missing_output="$(echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{}}' | bash scripts/agent-time-budget.sh --evidence-dir "$time_budget_fixture_dir/lane-missing" --state-dir "$time_budget_state_dir_lane_missing" 2>&1 1>/dev/null)" || lane_missing_exit=$?
if [ "$lane_missing_exit" -eq 2 ] && printf '%s' "$lane_missing_output" | grep -qi 'heavy'; then
  echo "PASSED: agent-time-budget lane 欠落は heavy 扱い (75min/90min warn band, PostToolUse exit 2)"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget lane 欠落は heavy 扱い (75min/90min warn band, PostToolUse exit 2) (exit=$lane_missing_exit, out=$lane_missing_output)"
  fail_count=$((fail_count + 1))
fi

missing_event_exit=0
missing_event_output="$(echo '{"tool_name":"Bash","tool_input":{}}' | bash scripts/agent-time-budget.sh --evidence-dir "$time_budget_fixture_dir/heavy-110" --state-dir "$time_budget_state_dir_110" 2>&1 1>/dev/null)" || missing_event_exit=$?
if [ "$missing_event_exit" -eq 0 ] && printf '%s' "$missing_event_output" | grep -qi 'hook_event_name'; then
  echo "PASSED: agent-time-budget hook_event_name 欠落 -> fail-safe allow (exit 0) + stderr 診断"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget hook_event_name 欠落 -> fail-safe allow (exit 0) + stderr 診断 (exit=$missing_event_exit, out=$missing_event_output)"
  fail_count=$((fail_count + 1))
fi

rm -rf "$time_budget_state_dir_no_active" "$time_budget_state_dir_50" "$time_budget_state_dir_82" \
       "$time_budget_state_dir_110" "$time_budget_state_dir_lane_missing"

# --- agent-time-budget.sh: Must-5 (.active tamper hardening — hook-private (task, started_at, lane)
# copy outside the working tree). docs/specs/guard-evasion-gates.md Must-5(a)/(b)/(c amended)/(d). ---
write_active_marker() {
  # $1=dir  $2=task  $3=seconds ago  $4=lane (空なら lane 行を省略)
  local dir="$1" task="$2" seconds_ago="$3" lane="$4"
  mkdir -p "$dir"
  {
    echo "task=$task"
    echo "started_at=$(iso8601_seconds_ago "$seconds_ago")"
    if [ -n "$lane" ]; then echo "lane=$lane"; fi
  } > "$dir/.active"
}

find_private_copy() {
  # $1=state_dir  $2=task -> 発見した private copy の絶対パスを1行出力 (無ければ空)
  find "$1" -type f -name "$2.json" 2>/dev/null | head -1
}

# Must-5(a): 対象 task を初めて見る (private コピー未存在) 時点で .active の現在値から private
# コピーが作成される (--state-dir <scratch>、実 $HOME を触らない)。
must5a_evidence_dir="$(mktemp -d)"
must5a_state_dir="$(mktemp -d)"
write_active_marker "$must5a_evidence_dir" "guard-evasion-active-tamper-a" 600 ""
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
  | bash scripts/agent-time-budget.sh --evidence-dir "$must5a_evidence_dir" --state-dir "$must5a_state_dir" >/dev/null 2>&1
must5a_private_file="$(find_private_copy "$must5a_state_dir" "guard-evasion-active-tamper-a")"
if [ -n "$must5a_private_file" ] && [ -f "$must5a_private_file" ]; then
  echo "PASSED: agent-time-budget Must-5(a) 初見で private コピーが state-dir に作成される"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget Must-5(a) 初見で private コピーが state-dir に作成される (private_file=[$must5a_private_file])"
  fail_count=$((fail_count + 1))
fi
rm -rf "$must5a_evidence_dir" "$must5a_state_dir"

# Must-5(b): 唯一の正当 re-stamp — private コピーに lane が未記録の状態から `lane=` が初めて現れた
# 時点で、private コピーの started_at/lane が更新される。
must5b_evidence_dir="$(mktemp -d)"
must5b_state_dir="$(mktemp -d)"
write_active_marker "$must5b_evidence_dir" "guard-evasion-active-tamper-b" 1800 ""   # Step 0 相当 (lane 未確定)
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
  | bash scripts/agent-time-budget.sh --evidence-dir "$must5b_evidence_dir" --state-dir "$must5b_state_dir" >/dev/null 2>&1
must5b_new_started_at="$(iso8601_seconds_ago 120)"
{
  echo "task=guard-evasion-active-tamper-b"
  echo "started_at=$must5b_new_started_at"
  echo "lane=heavy"
} > "$must5b_evidence_dir/.active"   # Step 1.5 Amendment A3 相当の re-stamp (lane= が初めて出現)
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
  | bash scripts/agent-time-budget.sh --evidence-dir "$must5b_evidence_dir" --state-dir "$must5b_state_dir" >/dev/null 2>&1
must5b_private_file="$(find_private_copy "$must5b_state_dir" "guard-evasion-active-tamper-b")"
if [ -n "$must5b_private_file" ] && [ -f "$must5b_private_file" ] \
  && grep -q "$must5b_new_started_at" "$must5b_private_file" \
  && grep -q "heavy" "$must5b_private_file"; then
  echo "PASSED: agent-time-budget Must-5(b) 唯一の正当re-stamp後にprivateコピーが新started_at/laneに更新される"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget Must-5(b) 唯一の正当re-stamp後にprivateコピーが新started_at/laneに更新される (private_file=[$must5b_private_file], content=[$(cat "$must5b_private_file" 2>/dev/null)])"
  fail_count=$((fail_count + 1))
fi
rm -rf "$must5b_evidence_dir" "$must5b_state_dir"

# Must-5(c) [amendment: falsifiable — deny-vs-allow-band]: 正当re-stamp後にさらに .active の
# started_at を書き換える tamper。private コピー側 started_at は deny帯 (ratio>=1.0)、.active側
# (tamper後) started_at は allow帯 (ratio<0.75) に設定する。private コピーが判定を支配していれば
# PreToolUse で exit 2 (deny帯の verdict がそのまま返る) になる。
must5c_evidence_dir="$(mktemp -d)"
must5c_state_dir="$(mktemp -d)"
write_active_marker "$must5c_evidence_dir" "guard-evasion-active-tamper-c" 1800 ""   # Step 0 相当
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
  | bash scripts/agent-time-budget.sh --evidence-dir "$must5c_evidence_dir" --state-dir "$must5c_state_dir" >/dev/null 2>&1
must5c_deny_started_at="$(iso8601_seconds_ago 6000)"    # 100分経過/90分 ~= 111% (deny帯)
write_active_marker "$must5c_evidence_dir" "guard-evasion-active-tamper-c" 6000 "heavy"
# ↑ .active の started_at を deny帯の値に一度合わせた状態で re-stamp (lane= 初出現) させ、private を
#   deny帯の値で確定させる (この呼び出し自体も正しく exit 2 を返すはず — 本当に時間超過しているため)。
must5c_restamp_exit=0
must5c_restamp_output="$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
  | bash scripts/agent-time-budget.sh --evidence-dir "$must5c_evidence_dir" --state-dir "$must5c_state_dir" 2>&1 1>/dev/null)" || must5c_restamp_exit=$?
# 攻撃者が .active の started_at のみを allow帯 (直近) の値に書き換える (lane はそのまま heavy)。
must5c_allow_started_at="$(iso8601_seconds_ago 300)"    # 5分経過/90分 ~= 5.6% (allow帯)
{
  echo "task=guard-evasion-active-tamper-c"
  echo "started_at=$must5c_allow_started_at"
  echo "lane=heavy"
} > "$must5c_evidence_dir/.active"
must5c_tamper_exit=0
must5c_tamper_output="$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
  | bash scripts/agent-time-budget.sh --evidence-dir "$must5c_evidence_dir" --state-dir "$must5c_state_dir" 2>&1 1>/dev/null)" || must5c_tamper_exit=$?
if [ "$must5c_restamp_exit" -eq 2 ] \
  && [ "$must5c_tamper_exit" -eq 2 ] \
  && printf '%s' "$must5c_tamper_output" | grep -Eiq 're-stamp|再スタンプ'; then
  echo "PASSED: agent-time-budget Must-5(c) deny-vs-allow-band tamper -> private優先でexit 2 + re-stamp検出メッセージ"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget Must-5(c) deny-vs-allow-band tamper -> private優先でexit 2 + re-stamp検出メッセージ (restamp_exit=$must5c_restamp_exit, tamper_exit=$must5c_tamper_exit, tamper_out=$must5c_tamper_output)"
  fail_count=$((fail_count + 1))
fi
rm -rf "$must5c_evidence_dir" "$must5c_state_dir"

# --- agent-time-budget.sh: Must-1 resume-grant lifecycle (docs/specs/harness-campaign-fix2-6.md,
# P-A) — budget-resume grant 機構。pending 発行 / 承認後の1回のみresume / 消費後の再利用拒否 /
# self-granting 順序検出。tests/fixtures/resume-grant/ ではなく scratch dir (mktemp -d) を使う
# (Must-5 の既存パターンを踏襲、時刻依存 fixture のためコミット不可)。
find_grant_file() {
  # $1=state_dir  $2=task  $3=suffix (pending/approved/consumed) -> 発見した絶対パスを1行出力
  find "$1" -type f -name "$2.resume-grant.$3" 2>/dev/null | head -1
}

# resume-grant (1): Must-1(a) — PreToolUse deny (ratio>=1.0) 発火時に <task>.resume-grant.pending
# が hook-private state に書かれる。
rg1_evidence_dir="$(mktemp -d)"
rg1_state_dir="$(mktemp -d)"
write_active_marker "$rg1_evidence_dir" "resume-grant-fixture-pending" 6000 "heavy"   # 100min/90min ~=111% (deny帯)
rg1_exit=0
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
  | bash scripts/agent-time-budget.sh --evidence-dir "$rg1_evidence_dir" --state-dir "$rg1_state_dir" >/dev/null 2>&1 || rg1_exit=$?
rg1_pending_file="$(find_grant_file "$rg1_state_dir" "resume-grant-fixture-pending" "pending")"
if [ "$rg1_exit" -eq 2 ] && [ -n "$rg1_pending_file" ] && [ -f "$rg1_pending_file" ]; then
  echo "PASSED: agent-time-budget resume-grant (1) Must-1(a) deny帯で resume-grant.pending が hook-private state に作成される"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget resume-grant (1) Must-1(a) deny帯で resume-grant.pending が hook-private state に作成される (exit=$rg1_exit, pending_file=[$rg1_pending_file])"
  fail_count=$((fail_count + 1))
fi
rm -rf "$rg1_evidence_dir" "$rg1_state_dir"

# resume-grant (2): Must-1(c) — 正当な承認順序 (approved の mtime が re-stamp の mtime より前) の場合
# のみ、private コピーの started_at を 1 回だけ resume し、適用と同時に approved を消費する
# (single-use)。mtime は touch -t で明示固定し、フレーキーな実時刻レースを避ける。
rg2_evidence_dir="$(mktemp -d)"
rg2_state_dir="$(mktemp -d)"
rg2_task="resume-grant-fixture-legit"
write_active_marker "$rg2_evidence_dir" "$rg2_task" 6000 "heavy"   # 100min/90min ~=111% (deny帯)
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
  | bash scripts/agent-time-budget.sh --evidence-dir "$rg2_evidence_dir" --state-dir "$rg2_state_dir" >/dev/null 2>&1 || true
rg2_pending_file="$(find_grant_file "$rg2_state_dir" "$rg2_task" "pending")"
rg2_approved_file="${rg2_pending_file%.pending}.approved"
mv "$rg2_pending_file" "$rg2_approved_file"   # 人間承認を模す (rename)
touch -t 202501010000.00 "$rg2_approved_file"   # 承認時刻 T1 (明示固定)
# 人間承認後、orchestrator/agent が .active started_at を fresh (allow帯) に再スタンプする。
write_active_marker "$rg2_evidence_dir" "$rg2_task" 60 "heavy"   # 1min/90min ~=1.1% (allow帯)
touch -t 202501020000.00 "$rg2_evidence_dir/.active"   # re-stamp 書込時刻 T2 (T2 > T1 = 正当な順序)
rg2_exit=0
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
  | bash scripts/agent-time-budget.sh --evidence-dir "$rg2_evidence_dir" --state-dir "$rg2_state_dir" >/dev/null 2>&1 || rg2_exit=$?
rg2_approved_still_present="no"; [ -f "$rg2_approved_file" ] && rg2_approved_still_present="yes"
if [ "$rg2_exit" -eq 0 ] && [ "$rg2_approved_still_present" = "no" ]; then
  echo "PASSED: agent-time-budget resume-grant (2) Must-1(c) 正当な承認順序 (approved mtime < re-stamp mtime) -> 1回のみresume許可 + grant消費"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget resume-grant (2) Must-1(c) 正当な承認順序 (approved mtime < re-stamp mtime) -> 1回のみresume許可 + grant消費 (exit=$rg2_exit, approved_still_present=$rg2_approved_still_present)"
  fail_count=$((fail_count + 1))
fi
rm -rf "$rg2_evidence_dir" "$rg2_state_dir"

# resume-grant (2b): Must-1(b)/(c) — 承認経路が rename ではなく **copy** (`cp`) だった場合、元の
# .pending が consume 後も残置されない (P-E: 2026-07-05 のこの campaign 自身の live resume-grant
# 使用で cp 経路の残置が実際に確認された latent gap の回帰防止)。
rg2b_evidence_dir="$(mktemp -d)"
rg2b_state_dir="$(mktemp -d)"
rg2b_task="resume-grant-fixture-legit-cp"
write_active_marker "$rg2b_evidence_dir" "$rg2b_task" 6000 "heavy"
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
  | bash scripts/agent-time-budget.sh --evidence-dir "$rg2b_evidence_dir" --state-dir "$rg2b_state_dir" >/dev/null 2>&1 || true
rg2b_pending_file="$(find_grant_file "$rg2b_state_dir" "$rg2b_task" "pending")"
rg2b_approved_file="${rg2b_pending_file%.pending}.approved"
cp "$rg2b_pending_file" "$rg2b_approved_file"   # 人間承認を模す (copy — rename ではない)
touch -t 202501010000.00 "$rg2b_approved_file"
write_active_marker "$rg2b_evidence_dir" "$rg2b_task" 60 "heavy"
touch -t 202501020000.00 "$rg2b_evidence_dir/.active"
rg2b_exit=0
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
  | bash scripts/agent-time-budget.sh --evidence-dir "$rg2b_evidence_dir" --state-dir "$rg2b_state_dir" >/dev/null 2>&1 || rg2b_exit=$?
rg2b_approved_gone="no"; [ ! -f "$rg2b_approved_file" ] && rg2b_approved_gone="yes"
rg2b_pending_gone="no"; [ ! -f "$rg2b_pending_file" ] && rg2b_pending_gone="yes"
if [ "$rg2b_exit" -eq 0 ] && [ "$rg2b_approved_gone" = "yes" ] && [ "$rg2b_pending_gone" = "yes" ]; then
  echo "PASSED: agent-time-budget resume-grant (2b) Must-1(b)/(c) cp承認経路でもconsume時にpendingが残置されない (P-E cleanup)"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget resume-grant (2b) Must-1(b)/(c) cp承認経路でもconsume時にpendingが残置されない (P-E cleanup) (exit=$rg2b_exit, approved_gone=$rg2b_approved_gone, pending_gone=$rg2b_pending_gone)"
  fail_count=$((fail_count + 1))
fi
rm -rf "$rg2b_evidence_dir" "$rg2b_state_dir"

# resume-grant (3): Must-1(d) — self-granting 順序検出。approved の mtime が re-stamp (.active 書込)
# の mtime **以降** (後付け) の場合は tamper 同様に拒否する。
rg3_evidence_dir="$(mktemp -d)"
rg3_state_dir="$(mktemp -d)"
rg3_task="resume-grant-fixture-selfgrant"
rg3_repo_key="$(printf '%s' "$REPO_ROOT" | sed -e 's#^/##' -e 's#/#_#g')"
rg3_private_dir="$rg3_state_dir/$rg3_repo_key"
mkdir -p "$rg3_private_dir"
rg3_deny_started_at="$(iso8601_seconds_ago 6000)"   # 100min/90min ~=111% (deny帯, private側)
printf '{"task": "%s", "started_at": "%s", "lane": "heavy"}\n' "$rg3_task" "$rg3_deny_started_at" > "$rg3_private_dir/$rg3_task.json"
# .active に fresh (allow帯) started_at を書き、mtime を T1 (先) に固定する -> 「re-stamp が先に起きた」。
write_active_marker "$rg3_evidence_dir" "$rg3_task" 60 "heavy"
touch -t 202501010000.00 "$rg3_evidence_dir/.active"
# approved grant を re-stamp より後 (T2 > T1) に「後付け」で作成する -> self-granting の疑い。
printf '{"task": "%s", "private_started_at": "%s", "lane": "heavy", "requested_at": "2025-01-01T00:00:00Z"}\n' \
  "$rg3_task" "$rg3_deny_started_at" > "$rg3_private_dir/$rg3_task.resume-grant.approved"
touch -t 202501020000.00 "$rg3_private_dir/$rg3_task.resume-grant.approved"
rg3_exit=0
rg3_output="$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
  | bash scripts/agent-time-budget.sh --evidence-dir "$rg3_evidence_dir" --state-dir "$rg3_state_dir" 2>&1 1>/dev/null)" || rg3_exit=$?
if [ "$rg3_exit" -eq 2 ] && printf '%s' "$rg3_output" | grep -Eiq 'self-grant|後付け'; then
  echo "PASSED: agent-time-budget resume-grant (3) Must-1(d) self-granting 順序検出 (approved mtime >= re-stamp mtime) -> 拒否"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget resume-grant (3) Must-1(d) self-granting 順序検出 (approved mtime >= re-stamp mtime) -> 拒否 (exit=$rg3_exit, out=$rg3_output)"
  fail_count=$((fail_count + 1))
fi
rm -rf "$rg3_evidence_dir" "$rg3_state_dir"

# resume-grant (4): Must-1(c) 消費済み — 一度 consume された grant は再利用できない。approved が
# 存在しない (=既に消費済み) 状態で再度 .active が書き換えられても、grant 不在のため既存の
# tamper 判定 (Must-5(c)) に戻り deny する (single-use の帰結)。
rg4_evidence_dir="$(mktemp -d)"
rg4_state_dir="$(mktemp -d)"
rg4_task="resume-grant-fixture-reuse-rejected"
rg4_repo_key="$(printf '%s' "$REPO_ROOT" | sed -e 's#^/##' -e 's#/#_#g')"
rg4_private_dir="$rg4_state_dir/$rg4_repo_key"
mkdir -p "$rg4_private_dir"
rg4_deny_started_at="$(iso8601_seconds_ago 6000)"   # 100min/90min ~=111% (deny帯, private側)
printf '{"task": "%s", "started_at": "%s", "lane": "heavy"}\n' "$rg4_task" "$rg4_deny_started_at" > "$rg4_private_dir/$rg4_task.json"
# grant は既に消費済み (approved ファイル無し)。.active だけが別の値に書き換えられている状態を装う。
write_active_marker "$rg4_evidence_dir" "$rg4_task" 60 "heavy"
rg4_exit=0
rg4_output="$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
  | bash scripts/agent-time-budget.sh --evidence-dir "$rg4_evidence_dir" --state-dir "$rg4_state_dir" 2>&1 1>/dev/null)" || rg4_exit=$?
if [ "$rg4_exit" -eq 2 ] && printf '%s' "$rg4_output" | grep -Eiq 're-stamp|再スタンプ'; then
  echo "PASSED: agent-time-budget resume-grant (4) Must-1(c) 消費済みgrant再利用試行 -> grant不在のためtamper判定に戻りexit 2"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-time-budget resume-grant (4) Must-1(c) 消費済みgrant再利用試行 -> grant不在のためtamper判定に戻りexit 2 (exit=$rg4_exit, out=$rg4_output)"
  fail_count=$((fail_count + 1))
fi
rm -rf "$rg4_evidence_dir" "$rg4_state_dir"

# --- Must-2 (dot_claude/skills/proven-done/SKILL.md stall 検出プロトコル, harness-campaign-fix2-6
# P-A) 定義相当のテスト — SKILL.md はプロトコルの正本 (doc-only entrypoint, 実行可能スクリプトを
# 持たない) であるため、Step 2.7 と同じ「自己申告を信用せず ls で確認する」stall 判定ロジック自体を
# fixture で模倣し健全性を確認する。stall の定義 (Must-2(a)(i)): 完了報告の tool-call 証跡 (commands
# ログ) に Write/Edit/Bash がゼロ、かつ orchestrator の ls 実在確認でも新規ファイルが無い。
detect_stall() {
  # $1 = subagent の commands.txt (tool-call 証跡の自己申告)  $2 = orchestrator ls 実測ディレクトリ
  # exit 1 = stall / exit 0 = not stall
  local commands_log="$1" probe_dir="$2"
  local has_tool_evidence=0
  if [ -s "$commands_log" ] && grep -qiE 'Write|Edit|Bash' "$commands_log"; then
    has_tool_evidence=1
  fi
  local ls_has_new_files=0
  if [ -n "$(find "$probe_dir" -type f 2>/dev/null)" ]; then
    ls_has_new_files=1
  fi
  if [ "$has_tool_evidence" -eq 0 ] && [ "$ls_has_new_files" -eq 0 ]; then
    return 1   # stall: 証跡ゼロ かつ ls 実在確認でも新規ファイル無し
  fi
  return 0   # not stall
}

stall_fixture_dir="$(mktemp -d)"
mkdir -p "$stall_fixture_dir/empty-probe"
: > "$stall_fixture_dir/commands-empty.txt"   # 自己申告のみ、tool-call 証跡ゼロ
if ! detect_stall "$stall_fixture_dir/commands-empty.txt" "$stall_fixture_dir/empty-probe"; then
  echo "PASSED: stall detection (Must-2) 証跡ゼロ + ls 新規ファイル無し -> stall と判定"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: stall detection (Must-2) 証跡ゼロ + ls 新規ファイル無し -> stall と判定"
  fail_count=$((fail_count + 1))
fi

mkdir -p "$stall_fixture_dir/nonempty-probe"
echo "actual file written" > "$stall_fixture_dir/nonempty-probe/output.txt"
if detect_stall "$stall_fixture_dir/commands-empty.txt" "$stall_fixture_dir/nonempty-probe"; then
  echo "PASSED: stall detection (Must-2) 証跡ゼロでも ls で新規ファイル実在確認 -> stall ではない"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: stall detection (Must-2) 証跡ゼロでも ls で新規ファイル実在確認 -> stall ではない"
  fail_count=$((fail_count + 1))
fi
rm -rf "$stall_fixture_dir"

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

# --- agent-evidence-gate.sh Must-6(c)/(d)/(f): in-place direct execution of verify-guard-integrity.sh
# (not round-log scanning) on status:complete; waiver-proof (docs/specs/guard-evasion-gates.md). ---
real_spec_hash="$({ command -v sha256sum >/dev/null 2>&1 && sha256sum docs/specs/agent-time-budget-hook.md || shasum -a 256 docs/specs/agent-time-budget-hook.md; } | awk '{print $1}')"
tampered_hash="$(printf 'definitely-wrong-hash-marker' | { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } | awk '{print $1}')"
{
  echo "task=agent-time-budget-hook"
  echo "started_at=2026-01-01T00:00:00Z"
  echo "lane=heavy"
  echo "spec_sha256=$tampered_hash"
} > "$AEG_BASE/guard-integrity-tampered-clean-log/.active"
{
  echo "task=agent-time-budget-hook"
  echo "started_at=2026-01-01T00:00:00Z"
  echo "lane=heavy"
  echo "spec_sha256=$real_spec_hash"
} > "$AEG_BASE/guard-integrity-legitimate/.active"
{
  echo "task=agent-time-budget-hook"
  echo "started_at=2026-01-01T00:00:00Z"
  echo "lane=heavy"
  echo "spec_sha256=$tampered_hash"
} > "$AEG_BASE/guard-integrity-tampered-quarantine-waiver-attempt/.active"

guard_gate_exit=0
guard_gate_output="$(bash scripts/agent-evidence-gate.sh --evidence-dir "$AEG_BASE/guard-integrity-tampered-clean-log" < /dev/null 2>&1 1>/dev/null)" || guard_gate_exit=$?
if [ "$guard_gate_exit" -eq 2 ] && printf '%s' "$guard_gate_output" | grep -qi 'verify-guard-integrity\|POLICY VIOLATION'; then
  echo "PASSED: agent-evidence-gate Must-6(c)/(d) tampered spec + clean/absent round-log -> block via in-place direct execution"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-evidence-gate Must-6(c)/(d) tampered spec + clean/absent round-log -> block via in-place direct execution (exit=$guard_gate_exit, out=$guard_gate_output)"
  fail_count=$((fail_count + 1))
fi

run_test "agent-evidence-gate Must-6(d) all-legitimate (valid spec_sha256) -> allow" \
  "bash scripts/agent-evidence-gate.sh --evidence-dir $AEG_BASE/guard-integrity-legitimate < /dev/null" \
  0

guard_waiver_exit=0
guard_waiver_output="$(bash scripts/agent-evidence-gate.sh --evidence-dir "$AEG_BASE/guard-integrity-tampered-quarantine-waiver-attempt" --quarantine "$AEG_BASE/guard-integrity-tampered-quarantine-waiver-attempt/quarantine.yml" < /dev/null 2>&1 1>/dev/null)" || guard_waiver_exit=$?
if [ "$guard_waiver_exit" -eq 2 ]; then
  echo "PASSED: agent-evidence-gate Must-6(f) quarantine substring waiver ('verify-guard-integrity.sh') does NOT waive -> still block"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-evidence-gate Must-6(f) quarantine substring waiver ('verify-guard-integrity.sh') does NOT waive -> still block (exit=$guard_waiver_exit, out=$guard_waiver_output)"
  fail_count=$((fail_count + 1))
fi

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

# --- verify-guard-integrity.sh: spec-amend subcheck (Must-2) + stash-escape subcheck (Must-4),
# stash-baseline recording (Must-3). Wire-first note: this script is intentionally NOT wired into
# any entrypoint yet (packet P12 of docs/specs/guard-evasion-gates.md; Step-4 battery / Stop hook /
# kit-manifest wiring is packet P4's scope) — standalone-runnable via --evidence-dir only.
GUARD_INTEGRITY_SCRIPT="scripts/verify-guard-integrity.sh"
guard_integrity_script_abs="$REPO_ROOT/$GUARD_INTEGRITY_SCRIPT"
spec_amend_base="tests/fixtures/guard-evasion-gates/spec-amend"
spec_amend_specs_dir="$spec_amend_base/specs"

sha256_of_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

write_spec_amend_active() {
  # $1=dir  $2=include_stamp(0/1)  $3=stamp_value
  local dir="$1" include_stamp="$2" stamp_value="$3"
  mkdir -p "$dir"
  {
    echo "task=fixture-task"
    echo "started_at=2026-01-01T00:00:00Z"
    echo "lane=heavy"
    if [ "$include_stamp" -eq 1 ]; then echo "spec_sha256=$stamp_value"; fi
  } > "$dir/.active"
}

current_spec_hash="$(sha256_of_file "$spec_amend_specs_dir/fixture-task.md")"
stale_hash="$(printf 'stale-spec-marker' | { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } | awk '{print $1}')"

write_spec_amend_active "$spec_amend_base/no-stamp" 0 ""
write_spec_amend_active "$spec_amend_base/hash-match" 1 "$current_spec_hash"
write_spec_amend_active "$spec_amend_base/mismatch-no-approval" 1 "$stale_hash"
write_spec_amend_active "$spec_amend_base/mismatch-invalid-approval" 1 "$stale_hash"
write_spec_amend_active "$spec_amend_base/mismatch-approved" 1 "$stale_hash"

mkdir -p "$spec_amend_base/mismatch-invalid-approval"
cat > "$spec_amend_base/mismatch-invalid-approval/oracle-change-approval.json" <<JSON
{
  "spec_path": "docs/specs/fixture-task.md",
  "old_spec_sha256": "$stale_hash",
  "new_spec_sha256": "$stale_hash",
  "approved_at": "2026-01-01T00:00:00Z",
  "approval_summary": "test fixture: approval present but new_spec_sha256 not updated to current (invalid)"
}
JSON

mkdir -p "$spec_amend_base/mismatch-approved"
cat > "$spec_amend_base/mismatch-approved/oracle-change-approval.json" <<JSON
{
  "spec_path": "docs/specs/fixture-task.md",
  "old_spec_sha256": "$stale_hash",
  "new_spec_sha256": "$current_spec_hash",
  "approved_at": "2026-01-01T00:00:00Z",
  "approval_summary": "test fixture: approved spec amend"
}
JSON

run_test "verify-guard-integrity spec-amend (a) stamp未記録 -> 非対象 exit 0" \
  "bash $GUARD_INTEGRITY_SCRIPT --evidence-dir $spec_amend_base/no-stamp --specs-dir $spec_amend_specs_dir" \
  0

run_test "verify-guard-integrity spec-amend (b) hash一致 -> exit 0" \
  "bash $GUARD_INTEGRITY_SCRIPT --evidence-dir $spec_amend_base/hash-match --specs-dir $spec_amend_specs_dir" \
  0

spec_amend_mismatch_exit=0
spec_amend_mismatch_output="$(bash $GUARD_INTEGRITY_SCRIPT --evidence-dir "$spec_amend_base/mismatch-no-approval" --specs-dir "$spec_amend_specs_dir" 2>&1 1>/dev/null)" || spec_amend_mismatch_exit=$?
if [ "$spec_amend_mismatch_exit" -ne 0 ] \
  && printf '%s' "$spec_amend_mismatch_output" | grep -q "POLICY VIOLATION" \
  && printf '%s' "$spec_amend_mismatch_output" | grep -q "fixture-task.md"; then
  echo "PASSED: verify-guard-integrity spec-amend (c) 未承認 mismatch -> non-zero + POLICY VIOLATION naming spec file"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: verify-guard-integrity spec-amend (c) 未承認 mismatch -> non-zero + POLICY VIOLATION naming spec file (exit=$spec_amend_mismatch_exit, out=$spec_amend_mismatch_output)"
  fail_count=$((fail_count + 1))
fi

spec_amend_invalid_approval_exit=0
spec_amend_invalid_approval_output="$(bash $GUARD_INTEGRITY_SCRIPT --evidence-dir "$spec_amend_base/mismatch-invalid-approval" --specs-dir "$spec_amend_specs_dir" 2>&1 1>/dev/null)" || spec_amend_invalid_approval_exit=$?
if [ "$spec_amend_invalid_approval_exit" -ne 0 ] && printf '%s' "$spec_amend_invalid_approval_output" | grep -q "POLICY VIOLATION"; then
  echo "PASSED: verify-guard-integrity spec-amend (c) 無効 approval (new_spec_sha256 不一致) -> non-zero"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: verify-guard-integrity spec-amend (c) 無効 approval (new_spec_sha256 不一致) -> non-zero (exit=$spec_amend_invalid_approval_exit, out=$spec_amend_invalid_approval_output)"
  fail_count=$((fail_count + 1))
fi

run_test "verify-guard-integrity spec-amend (d) 承認済み amend -> exit 0" \
  "bash $GUARD_INTEGRITY_SCRIPT --evidence-dir $spec_amend_base/mismatch-approved --specs-dir $spec_amend_specs_dir" \
  0

# --- verify-guard-integrity.sh: Must-3 stash-baseline recording (falsifiable diff fixture) +
# Must-4 stash-escape subcheck (a)/(b)/(c). git stash 状態はコミットできないため scratch git repo を
# 動的に組み立てる (tests/run-shell-tests.sh:293- setup_verify_wiring_long_lived_branch_fixture と同じ
# パターン)。CLAUDE_PROJECT_DIR は defensive に unset し、scratch repo 自身の toplevel を
# verify-guard-integrity.sh に解決させる。
setup_stash_escape_base_repo() {
  # tracked: task-file.txt (task 対象扱い, wiring-map.json changes[].file に列挙) /
  # unrelated-file.txt (無関係ファイル)。.agent-evidence/wiring-map.json も同時に用意する。
  local repo_dir
  repo_dir="$(mktemp -d)"
  (
    cd "$repo_dir"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    echo "task file v1" > task-file.txt
    echo "unrelated file v1" > unrelated-file.txt
    git add task-file.txt unrelated-file.txt
    git commit -q -m "base commit"
    mkdir -p .agent-evidence
    cat > .agent-evidence/wiring-map.json <<'JSON'
{"changes": [{"symbol": "Fixture.taskFile", "file": "task-file.txt", "wired_at": ["n/a"], "reachable_from": "test"}], "quarantined_tests": []}
JSON
  ) >/dev/null
  printf '%s' "$repo_dir"
}

# Must-3: baseline 記録 (Step-0-simulation) が git stash list の実出力と diff/文字列比較で完全一致する
stash_baseline_repo="$(setup_stash_escape_base_repo)"
(
  cd "$stash_baseline_repo"
  echo "pre-existing unrelated stash source" >> unrelated-file.txt
  git stash push -q -m "pre-existing user WIP" -- unrelated-file.txt
) >/dev/null
stash_baseline_actual="$(cd "$stash_baseline_repo" && unset CLAUDE_PROJECT_DIR && git stash list)"
(cd "$stash_baseline_repo" && unset CLAUDE_PROJECT_DIR && bash "$guard_integrity_script_abs" --record-stash-baseline --evidence-dir .agent-evidence) >/dev/null
stash_baseline_recorded="$(cat "$stash_baseline_repo/.agent-evidence/stash-baseline.txt" 2>/dev/null || true)"
if [ "$stash_baseline_recorded" = "$stash_baseline_actual" ] && [ -n "$stash_baseline_actual" ]; then
  echo "PASSED: verify-guard-integrity stash-baseline (Must-3) Step-0-simulation 記録が git stash list と完全一致"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: verify-guard-integrity stash-baseline (Must-3) Step-0-simulation 記録が git stash list と完全一致 (recorded=[$stash_baseline_recorded] actual=[$stash_baseline_actual])"
  fail_count=$((fail_count + 1))
fi
rm -rf "$stash_baseline_repo"

# Must-4 (a): baseline 記録後に新規 stash が追加されていない (既存 stash のみ) -> exit 0
stash_a_repo="$(setup_stash_escape_base_repo)"
(
  cd "$stash_a_repo"
  echo "pre-existing unrelated stash" >> unrelated-file.txt
  git stash push -q -m "pre-existing user WIP" -- unrelated-file.txt
) >/dev/null
(cd "$stash_a_repo" && unset CLAUDE_PROJECT_DIR && bash "$guard_integrity_script_abs" --record-stash-baseline --evidence-dir .agent-evidence) >/dev/null
run_test "verify-guard-integrity stash-escape (a) baseline後に新規stash無し -> exit 0" \
  "(cd '$stash_a_repo' && unset CLAUDE_PROJECT_DIR && bash '$guard_integrity_script_abs' --evidence-dir .agent-evidence)" \
  0
rm -rf "$stash_a_repo"

# Must-4 (b): baseline 記録後の新規 stash が無関係ファイルのみをタッチ (既存 stash の index シフトも
# 含めて index-shift-safe な正規化比較を検証する) -> exit 0
stash_b_repo="$(setup_stash_escape_base_repo)"
(
  cd "$stash_b_repo"
  echo "pre-existing unrelated stash" >> unrelated-file.txt
  git stash push -q -m "pre-existing user WIP" -- unrelated-file.txt
) >/dev/null
(cd "$stash_b_repo" && unset CLAUDE_PROJECT_DIR && bash "$guard_integrity_script_abs" --record-stash-baseline --evidence-dir .agent-evidence) >/dev/null
(
  cd "$stash_b_repo"
  echo "another unrelated change" >> unrelated-file.txt
  git stash push -q -m "new unrelated WIP"
) >/dev/null
run_test "verify-guard-integrity stash-escape (b) 無関係な新規stash (既存stashのindexシフト込み) -> exit 0" \
  "(cd '$stash_b_repo' && unset CLAUDE_PROJECT_DIR && bash '$guard_integrity_script_abs' --evidence-dir .agent-evidence)" \
  0
rm -rf "$stash_b_repo"

# Must-4 (c): baseline 記録後の新規 stash がタスク対象ファイル (wiring-map.json changes[].file) を
# タッチ -> POLICY VIOLATION (stash ref + ファイル名を明示)
stash_c_repo="$(setup_stash_escape_base_repo)"
(
  cd "$stash_c_repo"
  echo "pre-existing unrelated stash" >> unrelated-file.txt
  git stash push -q -m "pre-existing user WIP" -- unrelated-file.txt
) >/dev/null
(cd "$stash_c_repo" && unset CLAUDE_PROJECT_DIR && bash "$guard_integrity_script_abs" --record-stash-baseline --evidence-dir .agent-evidence) >/dev/null
(
  cd "$stash_c_repo"
  echo "task file v2 (should not be hidden via stash)" >> task-file.txt
  git stash push -q -m "escape attempt"
) >/dev/null
stash_c_exit=0
stash_c_output="$(cd "$stash_c_repo" && unset CLAUDE_PROJECT_DIR && bash "$guard_integrity_script_abs" --evidence-dir .agent-evidence 2>&1 1>/dev/null)" || stash_c_exit=$?
if [ "$stash_c_exit" -ne 0 ] \
  && printf '%s' "$stash_c_output" | grep -q "POLICY VIOLATION" \
  && printf '%s' "$stash_c_output" | grep -q "task-file.txt" \
  && printf '%s' "$stash_c_output" | grep -q "stash@{0}"; then
  echo "PASSED: verify-guard-integrity stash-escape (c) タスク対象ファイルをタッチする新規stash -> POLICY VIOLATION naming stash ref + file"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: verify-guard-integrity stash-escape (c) タスク対象ファイルをタッチする新規stash -> POLICY VIOLATION naming stash ref + file (exit=$stash_c_exit, out=$stash_c_output)"
  fail_count=$((fail_count + 1))
fi
rm -rf "$stash_c_repo"

# --- agent-policy-hook.sh: Must-18 orchestrator-direct-implementation (PreToolUse blocking) +
# first-ever regression cases for the pre-existing PostToolUse no-prod-doubles/test-bypass checks
# (docs/specs/harness-campaign-fix2-6.md P-C, Warning 6: this script had zero tests before). ---
APH_SCRIPT="scripts/agent-policy-hook.sh"
aph_evidence_dir="$(mktemp -d)"
{
  echo "task=aph-fixture"
  echo "started_at=2026-01-01T00:00:00Z"
  echo "lane=heavy"
} > "$aph_evidence_dir/.active"
aph_prod_dir="$(mktemp -d)"
echo "console.log('prod file')" > "$aph_prod_dir/prodfile.ts"
mkdir -p "$aph_prod_dir/tests"
echo "console.log('test file')" > "$aph_prod_dir/tests/foo.ts"

aph_block_exit=0
aph_block_output="$(env -u CLAUDE_CODE_CHILD_SESSION bash -c "echo '{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$aph_prod_dir/prodfile.ts\"}}' | EVIDENCE_DIR_OVERRIDE='$aph_evidence_dir' bash $APH_SCRIPT" 2>&1 1>/dev/null)" || aph_block_exit=$?
if [ "$aph_block_exit" -eq 2 ] && printf '%s' "$aph_block_output" | grep -qi "orchestrator-direct-implementation"; then
  echo "PASSED: agent-policy-hook Must-18 orchestrator-direct-implementation (no child session, prod path, .active present) -> exit 2"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: agent-policy-hook Must-18 orchestrator-direct-implementation (no child session, prod path, .active present) -> exit 2 (exit=$aph_block_exit, out=$aph_block_output)"
  fail_count=$((fail_count + 1))
fi

run_test "agent-policy-hook Must-18 subagent (CLAUDE_CODE_CHILD_SESSION=1) -> allow" \
  "CLAUDE_CODE_CHILD_SESSION=1 bash -c \"echo '{\\\"hook_event_name\\\":\\\"PreToolUse\\\",\\\"tool_name\\\":\\\"Write\\\",\\\"tool_input\\\":{\\\"file_path\\\":\\\"$aph_prod_dir/prodfile.ts\\\"}}' | EVIDENCE_DIR_OVERRIDE='$aph_evidence_dir' bash $APH_SCRIPT\"" \
  0

run_test "agent-policy-hook Must-18 no .active -> allow" \
  "env -u CLAUDE_CODE_CHILD_SESSION bash -c \"echo '{\\\"hook_event_name\\\":\\\"PreToolUse\\\",\\\"tool_name\\\":\\\"Write\\\",\\\"tool_input\\\":{\\\"file_path\\\":\\\"$aph_prod_dir/prodfile.ts\\\"}}' | EVIDENCE_DIR_OVERRIDE='$(mktemp -d)' bash $APH_SCRIPT\"" \
  0

run_test "agent-policy-hook Must-18 test-dir path -> allow" \
  "env -u CLAUDE_CODE_CHILD_SESSION bash -c \"echo '{\\\"hook_event_name\\\":\\\"PreToolUse\\\",\\\"tool_name\\\":\\\"Write\\\",\\\"tool_input\\\":{\\\"file_path\\\":\\\"$aph_prod_dir/tests/foo.ts\\\"}}' | EVIDENCE_DIR_OVERRIDE='$aph_evidence_dir' bash $APH_SCRIPT\"" \
  0

# Must-18 allowlist escape: ci/allowlist.yml contains a matching rule comment/entry -> allow even
# though the other conditions (no child session, prod path, .active present) would otherwise block.
aph_allowlist_dir="$(mktemp -d)"
mkdir -p "$aph_allowlist_dir/ci"
cat > "$aph_allowlist_dir/ci/allowlist.yml" <<'YAML'
entries:
  - rule: orchestrator-direct-implementation
    path: "prodfile.ts"
    owner: "@test"
    reason: "fixture waiver for test"
    expires_at: "2099-01-01"
YAML
cp -r "$aph_prod_dir"/* "$aph_allowlist_dir/" 2>/dev/null
run_test "agent-policy-hook Must-18 ci/allowlist.yml waiver present -> allow" \
  "env -u CLAUDE_CODE_CHILD_SESSION bash -c \"cd '$aph_allowlist_dir' && echo '{\\\"hook_event_name\\\":\\\"PreToolUse\\\",\\\"tool_name\\\":\\\"Write\\\",\\\"tool_input\\\":{\\\"file_path\\\":\\\"$aph_allowlist_dir/prodfile.ts\\\"}}' | CLAUDE_PROJECT_DIR='$aph_allowlist_dir' EVIDENCE_DIR_OVERRIDE='$aph_evidence_dir' bash '$REPO_ROOT/$APH_SCRIPT'\"" \
  0

# Regression (Warning 6: this script had zero tests before P-C): pre-existing PostToolUse
# no-prod-doubles / test-bypass behavior is unaffected by the new PreToolUse branch.
aph_bad_dir="$(mktemp -d)"
echo "jest.mock('./userService');" > "$aph_bad_dir/service.ts"
run_test "agent-policy-hook PostToolUse regression: prod-double pattern in non-test file -> exit 2" \
  "echo '{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$aph_bad_dir/service.ts\"}}' | bash $APH_SCRIPT" \
  2

aph_clean_dir="$(mktemp -d)"
echo 'export function add(a: number, b: number) { return a + b; }' > "$aph_clean_dir/math.ts"
run_test "agent-policy-hook PostToolUse regression: clean file -> exit 0" \
  "echo '{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$aph_clean_dir/math.ts\"}}' | bash $APH_SCRIPT" \
  0

rm -rf "$aph_evidence_dir" "$aph_prod_dir" "$aph_allowlist_dir" "$aph_bad_dir" "$aph_clean_dir"

# --- scripts/portable.sh: Must-19/22 portable_timeout + portable_http_probe (primary path +
# forced-fallback path each). docs/specs/harness-campaign-fix2-6.md P-D. ---
PORTABLE_SCRIPT="$REPO_ROOT/scripts/portable.sh"
# resolve the REAL python3 binary (not a pyenv/asdf shim script, which may itself depend on
# grep/sed/tr being on PATH) so the PATH-restricted fallback subshell can actually execute it.
real_python3="$(python3 -c 'import sys; print(sys.executable)' 2>/dev/null)"
[ -x "$real_python3" ] || real_python3="$(command -v python3)"
real_bash="$(command -v bash)"
real_perl="$(command -v perl)"
real_sleep="$(command -v sleep)"

# portable_timeout (1): primary path (gtimeout/timeout available in normal PATH) actually bounds
# a long-running command instead of waiting for it to finish.
pt_primary_start="$(date +%s)"
pt_primary_exit=0
(source "$PORTABLE_SCRIPT"; portable_timeout 1 sleep 5) >/dev/null 2>&1 || pt_primary_exit=$?
pt_primary_elapsed=$(( $(date +%s) - pt_primary_start ))
if [ "$pt_primary_exit" -ne 0 ] && [ "$pt_primary_elapsed" -le 3 ]; then
  echo "PASSED: portable_timeout (1) primary path (gtimeout/timeout) bounds a long command (elapsed=${pt_primary_elapsed}s, exit=$pt_primary_exit)"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: portable_timeout (1) primary path (gtimeout/timeout) bounds a long command (elapsed=${pt_primary_elapsed}s, exit=$pt_primary_exit)"
  fail_count=$((fail_count + 1))
fi

# portable_timeout (2): forced-fallback path — PATH restricted to only perl/sleep/bash (no
# gtimeout/timeout) — perl alarm() fallback still bounds the command.
pt_fallback_dir="$(mktemp -d)"
ln -s "$real_perl" "$pt_fallback_dir/perl"
ln -s "$real_sleep" "$pt_fallback_dir/sleep"
ln -s "$real_bash" "$pt_fallback_dir/bash"
pt_fallback_start="$(date +%s)"
pt_fallback_exit=0
PATH="$pt_fallback_dir" "$real_bash" -c "source '$PORTABLE_SCRIPT'; portable_timeout 1 sleep 5" >/dev/null 2>&1 || pt_fallback_exit=$?
pt_fallback_elapsed=$(( $(date +%s) - pt_fallback_start ))
if [ "$pt_fallback_exit" -ne 0 ] && [ "$pt_fallback_elapsed" -le 3 ]; then
  echo "PASSED: portable_timeout (2) forced-fallback path (perl alarm, no gtimeout/timeout on PATH) bounds a long command (elapsed=${pt_fallback_elapsed}s, exit=$pt_fallback_exit)"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: portable_timeout (2) forced-fallback path (perl alarm, no gtimeout/timeout on PATH) bounds a long command (elapsed=${pt_fallback_elapsed}s, exit=$pt_fallback_exit)"
  fail_count=$((fail_count + 1))
fi
rm -rf "$pt_fallback_dir"

# portable_http_probe fixture server (real python3, not a shim, so it survives PATH restriction below)
php_test_dir="$(mktemp -d)"
echo "portable_http_probe fixture" > "$php_test_dir/index.html"
php_port=18391
(cd "$php_test_dir" && "$real_python3" -m http.server "$php_port" >/dev/null 2>&1 &)
php_server_pid_pattern="http.server $php_port"
sleep 1

# portable_http_probe (1): primary path (curl available)
run_test "portable_http_probe (1) primary path (curl) -> 200 matches" \
  "(source $PORTABLE_SCRIPT; portable_http_probe http://127.0.0.1:$php_port/index.html 200)" \
  0

run_test "portable_http_probe (1b) primary path (curl) -> mismatch expected status -> non-zero" \
  "(source $PORTABLE_SCRIPT; portable_http_probe http://127.0.0.1:$php_port/index.html 404)" \
  1

# portable_http_probe (2): forced-fallback path — PATH restricted to only the REAL python3 binary
# (no curl/wget) — python3 urllib fallback still probes correctly.
php_fallback_dir="$(mktemp -d)"
ln -s "$real_python3" "$php_fallback_dir/python3"
ln -s "$real_bash" "$php_fallback_dir/bash"
run_test "portable_http_probe (2) forced-fallback path (python3 urllib, no curl/wget on PATH) -> 200 matches" \
  "PATH='$php_fallback_dir' $real_bash -c \"source '$PORTABLE_SCRIPT'; portable_http_probe http://127.0.0.1:$php_port/index.html 200\"" \
  0
rm -rf "$php_fallback_dir" "$php_test_dir"
pkill -f "$php_server_pid_pattern" 2>/dev/null || true

# --- BASE_REF fallback: origin/HEAD の無い checkout で abort しない (kit 1.3.1 回帰) ---
# actions/checkout は refs/remotes/origin/HEAD を設定しないため、BASE_REF 未設定の CI step では
# `base="${BASE_REF:-$(git symbolic-ref refs/remotes/origin/HEAD ...)}"` の command substitution が
# exit 128 になり、set -euo pipefail 下でスクリプトごと abort していた
# (native-trace pr-gate policy job が全 PR で出力ゼロ・exit 128 になった実測事故)。
# 期待挙動: fallback が空 -> origin/main -> rev-parse 検証で不在を吸収し、正常判定まで到達する。
no_origin_head_dir="$(mktemp -d)"
git -C "$no_origin_head_dir" init -q
git -C "$no_origin_head_dir" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
printf 'rules: []\n' > "$no_origin_head_dir/wiring_manifest.yml"

run_test "verify-no-stub-placeholder: origin/HEAD なし + BASE_REF 未設定 -> exit 0 (128 abort しない)" \
  "env -u BASE_REF CLAUDE_PROJECT_DIR=$no_origin_head_dir bash $REPO_ROOT/scripts/verify-no-stub-placeholder.sh" \
  0

run_test "verify-no-prod-doubles: origin/HEAD なし + BASE_REF 未設定 -> exit 0 (128 abort しない)" \
  "env -u BASE_REF CLAUDE_PROJECT_DIR=$no_origin_head_dir bash $REPO_ROOT/scripts/verify-no-prod-doubles.sh" \
  0

run_test "verify-test-bypass: origin/HEAD なし + BASE_REF 未設定 -> exit 0 (128 abort しない)" \
  "env -u BASE_REF CLAUDE_PROJECT_DIR=$no_origin_head_dir bash $REPO_ROOT/scripts/verify-test-bypass.sh" \
  0

run_test "verify-wiring: origin/HEAD なし + BASE_REF 未設定 -> exit 0 (128 abort しない)" \
  "env -u BASE_REF CLAUDE_PROJECT_DIR=$no_origin_head_dir bash $REPO_ROOT/scripts/verify-wiring.sh" \
  0
rm -rf "$no_origin_head_dir"

# z3-tla-playbook のハーネス契約 (setup-env / run-checks) を本 runner から到達させる。
run_test "z3-tla-playbook harness contract suite" \
  "bash tests/z3-tla-playbook-tests.sh" \
  0

echo ""
echo "Results: $pass_count passed, $fail_count failed"
exit $fail_count
