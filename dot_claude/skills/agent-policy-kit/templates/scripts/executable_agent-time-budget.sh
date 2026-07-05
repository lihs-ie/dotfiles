#!/usr/bin/env bash
# KIT_VERSION: 1.2.0
# agent-policy: proven-done の Time budget (light=30min / heavy=90min) を hook で決定論的に執行する。
# PreToolUse **と** PostToolUse の両方に登録し、stdin の hook JSON の hook_event_name で分岐する
# (docs/specs/agent-time-budget-hook.md Amendments Q3):
#   - PreToolUse:  経過率(ratio) >= 1.0 (100%) で exit 2 (deny) — tool call 自体をブロックしループを
#                  強制停止する。< 100% は exit 0 (無警告)。
#   - PostToolUse: 0.75 <= ratio < 1.0 (75%〜100%) で exit 2 — tool は既に実行済みのため実行はブロック
#                  しないが、Claude Code の公式仕様上 exit 2 の stderr は agent に届く
#                  (非ブロック警告の意味論)。それ以外は exit 0。
# 例外 (最優先で判定): tool_name が Write/Edit で、tool_input.file_path を repo-root 相対に正規化した
# 結果が .agent-evidence/ 配下なら、上記いずれの帯域でも常に exit 0 (deny 帯からの退避路 —
# agent が time-budget-exceeded.md を書いて Step 10 に進めるようにするため)。
# `.agent-evidence/.active` (task=/started_at=/lane= の marker) が無ければ no-op (exit 0)。
# started_at (ISO8601 UTC) の parse に失敗した場合は、壊れた marker でセッションを brick しないよう
# fail-safe で exit 0 とする。lane 欠落/未知値は heavy (90min) として扱う (安全側デフォルト)。
# hook_event_name が欠落/未知の場合も同様に fail-safe allow (exit 0) とするが、無言にはせず
# stderr に 1 行診断を出す (field 名変更等でセッションが brick しないよう fail-closed にはしない —
# docs/specs/agent-time-budget-hook.md Amendment 追記/static-review CONCERNS 対応)。
#
# Must-5 (.active tamper 検出 — docs/specs/guard-evasion-gates.md): (task, started_at, lane) の
# hook-private コピーをリポジトリ working tree の外側 (既定 $HOME/.claude/state/agent-time-budget/、
# リポジトリパス+task でキー、テスト用に --state-dir で上書き可能) に保持する。
#   (a) 対象 task を初めて見る (private コピー未存在) 時点で .active の現在値から private コピーを
#       作成する。
#   (b) 正当な re-stamp は1回のみ許可する: private コピーに lane が未記録の状態から `lane=` が
#       初めて現れた時点 (Step 1.5 Amendment A3 の re-stamp) で、private コピーの started_at/lane を
#       更新する。
#   (c) それ以降 .active の started_at が private コピーの started_at と食い違い、かつ private コピーに
#       既に lane が記録済みの場合は tamper と判定し、budget 計算に private コピーの started_at を
#       使う (.active の値は無視する)。deny/warn メッセージに re-stamp 検出・無視の旨を明記する。
#
# 使い方: <hook JSON> | agent-time-budget.sh [--evidence-dir <dir>] [--state-dir <dir>]
#   (既定: --evidence-dir .agent-evidence  --state-dir $HOME/.claude/state/agent-time-budget)
set -uo pipefail

repository_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$repository_root" 2>/dev/null || true

evidence_dir=".agent-evidence"
state_dir_root="$HOME/.claude/state/agent-time-budget"

while [ $# -gt 0 ]; do
  case "$1" in
    --evidence-dir) evidence_dir="${2:-}"; shift 2 ;;
    --evidence-dir=*) evidence_dir="${1#--evidence-dir=}"; shift ;;
    --state-dir) state_dir_root="${2:-}"; shift 2 ;;
    --state-dir=*) state_dir_root="${1#--state-dir=}"; shift ;;
    *) shift ;;
  esac
done

payload="$(cat 2>/dev/null || true)"

json_field() {
  # $1 = json string  $2 = jq filter (e.g. '.tool_input.file_path')。jq 優先 + python3 fallback。
  local json="$1" filter="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r "$filter // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
path = '$filter'.lstrip('.').split('.')
for p in path:
    if isinstance(data, dict):
        data = data.get(p)
    else:
        data = None
        break
if isinstance(data, str):
    print(data)
" <<< "$json" 2>/dev/null
  fi
}

hook_event_name="$(json_field "$payload" '.hook_event_name')"
tool_name="$(json_field "$payload" '.tool_name')"
file_path="$(json_field "$payload" '.tool_input.file_path')"

