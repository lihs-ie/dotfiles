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

# P4 note: the P3 packet-split transient (kit-sync-check --self reporting STALE because
# kit-manifest.yml predated the Must-5 hardening) is resolved by this packet's atomic
# kit_version 1.1.0->1.2.0 bump (Must-7(b), kit-manifest-update.sh run once covering all 15
# templates). Reverted to the original exit-0 assertion.
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

echo ""
echo "Results: $pass_count passed, $fail_count failed"
exit $fail_count
