#!/bin/bash
# workspace-resume scan — workspace 全リポジトリの俯瞰、または単一リポジトリの再開用深掘りダンプ
# usage:
#   scan.sh                     # dashboard: 全リポジトリの状態一覧 (直近90日 or dirty のみ)
#   scan.sh <repository-name>   # deep: 1 リポジトリの再開ブリーフ用素材を全部出す
# 環境変数:
#   WORKSPACE_ROOT (default: $HOME/workspace)
#   DASHBOARD_DAYS (default: 90)
set -eu

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/workspace}"
DASHBOARD_DAYS="${DASHBOARD_DAYS:-90}"

# ---------------------------------------------------------------------------
dashboard() {
  local now cutoff
  now=$(date +%s)
  cutoff=$((now - DASHBOARD_DAYS * 86400))

  printf '%s\n' "LAST_COMMIT|REPOSITORY|BRANCH|DIRTY|AHEAD/BEHIND|HANDOFF|LAST_SUBJECT"
  local repository_path name branch dirty last_commit_timestamp last_commit_date
  local ahead_behind handoff last_subject
  for repository_path in "$WORKSPACE_ROOT"/*/; do
    [ -d "$repository_path/.git" ] || continue
    name=$(basename "$repository_path")

    last_commit_timestamp=$(git -C "$repository_path" log -1 --format='%ct' 2>/dev/null || echo 0)
    dirty=$(git -C "$repository_path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

    # 直近 DASHBOARD_DAYS 日にコミットがない & クリーンなリポジトリは省略
    if [ "$last_commit_timestamp" -lt "$cutoff" ] && [ "$dirty" = "0" ]; then
      continue
    fi

    last_commit_date=$(git -C "$repository_path" log -1 --format='%ad' --date=short 2>/dev/null || echo '-')
    last_subject=$(git -C "$repository_path" log -1 --format='%s' 2>/dev/null | cut -c1-60 || echo '-')
    branch=$(git -C "$repository_path" branch --show-current 2>/dev/null || echo '-')
    [ -n "$branch" ] || branch='(detached)'

    ahead_behind='-'
    if git -C "$repository_path" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
      ahead_behind=$(git -C "$repository_path" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null \
        | awk '{print "+" $2 "/-" $1}' || echo '-')
    fi

    handoff='no'
    if [ -f "$repository_path/HANDOFF.md" ]; then
      handoff=$(date -r "$repository_path/HANDOFF.md" '+%Y-%m-%d' 2>/dev/null || echo 'yes')
    fi

    printf '%s|%s|%s|%s|%s|%s|%s\n' \
      "$last_commit_date" "$name" "$branch" "$dirty" "$ahead_behind" "$handoff" "$last_subject"
  done | sort -t'|' -k1,1r
}

# ---------------------------------------------------------------------------
section() { printf '\n=== %s ===\n' "$1"; }

deep() {
  local name="$1"
  local repository_path="$WORKSPACE_ROOT/$name"
  if [ ! -d "$repository_path" ]; then
    echo "ERROR: $repository_path が存在しません" >&2
    exit 1
  fi
  if [ ! -d "$repository_path/.git" ]; then
    echo "WARN: $repository_path は git リポジトリではありません (ファイル一覧のみ)" >&2
    ls -la "$repository_path" | head -30
    exit 0
  fi

  section "SUMMARY"
  echo "repository: $name"
  echo "branch: $(git -C "$repository_path" branch --show-current 2>/dev/null || echo '(detached)')"
  echo "last_commit: $(git -C "$repository_path" log -1 --format='%ad %h %s' --date=iso 2>/dev/null)"

  section "STATUS (uncommitted)"
  git -C "$repository_path" status --porcelain 2>/dev/null | head -40 || true
  local dirty_total
  dirty_total=$(git -C "$repository_path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  echo "(total: $dirty_total files)"

  section "RECENT COMMITS (15)"
  git -C "$repository_path" log -15 --format='%ad %h %s' --date=short 2>/dev/null || true

  section "RECENT BRANCHES (by commit date)"
  git -C "$repository_path" for-each-ref --sort=-committerdate refs/heads \
    --format='%(committerdate:short) %(refname:short)' 2>/dev/null | head -8 || true

  section "STASHES"
  git -C "$repository_path" stash list 2>/dev/null | head -5 || true

  section "HANDOFF.md"
  if [ -f "$repository_path/HANDOFF.md" ]; then
    cat "$repository_path/HANDOFF.md"
  else
    echo "(なし — /workspace-resume save で作成可能)"
  fi

  section "TODO"
  local todo_file
  for todo_file in "$repository_path/TODO.md" "$repository_path/docs/todo.md" "$repository_path/docs/TODO.md" "$repository_path/TODO.md.local.bak"; do
    if [ -f "$todo_file" ]; then
      echo "--- $todo_file (head 30) ---"
      head -30 "$todo_file"
    fi
  done

  section "OPEN PULL REQUESTS"
  if command -v gh >/dev/null 2>&1 && git -C "$repository_path" remote get-url origin >/dev/null 2>&1; then
    (cd "$repository_path" && gh pr list --limit 10 2>/dev/null) || echo "(gh pr list 失敗 — remote なし or 未認証)"
  else
    echo "(gh なし or remote なし)"
  fi

  section "AGENT EVIDENCE (latest 3)"
  if [ -d "$repository_path/.agent-evidence" ]; then
    ls -1t "$repository_path/.agent-evidence" 2>/dev/null | head -3 || true
  else
    echo "(なし)"
  fi

  section "ADR (latest 3)"
  local adr_directory
  for adr_directory in "$repository_path/docs/adr" "$repository_path/adr" "$repository_path/docs/ADR"; do
    if [ -d "$adr_directory" ]; then
      ls -1t "$adr_directory"/*.md 2>/dev/null | head -3 || true
      break
    fi
  done
}

# ---------------------------------------------------------------------------
if [ $# -eq 0 ]; then
  dashboard
else
  deep "$1"
fi