# (b) 例外判定を最優先: Write/Edit の file_path が (実) .agent-evidence/ 配下なら常に allow。
# --evidence-dir はテスト用の budget 判定対象ディレクトリの上書きであり、この例外の対象は常に
# 実際の repo root 直下の .agent-evidence/ (ハードコード) — 退避路の実体そのものを保護するため。
if [ "$tool_name" = "Write" ] || [ "$tool_name" = "Edit" ]; then
  if [ -n "$file_path" ]; then
    rel_path="$file_path"
    case "$file_path" in
      /*) rel_path="${file_path#"$repository_root"/}" ;;
    esac
    case "$rel_path" in
      .agent-evidence/*|.agent-evidence)
        exit 0
        ;;
    esac
  fi
fi

active_file="$evidence_dir/.active"

# (c) marker 不在 -> allow
[ -f "$active_file" ] || exit 0

task="$(grep '^task=' "$active_file" 2>/dev/null | head -1 | cut -d'=' -f2-)"
active_started_at="$(grep '^started_at=' "$active_file" 2>/dev/null | head -1 | cut -d'=' -f2-)"
active_lane="$(grep '^lane=' "$active_file" 2>/dev/null | head -1 | cut -d'=' -f2-)"

# started_at 無し -> fail-safe allow (壊れた marker でセッションを brick しない)
[ -n "$active_started_at" ] || exit 0

private_json_field() {
  # $1 = private copy ファイルパス  $2 = フィールド名 (task/started_at/lane)。jq 優先 + python3 fallback。
  local file="$1" field="$2"
  [ -f "$file" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg f "$field" '.[$f] // empty' "$file" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json, sys
try:
    d = json.load(open('$file'))
except Exception:
    sys.exit(0)
v = d.get('$field')
if isinstance(v, str):
    print(v)
" 2>/dev/null
  fi
}

write_private_copy() {
  # $1=private copy ファイルパス  $2=task  $3=started_at  $4=lane
  local file="$1" ptask="$2" pstarted_at="$3" planeval="$4"
  mkdir -p "$(dirname "$file")"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg task "$ptask" --arg started_at "$pstarted_at" --arg lane "$planeval" \
      '{task: $task, started_at: $started_at, lane: $lane}' > "$file" 2>/dev/null
  else
    printf '{"task": "%s", "started_at": "%s", "lane": "%s"}\n' "$ptask" "$pstarted_at" "$planeval" > "$file"
  fi
}

# Must-5: private コピーは effective な started_at/lane を確定させる (private が確定できなければ
# .active の現在値をそのまま使う — task 不明などの fail-safe)。
started_at="$active_started_at"
lane="$active_lane"
tamper_detected=0

if [ -n "$task" ]; then
  repo_key="$(printf '%s' "$repository_root" | sed -e 's#^/##' -e 's#/#_#g')"
  private_file="$state_dir_root/$repo_key/$task.json"
  if [ -f "$private_file" ]; then
    private_started_at="$(private_json_field "$private_file" 'started_at')"
    private_lane="$(private_json_field "$private_file" 'lane')"
    if [ -z "$private_lane" ] && [ -n "$active_lane" ]; then
      # (b) 唯一の正当 re-stamp: lane= が private コピーにまだ記録されていない状態から初めて現れた。
      private_started_at="$active_started_at"
      private_lane="$active_lane"
      write_private_copy "$private_file" "$task" "$private_started_at" "$private_lane"
    fi
    if [ -n "$private_lane" ] && [ "$active_started_at" != "$private_started_at" ]; then
      # (c) 正当な re-stamp が既に起きた後の started_at 食い違い -> tamper。private を採用する。
      tamper_detected=1
    fi
    started_at="$private_started_at"
    lane="$private_lane"
  else
    # (a) 初見: .active の現在値から private コピーを作成する。
    write_private_copy "$private_file" "$task" "$active_started_at" "$active_lane"
    started_at="$active_started_at"
    lane="$active_lane"
  fi
fi

case "$lane" in
  light) budget_minutes=30 ;;
  *) lane="heavy"; budget_minutes=90 ;;
esac

# started_at 無し -> fail-safe allow (壊れた marker でセッションを brick しない)
[ -n "$started_at" ] || exit 0

parse_iso8601_epoch() {
  local iso="$1" epoch=""
  # BSD date (macOS) 優先、失敗したら GNU date にフォールバック。
  epoch="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null)" && { printf '%s' "$epoch"; return 0; }
  epoch="$(date -u -d "$iso" +%s 2>/dev/null)" && { printf '%s' "$epoch"; return 0; }
  return 1
}

started_epoch="$(parse_iso8601_epoch "$started_at")" || exit 0
[ -n "$started_epoch" ] || exit 0

now_epoch="$(date -u +%s)"
elapsed_seconds=$((now_epoch - started_epoch))
[ "$elapsed_seconds" -lt 0 ] && elapsed_seconds=0

budget_seconds=$((budget_minutes * 60))
ratio_permille=$(( elapsed_seconds * 1000 / budget_seconds ))
elapsed_minutes=$(( elapsed_seconds / 60 ))
percent=$(( ratio_permille / 10 ))

case "$hook_event_name" in
  PreToolUse)
    if [ "$ratio_permille" -ge 1000 ]; then
      {
        echo "time budget 超過 (lane=${lane}, ${elapsed_minutes} 分経過)。"
        echo ".agent-evidence/time-budget-exceeded.md に状態を書き Step 10 へ。"
        echo "解除は rm .agent-evidence/.active または started_at 更新"
        if [ "$tamper_detected" -eq 1 ]; then
          echo "re-stamp (再スタンプ) 検出: .active の started_at 書き換えを検出し無視しました。private コピーの started_at を採用しています。"
        fi
      } >&2
      exit 2
    fi
    exit 0
    ;;
  PostToolUse)
    if [ "$ratio_permille" -ge 750 ] && [ "$ratio_permille" -lt 1000 ]; then
      {
        echo "budget の ${percent}% 消費 (lane=${lane}, ${elapsed_minutes} 分経過) — 収束を急ぎ、残作業を絞れ"
        if [ "$tamper_detected" -eq 1 ]; then
          echo "re-stamp (再スタンプ) 検出: .active の started_at 書き換えを検出し無視しました。private コピーの started_at を採用しています。"
        fi
      } >&2
      exit 2
    fi
    exit 0
    ;;
  *)
    echo "agent-time-budget: unknown/missing hook_event_name — fail-safe allow" >&2
    exit 0
    ;;
esac
