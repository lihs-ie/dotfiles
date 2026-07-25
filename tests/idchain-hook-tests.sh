#!/usr/bin/env bash
# idchain 編集ブロック hook (Must-22, docs/specs/idchain.md M4) の exit code 検証。
# tests/idchain-fixture-tests.sh の run_test 流儀 (PASSED/FAILED 集計) を踏襲する独立スクリプト。
# 配布前の repo 内スクリプト (dot_claude/idchain/hooks/executable_idchain-edit-guard.sh) を直接呼ぶ。
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HOOK="$REPO_ROOT/dot_claude/idchain/hooks/executable_idchain-edit-guard.sh"

pass_count=0
fail_count=0

run_test() {
  local name="$1" input="$2" expected_exit="$3"
  local actual_exit=0

  printf '%s' "$input" | bash "$HOOK" >/dev/null 2>/dev/null || actual_exit=$?

  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "PASSED: $name (exit $actual_exit)"
    pass_count=$((pass_count + 1))
  else
    echo "FAILED: $name (expected exit $expected_exit, got $actual_exit)"
    fail_count=$((fail_count + 1))
  fi
}

edit_input() {
  # $1 = file_path。hook が読む tool_input.file_path のみ埋める最小 PreToolUse payload。
  printf '{"tool_name": "Edit", "tool_input": {"file_path": "%s"}}' "$1"
}

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# ============================================================
# シナリオ 1: idchain 非導入 repo (idchain/idchain.json が上方向に存在しない)
# ============================================================
NON_IDCHAIN_DIR="$WORKDIR/non-idchain-repo"

run_test "1. idchain 非導入 repo のファイル編集 -> allow" \
  "$(edit_input "$NON_IDCHAIN_DIR/src/impl.txt")" \
  0

# ============================================================
# idchain 導入 repo の最小土台 (idchain/idchain.json + idchain/.gate-status.json だけ、lake 不要)
# ============================================================
REPO_DIR="$WORKDIR/sample-repo"
mkdir -p "$REPO_DIR/idchain"
cat > "$REPO_DIR/idchain/idchain.json" <<'JSON'
{
  "repoRoot": "..",
  "testFileRoots": ["Tests"],
  "testFileExtensions": [".swift"],
  "editAllowlist": ["docs/"]
}
JSON

# ------------------------------------------------------------
# シナリオ 2: gate-status あり (approvedFreshSpecs 1) の実装ファイル編集 -> allow
# ------------------------------------------------------------
cat > "$REPO_DIR/idchain/.gate-status.json" <<'JSON'
{
  "approvedFreshSpecs": 1,
  "unapprovedSpecs": 0,
  "violations": 0
}
JSON

run_test "2. gate-status あり (approvedFreshSpecs 1) の実装ファイル編集 -> allow" \
  "$(edit_input "$REPO_DIR/src/impl.swift")" \
  0

# ------------------------------------------------------------
# シナリオ 3〜6: gate-status あり (approvedFreshSpecs 0, unapprovedSpecs 2、未承認 SP のみ)
# ------------------------------------------------------------
cat > "$REPO_DIR/idchain/.gate-status.json" <<'JSON'
{
  "approvedFreshSpecs": 0,
  "unapprovedSpecs": 2,
  "violations": 0
}
JSON

run_test "3. gate-status (0 fresh / 2 unapproved) の実装ファイル編集 -> deny" \
  "$(edit_input "$REPO_DIR/src/impl.swift")" \
  2

run_test "4. 同状態で idchain/ 配下の編集 -> allow" \
  "$(edit_input "$REPO_DIR/idchain/idchain.json")" \
  0

run_test "5. 同状態で testFileRoots (\"Tests\") 配下の編集 -> allow" \
  "$(edit_input "$REPO_DIR/Tests/impl_test.swift")" \
  0

run_test "6. 同状態で editAllowlist (\"docs/\") 配下の編集 -> allow" \
  "$(edit_input "$REPO_DIR/docs/readme.md")" \
  0

# ------------------------------------------------------------
# シナリオ 7: gate-status 不在 (check 未実行) -> deny
# ------------------------------------------------------------
rm -f "$REPO_DIR/idchain/.gate-status.json"

run_test "7. gate-status 不在 -> deny" \
  "$(edit_input "$REPO_DIR/src/impl.swift")" \
  2

# ------------------------------------------------------------
# シナリオ 8: stdin に file_path なし -> allow (誤爆防止優先)
# ------------------------------------------------------------
run_test "8. stdin に file_path なし -> allow" \
  '{"tool_name": "Edit", "tool_input": {}}' \
  0

echo ""
echo "Results: $pass_count passed, $fail_count failed"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
exit 0
