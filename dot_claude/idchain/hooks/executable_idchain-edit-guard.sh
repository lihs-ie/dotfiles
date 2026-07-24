#!/usr/bin/env bash
# idchain-edit-guard.sh — Claude Code PreToolUse(Edit|Write|MultiEdit|NotebookEdit) hook
#
# Must-22 (docs/specs/idchain.md M4): idchain 導入 repo (`<root>/idchain/idchain.json` を持つ) で、
# 未承認 SP しか存在しない状態での実装ファイル編集を deny する「四層強制」の第四層。
# 他の 3 層 (①skill 内ゲート ②pre-commit ③CI) と異なり、編集の瞬間にブロックする。
#
# jq / python3 に依存しない (対象 repo にどちらも無くても動く移植性を優先し、grep/sed/awk のみで書く)。
#
# 判定フロー:
#   1. stdin の tool_input.file_path を抽出できなければ allow (誤爆防止優先)。
#   2. file_path から上方向に walk し `idchain/idchain.json` を持つルートを探す。
#      見つからなければ (idchain 非導入 repo、または対象外ファイル) allow。
#   3. file_path が <root>/idchain/ 配下、または idchain.json の testFileRoots / editAllowlist の
#      いずれかの配下なら allow。
#   4. <root>/idchain/.gate-status.json (lake exe idchain check が書く) を読む:
#        - 存在しない、または内容の数値抽出に失敗 → deny (「ゲート状態が未生成」扱いに倒す)
#        - approvedFreshSpecs == 0 かつ unapprovedSpecs >= 1 (未承認 SP のみ) → deny
#        - それ以外 (SP 0 件、または fresh 承認が 1 件以上) → allow
#
# Claude Code hook 契約: deny は exit 2 + stderr にメッセージ (stderr が Claude にフィードバックされる)、
# allow は exit 0。set -euo pipefail 下で防御的に書く (パース失敗で意図しない結果にならないよう、
# 数値抽出に失敗した場合は「.gate-status.json が存在しない」場合と同じ deny 分岐に倒す)。
set -euo pipefail

input="$(cat)"

extract_file_path() {
  printf '%s' "$1" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}

file_path="$(extract_file_path "$input")"

if [ -z "$file_path" ]; then
  exit 0
fi

# --- ルート検出: file_path から上方向に idchain/idchain.json を持つディレクトリを探す ---
dir="$(dirname "$file_path")"
root=""
while :; do
  if [ -f "$dir/idchain/idchain.json" ]; then
    root="$dir"
    break
  fi
  if [ "$dir" = "/" ]; then
    break
  fi
  parent="$(dirname "$dir")"
  if [ "$parent" = "$dir" ]; then
    break
  fi
  dir="$parent"
done

if [ -z "$root" ]; then
  exit 0
fi

if [ "$root" = "/" ]; then
  rel="${file_path#/}"
else
  rel="${file_path#"$root"/}"
fi

# idchain/ 配下は常に allow (正本・エンジン・ビュー・レポート等の編集は妨げない)。
case "$rel" in
  idchain/*) exit 0 ;;
esac

config="$root/idchain/idchain.json"

# idchain.json の配列キー (testFileRoots / editAllowlist) の値一覧を抽出する。
# 配列が複数行に跨っても閉じ括弧 "]" まで拾う。厳密な JSON パースは行わず、
# キー行〜閉じ括弧の間に現れる引用符付き文字列を「値」として扱う (先頭 1 個はキー自身なので除く)。
extract_array_values() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  awk -v k="\"$key\"" '
    index($0, k) { capture = 1 }
    capture { buffer = buffer $0 "\n" }
    capture && index($0, "]") { print buffer; capture = 0; buffer = "" }
  ' "$file" 2>/dev/null | grep -oE '"[^"]*"' | tail -n +2 | sed -e 's/^"//' -e 's/"$//'
}

# $1 が prefix ($2) 配下 (完全一致 or ディレクトリ配下) かどうか。
is_under_prefix() {
  local target="$1" prefix="$2"
  prefix="${prefix%/}"
  if [ -z "$prefix" ]; then
    return 1
  fi
  if [ "$target" = "$prefix" ]; then
    return 0
  fi
  case "$target" in
    "$prefix"/*) return 0 ;;
  esac
  return 1
}

while IFS= read -r allowed; do
  if [ -n "$allowed" ] && is_under_prefix "$rel" "$allowed"; then
    exit 0
  fi
done < <(extract_array_values "$config" "testFileRoots")

while IFS= read -r allowed; do
  if [ -n "$allowed" ] && is_under_prefix "$rel" "$allowed"; then
    exit 0
  fi
done < <(extract_array_values "$config" "editAllowlist")

# --- ゲート状態 (lake exe idchain check が cwd = idchain/ に書く) を読む ---
gate_status="$root/idchain/.gate-status.json"

deny_not_generated() {
  echo "idchain: ゲート状態が未生成。先に (cd idchain && lake exe idchain check) を実行してください" >&2
  exit 2
}

if [ ! -f "$gate_status" ]; then
  deny_not_generated
fi

approved="$(grep -oE '"approvedFreshSpecs"[[:space:]]*:[[:space:]]*[0-9]+' "$gate_status" 2>/dev/null | grep -oE '[0-9]+$' || true)"
unapproved="$(grep -oE '"unapprovedSpecs"[[:space:]]*:[[:space:]]*[0-9]+' "$gate_status" 2>/dev/null | grep -oE '[0-9]+$' || true)"

case "$approved" in
  ''|*[!0-9]*) deny_not_generated ;;
esac
case "$unapproved" in
  ''|*[!0-9]*) deny_not_generated ;;
esac

if [ "$approved" -eq 0 ] && [ "$unapproved" -ge 1 ]; then
  echo "idchain: 未承認 SP のみの状態で実装ファイルは編集できません (G2 承認 → lake exe idchain check 後に再試行)" >&2
  exit 2
fi

exit 0
