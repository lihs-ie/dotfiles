#!/usr/bin/env bash
# idchain 正例 (idchain-sample) / 負例 (idchain-broken) fixture の実行検証。
# tests/run-shell-tests.sh の流儀 (run_test 関数 + PASSED/FAILED 集計) を踏襲する独立スクリプト。
set -euo pipefail

export PATH="$HOME/.elan/bin:$PATH"

if ! command -v elan >/dev/null 2>&1; then
  echo "SKIP: elan 未導入"
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

SAMPLE_DIR="tests/fixtures/idchain-sample/idchain"
BROKEN_DIR="tests/fixtures/idchain-broken/idchain"

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

assert_contains() {
  # $1=name  $2=haystack  $3=needle
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "PASSED: $name"
    pass_count=$((pass_count + 1))
  else
    echo "FAILED: $name (needle not found: $needle)"
    fail_count=$((fail_count + 1))
  fi
}

# ============================================================
# 正例: tests/fixtures/idchain-sample (全ゲート green)
# ============================================================

run_test "idchain-sample: lake build" \
  "(cd $SAMPLE_DIR && lake build)" \
  0

run_test "idchain-sample: check (違反 0 件)" \
  "(cd $SAMPLE_DIR && lake exe idchain check)" \
  0

run_test "idchain-sample: views --check (鮮度 OK)" \
  "(cd $SAMPLE_DIR && lake exe idchain views --check)" \
  0

run_test "idchain-sample: crosscheck (違反 0 件)" \
  "(cd $SAMPLE_DIR && lake exe idchain crosscheck)" \
  0

sample_gate_status_file="$SAMPLE_DIR/.gate-status.json"
if [ -f "$sample_gate_status_file" ]; then
  sample_gate_status_content="$(cat "$sample_gate_status_file")"
else
  sample_gate_status_content=""
fi

if [ -f "$sample_gate_status_file" ]; then
  echo "PASSED: idchain-sample: check 実行後に .gate-status.json が存在する"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: idchain-sample: check 実行後に .gate-status.json が存在する"
  fail_count=$((fail_count + 1))
fi

assert_contains "idchain-sample: .gate-status.json に \"approvedFreshSpecs\": 1 を含む" \
  "$sample_gate_status_content" "\"approvedFreshSpecs\": 1"

assert_contains "idchain-sample: .gate-status.json に \"unapprovedSpecs\": 0 を含む" \
  "$sample_gate_status_content" "\"unapprovedSpecs\": 0"

run_test "idchain-sample: report --date 2026-01-01" \
  "(cd $SAMPLE_DIR && lake exe idchain report --date 2026-01-01)" \
  0

sample_report_md="$SAMPLE_DIR/reports/2026-01-01/verification-report.md"
if [ -f "$sample_report_md" ]; then
  sample_report_content="$(cat "$sample_report_md")"
else
  sample_report_content=""
fi

assert_contains "idchain-sample: report md に「検証に紐づいていない仕様: 0 件」を含む" \
  "$sample_report_content" "検証に紐づいていない仕様: 0 件"

assert_contains "idchain-sample: report md に「仕様に紐づいていないテスト: 0 件」を含む" \
  "$sample_report_content" "仕様に紐づいていないテスト: 0 件"

# ------------------------------------------------------------
# M5 (Must-29): roadmap.md が views に生成される
# ------------------------------------------------------------

sample_roadmap_view="$SAMPLE_DIR/views/roadmap.md"
if [ -f "$sample_roadmap_view" ]; then
  sample_roadmap_content="$(cat "$sample_roadmap_view")"
else
  sample_roadmap_content=""
fi

if [ -f "$sample_roadmap_view" ]; then
  echo "PASSED: idchain-sample: views/roadmap.md が生成される"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: idchain-sample: views/roadmap.md が生成される"
  fail_count=$((fail_count + 1))
fi

assert_contains "idchain-sample: views/roadmap.md に RM-001 を含む" \
  "$sample_roadmap_content" "RM-001"

# ------------------------------------------------------------
# M3 付帯機構: 正例 (pairwise/oracle/bench はすべて green)
# ------------------------------------------------------------

sample_pairwise_exit=0
sample_pairwise_output="$(cd "$SAMPLE_DIR" && lake exe idchain pairwise 2>&1)" || sample_pairwise_exit=$?

if [ "$sample_pairwise_exit" -eq 0 ]; then
  echo "PASSED: idchain-sample: pairwise exit 0"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: idchain-sample: pairwise exit 0 (got $sample_pairwise_exit)"
  fail_count=$((fail_count + 1))
fi

assert_contains "idchain-sample: pairwise 出力に「100%」を含む (網羅率 100%)" \
  "$sample_pairwise_output" "100%"

run_test "idchain-sample: oracle (全クエリ一致)" \
  "(cd $SAMPLE_DIR && lake exe idchain oracle)" \
  0

run_test "idchain-sample: bench (green 判定)" \
  "(cd $SAMPLE_DIR && lake exe idchain bench)" \
  0

