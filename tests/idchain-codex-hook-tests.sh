#!/usr/bin/env bash
# Codex PreToolUse(apply_patch) adapter for idchain Must-22.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
hook="$repo_root/dot_codex/idchain/hooks/executable_idchain-edit-guard.py"
pass_count=0
fail_count=0

payload() {
  local cwd="$1" patch="$2"
  python3 - "$cwd" "$patch" <<'PY'
import json
import sys

print(json.dumps({
    "cwd": sys.argv[1],
    "hook_event_name": "PreToolUse",
    "tool_name": "apply_patch",
    "tool_input": {"command": sys.argv[2]},
}))
PY
}

run_test() {
  local name="$1" cwd="$2" patch="$3" expected="$4"
  local output actual="allow"

  output="$(payload "$cwd" "$patch" | python3 "$hook")"
  if printf '%s' "$output" | grep -q '"permissionDecision": "deny"'; then
    actual="deny"
  fi

  if [ "$actual" = "$expected" ]; then
    echo "PASSED: $name ($actual)"
    pass_count=$((pass_count + 1))
  else
    echo "FAILED: $name (expected $expected, got $actual)"
    if [ -n "$output" ]; then
      echo "$output"
    fi
    fail_count=$((fail_count + 1))
  fi
}

work_directory="$(mktemp -d)"
trap 'rm -rf "$work_directory"' EXIT

non_idchain="$work_directory/non-idchain"
mkdir -p "$non_idchain/src"
run_test \
  "1. idchain 非導入 repo" \
  "$non_idchain" \
  $'*** Begin Patch\n*** Add File: src/new.ts\n+new\n*** End Patch' \
  allow

sample_repo="$work_directory/sample/idchain-repo"
mkdir -p "$sample_repo/idchain" "$sample_repo/Tests" "$sample_repo/docs" "$sample_repo/src"
cat > "$sample_repo/idchain/idchain.json" <<'JSON'
{
  "testFileRoots": ["Tests"],
  "editAllowlist": ["docs/"]
}
JSON

cat > "$sample_repo/idchain/.gate-status.json" <<'JSON'
{
  "approvedFreshSpecs": 1,
  "unapprovedSpecs": 0
}
JSON
run_test \
  "2. fresh 承認済み SP がある実装編集" \
  "$sample_repo" \
  $'*** Begin Patch\n*** Update File: src/impl.ts\n@@\n-old\n+new\n*** End Patch' \
  allow

cat > "$sample_repo/idchain/.gate-status.json" <<'JSON'
{
  "approvedFreshSpecs": 0,
  "unapprovedSpecs": 2
}
JSON
run_test \
  "3. 未承認 SP のみで実装編集" \
  "$sample_repo" \
  $'*** Begin Patch\n*** Update File: src/impl.ts\n@@\n-old\n+new\n*** End Patch' \
  deny

run_test \
  "4. 未承認状態でも idchain 正本は編集可能" \
  "$sample_repo" \
  $'*** Begin Patch\n*** Update File: idchain/Canon/Artifacts.lean\n@@\n-old\n+new\n*** End Patch' \
  allow

run_test \
  "5. testFileRoots は編集可能" \
  "$sample_repo" \
  $'*** Begin Patch\n*** Add File: Tests/impl_test.ts\n+test\n*** End Patch' \
  allow

run_test \
  "6. editAllowlist は編集可能" \
  "$sample_repo" \
  $'*** Begin Patch\n*** Update File: docs/design.md\n@@\n-old\n+new\n*** End Patch' \
  allow

run_test \
  "7. 複数ファイル中に実装ファイルがあれば deny" \
  "$sample_repo" \
  $'*** Begin Patch\n*** Add File: Tests/new_test.ts\n+test\n*** Add File: src/new.ts\n+impl\n*** End Patch' \
  deny

run_test \
  "8. allowlist から実装パスへの Move を deny" \
  "$sample_repo" \
  $'*** Begin Patch\n*** Update File: Tests/old_test.ts\n*** Move to: src/old.ts\n@@\n-old\n+new\n*** End Patch' \
  deny

rm -f "$sample_repo/idchain/.gate-status.json"
run_test \
  "9. gate-status 不在は deny" \
  "$sample_repo/src" \
  $'*** Begin Patch\n*** Delete File: impl.ts\n*** End Patch' \
  deny

run_test \
  "10. 対象パスを持たない patch は fail-open" \
  "$sample_repo" \
  $'*** Begin Patch\n*** End Patch' \
  allow

echo ""
echo "Results: $pass_count passed, $fail_count failed"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
