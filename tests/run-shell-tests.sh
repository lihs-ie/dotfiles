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

echo ""
echo "Results: $pass_count passed, $fail_count failed"
exit $fail_count