# ============================================================
# 負例: tests/fixtures/idchain-broken (意図的に 5 種の違反 + crosscheck 3 種の不整合)
# ============================================================

run_test "idchain-broken: lake build" \
  "(cd $BROKEN_DIR && lake build)" \
  0

broken_check_exit=0
broken_check_output="$(cd "$BROKEN_DIR" && lake exe idchain check 2>&1)" || broken_check_exit=$?

if [ "$broken_check_exit" -eq 1 ]; then
  echo "PASSED: idchain-broken: check exit 1"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: idchain-broken: check exit 1 (got $broken_check_exit)"
  fail_count=$((fail_count + 1))
fi

# check の 9 違反ラベル (M1 の 5 種 + M5 の 4 種): 1 ラベルにつき 1 テストケース
for label in \
  "orphan-spec" \
  "test-case-for-unapproved-spec" \
  "stale-approval" \
  "retired-identifier-reuse" \
  "learning-not-contiguous" \
  "roadmap-not-contiguous" \
  "in-cycle-roadmap-unapproved" \
  "semantic-review-missing" \
  "semantic-review-stale"
do
  assert_contains "idchain-broken: check 出力に [$label] を含む" \
    "$broken_check_output" "[$label]"
done

broken_gate_status_file="$BROKEN_DIR/.gate-status.json"
if [ -f "$broken_gate_status_file" ]; then
  broken_gate_status_content="$(cat "$broken_gate_status_file")"
else
  broken_gate_status_content=""
fi

assert_contains "idchain-broken: .gate-status.json に \"violations\": 9 を含む" \
  "$broken_gate_status_content" "\"violations\": 9"

broken_crosscheck_exit=0
broken_crosscheck_output="$(cd "$BROKEN_DIR" && lake exe idchain crosscheck 2>&1)" || broken_crosscheck_exit=$?

if [ "$broken_crosscheck_exit" -eq 1 ]; then
  echo "PASSED: idchain-broken: crosscheck exit 1"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: idchain-broken: crosscheck exit 1 (got $broken_crosscheck_exit)"
  fail_count=$((fail_count + 1))
fi

assert_contains "idchain-broken: crosscheck 出力に孤児テスト (testWithoutIdentifier) を含む" \
  "$broken_crosscheck_output" "testWithoutIdentifier"

assert_contains "idchain-broken: crosscheck 出力に未知の TC 参照 (TC-099-9) を含む" \
  "$broken_crosscheck_output" "TC-099-9"

assert_contains "idchain-broken: crosscheck 出力に未実行 TC (TC-048-1) を含む" \
  "$broken_crosscheck_output" "TC-048-1"

# ------------------------------------------------------------
# M3 付帯機構: 負例 (oracle 不一致 / bench 赤判定は exit 1)
# ------------------------------------------------------------

broken_oracle_exit=0
(cd "$BROKEN_DIR" && lake exe idchain oracle) >/dev/null 2>&1 || broken_oracle_exit=$?

if [ "$broken_oracle_exit" -eq 1 ]; then
  echo "PASSED: idchain-broken: oracle exit 1 (不一致)"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: idchain-broken: oracle exit 1 (got $broken_oracle_exit)"
  fail_count=$((fail_count + 1))
fi

broken_bench_exit=0
(cd "$BROKEN_DIR" && lake exe idchain bench) >/dev/null 2>&1 || broken_bench_exit=$?

if [ "$broken_bench_exit" -eq 1 ]; then
  echo "PASSED: idchain-broken: bench exit 1 (赤判定)"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: idchain-broken: bench exit 1 (got $broken_bench_exit)"
  fail_count=$((fail_count + 1))
fi

# ------------------------------------------------------------
# M5 (Must-28): report が bench 赤判定に対応する RM の不在を検出して FAIL にする
# (bench を先に実行して bench-results.json を最新化してから report を走らせる)。
# ------------------------------------------------------------

broken_report_exit=0
(cd "$BROKEN_DIR" && lake exe idchain report --date 2026-01-01) >/dev/null 2>&1 || broken_report_exit=$?

if [ "$broken_report_exit" -eq 1 ]; then
  echo "PASSED: idchain-broken: report exit 1 (FAIL)"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: idchain-broken: report exit 1 (got $broken_report_exit)"
  fail_count=$((fail_count + 1))
fi

broken_report_md="$BROKEN_DIR/reports/2026-01-01/verification-report.md"
if [ -f "$broken_report_md" ]; then
  broken_report_content="$(cat "$broken_report_md")"
else
  broken_report_content=""
fi

assert_contains "idchain-broken: report md の総合判定が FAIL" \
  "$broken_report_content" "## 総合判定: FAIL"

assert_contains "idchain-broken: report md のベンチセクションに「未反映」を含む" \
  "$broken_report_content" "未反映"

assert_contains "idchain-broken: report md の未反映ベンチ名 (重い処理) を含む" \
  "$broken_report_content" "重い処理"

echo ""
echo "Results: $pass_count passed, $fail_count failed"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
exit 0
