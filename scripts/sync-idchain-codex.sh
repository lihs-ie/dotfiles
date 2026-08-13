#!/usr/bin/env bash
# dot_claude の idchain Skill 正本から dot_codex 配布実体と engine digest を同期する。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_skills="$repo_root/dot_claude/skills"
codex_skills="$repo_root/dot_codex/skills"
engine_source="$repo_root/dot_claude/idchain/engine"
digest_file="$repo_root/dot_codex/idchain/engine-source.sha256"
mode="${1:---write}"

skill_names=(
  idchain
  idchain-init
  idchain-discovery
  idchain-spec
  idchain-approve
  idchain-build
  idchain-retro
)

case "$mode" in
  --write|--check) ;;
  *)
    echo "usage: $0 [--write|--check]" >&2
    exit 2
    ;;
esac

compute_engine_digest() {
  local directory="$1"
  (
    cd "$directory"
    find . -type f \
      ! -path './.lake/*' \
      ! -name '.DS_Store' \
      -print \
      | LC_ALL=C sort \
      | while IFS= read -r path; do
          printf '%s\n' "$path"
          shasum -a 256 "$path" | awk '{print $1}'
        done
  ) | shasum -a 256 | awk '{print $1}'
}

render_codex_skill() {
  sed \
    -e 's|^- engine の正本は `dot_claude/idchain/engine/`。chezmoi 配布後は `~/.claude/idchain/engine/` に存在する。|- engine は共通正本の digest 検証後、chezmoi により `~/.codex/idchain/engine/` へ実体同期される。|' \
    -e 's|~/.claude/skills/|~/.codex/skills/|g' \
    -e 's|~/.claude/idchain/engine|~/.codex/idchain/engine|g' \
    -e 's|AskUserQuestion または対話で|対話で|g' \
    -e 's|AskUserQuestion で|ユーザーに|g' \
    -e 's|<ID>|[ID]|g' \
    -e 's|(2) /idchain-|(2) $idchain-|g' \
    -e 's|(2) /idchain \[|(2) $idchain [|g' \
    "$1"
}

failures=0

for skill_name in "${skill_names[@]}"; do
  source_file="$source_skills/$skill_name/SKILL.md"
  destination_file="$codex_skills/$skill_name/SKILL.md"

  if [ ! -f "$source_file" ]; then
    echo "missing source skill: $source_file" >&2
    failures=$((failures + 1))
    continue
  fi

  if [ "$mode" = "--write" ]; then
    mkdir -p "$(dirname "$destination_file")"
    temporary_file="$(mktemp)"
    render_codex_skill "$source_file" > "$temporary_file"
    install -m 0644 "$temporary_file" "$destination_file"
    rm -f "$temporary_file"
  elif [ ! -f "$destination_file" ]; then
    echo "missing generated skill: $destination_file" >&2
    failures=$((failures + 1))
  elif ! render_codex_skill "$source_file" | diff -u - "$destination_file"; then
    echo "stale generated skill: $destination_file" >&2
    failures=$((failures + 1))
  fi
done

engine_digest="$(compute_engine_digest "$engine_source")"

if [ "$mode" = "--write" ]; then
  mkdir -p "$(dirname "$digest_file")"
  printf '%s\n' "$engine_digest" > "$digest_file"
elif [ ! -f "$digest_file" ]; then
  echo "missing engine digest: $digest_file" >&2
  failures=$((failures + 1))
elif [ "$(tr -d '[:space:]' < "$digest_file")" != "$engine_digest" ]; then
  echo "stale engine digest: $digest_file" >&2
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi

echo "idchain Codex sync: $mode OK (engine $engine_digest)"
