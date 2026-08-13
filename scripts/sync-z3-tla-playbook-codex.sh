#!/usr/bin/env bash
# z3-tla-playbook のローカル正本を Codex 用パッケージへ決定論的に同期する。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_skill="${Z3_TLA_SOURCE_SKILL:-$repo_root/dot_claude/skills/z3-tla-playbook}"
codex_skill="${Z3_TLA_CODEX_SKILL:-$repo_root/dot_codex/skills/z3-tla-playbook}"
mode="${1:---check}"

case "$mode" in
  --write|--check) ;;
  *) echo "usage: $0 [--write|--check]" >&2; exit 2 ;;
esac

test -f "$source_skill/SKILL.md" || {
  echo "source skill not found: $source_skill" >&2
  exit 2
}

canonical_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

resolve_without_creating() {
  python3 -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve(strict=False))' "$1"
}

source_skill="$(canonical_dir "$source_skill")" || {
  echo "source skill cannot be resolved: $source_skill" >&2
  exit 2
}
codex_basename="$(basename "$codex_skill")"
codex_parent_input="$(dirname "$codex_skill")"
codex_parent="$(resolve_without_creating "$codex_parent_input")" || {
  echo "destination parent cannot be resolved: $codex_parent_input" >&2
  exit 2
}
codex_skill="$codex_parent/$codex_basename"

[ "$(basename "$source_skill")" = "z3-tla-playbook" ] || {
  echo "source basename must be z3-tla-playbook: $source_skill" >&2
  exit 2
}
[ "$(basename "$codex_skill")" = "z3-tla-playbook" ] || {
  echo "destination basename must be z3-tla-playbook: $codex_skill" >&2
  exit 2
}
[ "$source_skill" != "$codex_skill" ] || {
  echo "source and destination must differ" >&2
  exit 2
}

expected_parent="$(canonical_dir "$repo_root/dot_codex/skills")"
if [ "$codex_parent" != "$expected_parent" ]; then
  temp_root="$(canonical_dir "${TMPDIR:-/tmp}")"
  case "$codex_parent/" in
    "$temp_root"/*/) ;;
    *) echo "destination outside allowed Codex or temporary parent: $codex_parent" >&2; exit 2 ;;
  esac
  [ "${Z3_TLA_ALLOW_TEMP_OVERRIDE:-0}" = "1" ] || {
    echo "temporary destination override requires Z3_TLA_ALLOW_TEMP_OVERRIDE=1" >&2
    exit 2
  }
fi

# 許可判定が完了するまで destination の親を作らない。
mkdir -p "$codex_parent"
codex_parent="$(canonical_dir "$codex_parent")" || exit 2
codex_skill="$codex_parent/$codex_basename"

# rename が同一 filesystem 上で atomic になるよう destination と同じ parent に staging を置く。
staging_root="$(mktemp -d "$codex_parent/.z3-tla-playbook.sync.XXXXXX")"
staging_skill="$staging_root/z3-tla-playbook"
previous="$staging_root/previous"
interrupted_new="$staging_root/interrupted-new"
swap_started=0
swap_committed=0

cleanup() {
  trap - EXIT INT TERM
  if [ "$swap_started" -eq 1 ] && [ "$swap_committed" -eq 0 ] && [ -e "$previous" ]; then
    if [ -e "$codex_skill" ]; then
      mv "$codex_skill" "$interrupted_new" || true
    fi
    mv "$previous" "$codex_skill" || {
      echo "CRITICAL: failed to restore previous package: $previous -> $codex_skill" >&2
      return 1
    }
  fi
  rm -rf "$staging_root"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$staging_skill"

# 共通本文は変えず、Codex のホームと Skill 呼び出し表記だけを変換する。
while IFS= read -r relative; do
  mkdir -p "$staging_skill/$(dirname "$relative")"
  sed \
    -e 's|~/.claude|~/.codex|g' \
    -e 's|\$HOME/.claude|$HOME/.codex|g' \
    -e 's|または /z3-tla-playbook|または $z3-tla-playbook|g' \
    "$source_skill/$relative" > "$staging_skill/$relative"
done < <(cd "$source_skill" && find . -type f -print | sed 's|^./||' | LC_ALL=C sort)

if [ "$mode" = "--write" ]; then
  if [ -e "$codex_skill" ]; then
    swap_started=1
    mv "$codex_skill" "$previous"
  fi
  if ! mv "$staging_skill" "$codex_skill"; then
    echo "failed to atomically install Codex package" >&2
    exit 1
  fi
  swap_committed=1
  echo "z3-tla-playbook Codex sync: write OK"
  exit 0
fi

if [ ! -d "$codex_skill" ]; then
  echo "Codex package missing: $codex_skill" >&2
  echo "run: $0 --write" >&2
  exit 1
fi

if ! diff -ru "$staging_skill" "$codex_skill"; then
  echo "z3-tla-playbook Codex sync: drift detected" >&2
  echo "run: $0 --write" >&2
  exit 1
fi

echo "z3-tla-playbook Codex sync: check OK"
