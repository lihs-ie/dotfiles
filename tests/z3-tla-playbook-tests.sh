#!/usr/bin/env bash
# z3-tla-playbook の実行ハーネス (setup-env.sh / run-checks.sh) の契約検証。
# tests/run-shell-tests.sh の流儀 (run_test 関数 + PASSED/FAILED 集計) を踏襲する。
#
# fixture は z3 / java に依存させない。ここで固定したいのは
# 「ハーネスが exit code をどう判定するか」であって、ソルバーの正しさではないため。
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

SKILL_DIR="dot_claude/skills/z3-tla-playbook"
SETUP="$SKILL_DIR/scripts/executable_setup-env.sh"
RUN_CHECKS="$SKILL_DIR/scripts/executable_run-checks.sh"

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
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    echo "PASSED: $name"
    pass_count=$((pass_count + 1))
  else
    echo "FAILED: $name (expected to contain: $needle)"
    fail_count=$((fail_count + 1))
  fi
}

# ---------- run-checks.sh の判定契約 ----------

run_test "run-checks: 正例 (モデル緑 + 対照が赤) -> exit 0" \
  "bash $RUN_CHECKS --dir tests/fixtures/formal-ok --only z3" \
  0

run_test "run-checks: 対照なし -> exit 1 (検査が効いている証明が無い)" \
  "bash $RUN_CHECKS --dir tests/fixtures/formal-missing-broken --only z3" \
  1

run_test "run-checks: 対照なしでも --allow-missing-broken なら exit 0" \
  "bash $RUN_CHECKS --dir tests/fixtures/formal-missing-broken --only z3 --allow-missing-broken" \
  0

run_test "run-checks: 対照が緑のまま通る -> exit 1 (何も検証していない緑)" \
  "bash $RUN_CHECKS --dir tests/fixtures/formal-vacuous-broken --only z3" \
  1

empty_dir="$(mktemp -d)"
mkdir -p "$empty_dir/models"
run_test "run-checks: 検証対象 0 件 -> exit 1 (空っぽの緑は失格)" \
  "bash $RUN_CHECKS --dir $empty_dir --only z3" \
  1
run_test "run-checks: 0 件でも --allow-empty なら exit 0" \
  "bash $RUN_CHECKS --dir $empty_dir --only z3 --allow-empty" \
  0
rm -rf "$empty_dir"

run_test "run-checks: 存在しない --dir -> exit 2 (環境エラーと検査失敗を分離)" \
  "bash $RUN_CHECKS --dir /nonexistent/formal-dir" \
  2

run_test "run-checks: 未知の引数 -> exit 2" \
  "bash $RUN_CHECKS --bogus" \
  2

run_test "run-checks: 不正な --only -> exit 2" \
  "bash $RUN_CHECKS --only quantum" \
  2

vacuous_output="$(bash "$RUN_CHECKS" --dir tests/fixtures/formal-vacuous-broken --only z3 2>&1 || true)"
assert_contains "run-checks: 対照が緑のとき理由を出力する" \
  "$vacuous_output" "検査が効いていない"

# exit code の分類: 「非 0 = 捕まえた」と数えると、依存不足やクラッシュが
# 「壊れた実装を検出できた」に化ける (実測: venv 破損時に Abort trap exit 134 を PASS 判定していた)。
run_test "run-checks: 対照が exit 2 で異常終了 -> exit 1 (クラッシュは検出ではない)" \
  "bash $RUN_CHECKS --dir tests/fixtures/formal-crash-broken --only z3" \
  1

crash_output="$(bash "$RUN_CHECKS" --dir tests/fixtures/formal-crash-broken --only z3 2>&1 || true)"
assert_contains "run-checks: 対照の異常終了を『検出』と区別して報告する" \
  "$crash_output" "であって検出ではない"

run_test "run-checks: 基準モデルが exit 2 -> exit 1 (実行エラー)" \
  "bash $RUN_CHECKS --dir tests/fixtures/formal-env-error --only z3" \
  1

env_error_output="$(bash "$RUN_CHECKS" --dir tests/fixtures/formal-env-error --only z3 2>&1 || true)"
assert_contains "run-checks: 基準モデルの実行エラーを検査失敗と区別して報告する" \
  "$env_error_output" "検査結果ではない"
assert_contains "run-checks: 実行エラーの fixture でも正常な対照は捕捉扱いにする" \
  "$env_error_output" "が赤で捕まった (exit 1)"

# ---------- setup-env.sh の契約 ----------

init_dir="$(mktemp -d)"
run_test "setup-env --init -> exit 0" \
  "bash $SETUP --dir $init_dir/.formal --init" \
  0

for expected in models/example_cap.py models/broken/example_cap__guard-removed.py \
                specs/Example.tla specs/Example.cfg specs/Example.expect \
                specs/broken/Example__StaleRead.tla specs/broken/Example__StaleRead.cfg \
                ledger.md .gitignore; do
  if [ -f "$init_dir/.formal/$expected" ]; then
    echo "PASSED: setup-env --init が $expected を配置する"
    pass_count=$((pass_count + 1))
  else
    echo "FAILED: setup-env --init が $expected を配置していない"
    fail_count=$((fail_count + 1))
  fi
done

run_test "setup-env --init は再実行しても既存を壊さない (冪等)" \
  "bash $SETUP --dir $init_dir/.formal --init" \
  0

init_output="$(bash "$SETUP" --dir "$init_dir/.formal" --init 2>&1 || true)"
assert_contains "setup-env --init: 2 回目は keep (exists) と報告する" \
  "$init_output" "keep (exists)"

run_test "setup-env --check: 依存未導入なら exit 1" \
  "bash $SETUP --dir $init_dir/.formal --check --lane tla" \
  1

run_test "setup-env: 不正な --lane -> exit 2" \
  "bash $SETUP --lane both-ish" \
  2
rm -rf "$init_dir"

# ---------- テンプレート自体の健全性 ----------

run_test "template model.py が Python として構文妥当" \
  "python3 -m py_compile $SKILL_DIR/templates/model.py" \
  0

run_test "template broken_model.py が Python として構文妥当" \
  "python3 -m py_compile $SKILL_DIR/templates/broken_model.py" \
  0

# TLA+ はモジュール名とファイル名の一致が必須。--init 後の配置名と突き合わせる。
tla_module="$(sed -n 's/^-*[[:space:]]*MODULE[[:space:]]\([A-Za-z0-9_]*\).*/\1/p' "$SKILL_DIR/templates/spec.tla" | head -1)"
assert_contains "template spec.tla のモジュール名が配置名 Example と一致" "$tla_module" "Example"

broken_module="$(sed -n 's/^-*[[:space:]]*MODULE[[:space:]]\([A-Za-z0-9_]*\).*/\1/p' "$SKILL_DIR/templates/broken_spec.tla" | head -1)"
assert_contains "template broken_spec.tla のモジュール名が配置名 Example__StaleRead と一致" \
  "$broken_module" "Example__StaleRead"

if [ "$broken_module" = "${tla_module}__StaleRead" ]; then
  echo "PASSED: broken variant の命名が run-checks の探索パターン <stem>__* に合致"
  pass_count=$((pass_count + 1))
else
  echo "FAILED: broken variant の命名が <stem>__* に合致しない ($broken_module)"
  fail_count=$((fail_count + 1))
fi

find "$SKILL_DIR/templates" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true

echo ""
echo "Results: $pass_count passed, $fail_count failed"
exit "$fail_count"
