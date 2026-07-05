#!/bin/bash
# adr-drift-scan — ADR と対象コードの鮮度を比較し、ADR より後に対象コードが変わった
# (= ADR が現実と乖離している可能性がある) ものを検出する。読み取り専用。
#
# usage: adr-drift-scan.sh [repository_root]   # default: カレントディレクトリ
#
# scope の特定方法 (優先順):
#   1. ADR 本文の `Scope:` 行 (カンマ区切りで repo 相対パス)
#   2. fallback: 本文の backtick 内パス風文字列のうち、repo に実在するもの (最大 8 件)
set -eu

REPOSITORY_ROOT="${1:-$PWD}"
cd "$REPOSITORY_ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: $REPOSITORY_ROOT は git リポジトリではありません" >&2
  exit 1
fi

# --- ADR ディレクトリ検出 ---------------------------------------------------
ADR_DIRECTORY=''
for candidate in docs/adr adr docs/ADR docs/architecture/decisions; do
  if [ -d "$candidate" ]; then
    ADR_DIRECTORY="$candidate"
    break
  fi
done
if [ -z "$ADR_DIRECTORY" ]; then
  echo "ERROR: ADR ディレクトリが見つかりません (docs/adr, adr, docs/ADR, docs/architecture/decisions)" >&2
  exit 1
fi

echo "=== ADR DRIFT SCAN: $(basename "$PWD") (adr dir: $ADR_DIRECTORY) ==="

drift_count=0
fresh_count=0
no_scope_count=0
total_count=0

for adr_file in "$ADR_DIRECTORY"/*.md; do
  [ -f "$adr_file" ] || continue
  base_name=$(basename "$adr_file")
  case "$base_name" in
    README.md|template.md|TEMPLATE.md|_*) continue ;;
  esac
  total_count=$((total_count + 1))

  # ADR 自身の最終更新 (git 履歴優先、未コミットなら mtime)
  adr_timestamp=$(git log -1 --format='%ct' -- "$adr_file" 2>/dev/null || true)
  [ -n "$adr_timestamp" ] || adr_timestamp=$(stat -f '%m' "$adr_file")
  adr_date=$(date -r "$adr_timestamp" '+%Y-%m-%d')
  adr_iso=$(date -r "$adr_timestamp" '+%Y-%m-%dT%H:%M:%S')

  # Status と改訂履歴の有無 (4 形式対応: "Status: x" / "- ステータス: x" 箇条書き行 /
  # テーブル行 "| status | x |" / "# ステータス" 見出しの次の非空行)
  adr_status=$(grep -m1 -iE '^[*-]* *\**(status|ステータス)\**[:：*]' "$adr_file" 2>/dev/null \
    | sed -E 's/^[*-]* *\**([Ss]tatus|ステータス)\**[:： ]*//; s/\*//g' | tr -d ' ' || true)
  if [ -z "$adr_status" ]; then
    adr_status=$(grep -m1 -iE '^\| *(status|ステータス) *\|' "$adr_file" 2>/dev/null \
      | awk -F'|' '{gsub(/^ +| +$/, "", $3); print $3}' || true)
  fi
  if [ -z "$adr_status" ]; then
    adr_status=$(awk '/^#+ *(ステータス|Status)/ {looking=1; next}
      looking && NF > 0 {gsub(/^ +| +$/, ""); print; exit}' "$adr_file" | cut -c1-30 || true)
  fi
  [ -n "$adr_status" ] || adr_status='不明'
  if grep -q '^## 改訂履歴' "$adr_file"; then
    revision_history='あり'
  else
    revision_history='なし'
  fi

  # --- scope 抽出 -----------------------------------------------------------
  scope_paths=''
  explicit_scope=$(grep -m1 -E '^ *[Ss]cope *:' "$adr_file" | sed -E 's/^ *[Ss]cope *: *//' || true)
  if [ -n "$explicit_scope" ]; then
    scope_paths=$(printf '%s' "$explicit_scope" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' || true)
  else
    scope_paths=$(grep -ohE '`[A-Za-z0-9_][A-Za-z0-9_./-]*`' "$adr_file" \
      | tr -d '`' | sort -u \
      | while IFS= read -r candidate_path; do
          case "$candidate_path" in
            */*|*.*) ;; # パスらしさ: / か 拡張子を含む
            *) continue ;;
          esac
          case "$candidate_path" in
            "$ADR_DIRECTORY"/*) continue ;; # ADR 自身の相互参照は除外
          esac
          [ -e "$candidate_path" ] && printf '%s\n' "$candidate_path"
        done | head -8 || true)
  fi

  if [ -z "$scope_paths" ]; then
    printf '[NO-SCOPE] %s (updated %s, status: %s, 改訂履歴: %s)\n' \
      "$base_name" "$adr_date" "$adr_status" "$revision_history"
    echo "    scope を特定できず。ADR 本文に 'Scope: <path>, <path>' 行の追加を推奨"
    no_scope_count=$((no_scope_count + 1))
    continue
  fi

  # --- 各 scope パスの ADR 以降のコミットを数える ----------------------------
  drift_detail=''
  while IFS= read -r scope_path; do
    [ -n "$scope_path" ] || continue
    [ -e "$scope_path" ] || continue
    commit_count=$(git log --oneline --since="$adr_iso" -- "$scope_path" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$commit_count" -gt 0 ]; then
      recent=$(git log -3 --format='      %ad %h %s' --date=short --since="$adr_iso" -- "$scope_path" 2>/dev/null)
      drift_detail="${drift_detail}    - ${scope_path}: ${commit_count} commits since ADR update
${recent}
"
    fi
  done <<EOF_SCOPE
$scope_paths
EOF_SCOPE

  if [ -n "$drift_detail" ]; then
    printf '[DRIFT]    %s (updated %s, status: %s, 改訂履歴: %s)\n' \
      "$base_name" "$adr_date" "$adr_status" "$revision_history"
    printf '%s' "$drift_detail"
    drift_count=$((drift_count + 1))
  else
    printf '[FRESH]    %s (updated %s, status: %s, 改訂履歴: %s)\n' \
      "$base_name" "$adr_date" "$adr_status" "$revision_history"
    fresh_count=$((fresh_count + 1))
  fi
done

echo "---"
echo "Summary: $total_count ADRs — drift: $drift_count, fresh: $fresh_count, no-scope: $no_scope_count"
