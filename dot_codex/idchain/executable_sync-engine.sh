#!/usr/bin/env bash
# chezmoi apply 時に idchain engine 正本を ~/.codex へ原子的に同期する。
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <source-engine> <destination-engine> <expected-sha256>" >&2
  exit 2
fi

source_engine="$1"
destination_engine="$2"
expected_digest="$3"

case "$source_engine" in
  /*/idchain/engine) ;;
  *) echo "idchain engine sync: source must end in /idchain/engine" >&2; exit 2 ;;
esac

case "$destination_engine" in
  /*/idchain/engine) ;;
  *) echo "idchain engine sync: destination must end in /idchain/engine" >&2; exit 2 ;;
esac

if [[ ! "$expected_digest" =~ ^[0-9a-f]{64}$ ]]; then
  echo "idchain engine sync: invalid expected digest" >&2
  exit 2
fi

if [ ! -f "$source_engine/lakefile.toml" ] || [ ! -f "$source_engine/Idchain.lean" ]; then
  echo "idchain engine sync: source is not an idchain engine" >&2
  exit 2
fi

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

source_digest="$(compute_engine_digest "$source_engine")"
if [ "$source_digest" != "$expected_digest" ]; then
  echo "idchain engine sync: source digest mismatch (expected $expected_digest, got $source_digest)" >&2
  exit 1
fi

if [ -d "$destination_engine" ] && [ "$(compute_engine_digest "$destination_engine")" = "$expected_digest" ]; then
  echo "idchain engine sync: already current ($expected_digest)"
  exit 0
fi

destination_parent="$(dirname "$destination_engine")"
mkdir -p "$destination_parent"
staging_directory="$(mktemp -d "$destination_parent/.engine.sync.XXXXXX")"
backup_directory=""

cleanup() {
  if [ -n "$staging_directory" ] && [ -d "$staging_directory" ]; then
    rm -rf "$staging_directory"
  fi
  if [ -n "$backup_directory" ] && [ -d "$backup_directory" ] && [ ! -d "$destination_engine" ]; then
    mv "$backup_directory" "$destination_engine"
  fi
}
trap cleanup EXIT

rsync -a --delete --exclude '.lake/' --exclude '.DS_Store' "$source_engine/" "$staging_directory/"

staging_digest="$(compute_engine_digest "$staging_directory")"
if [ "$staging_digest" != "$expected_digest" ]; then
  echo "idchain engine sync: staged digest mismatch" >&2
  exit 1
fi

if [ -e "$destination_engine" ]; then
  backup_directory="$(mktemp -d "$destination_parent/.engine.backup.XXXXXX")"
  rmdir "$backup_directory"
  mv "$destination_engine" "$backup_directory"
fi

mv "$staging_directory" "$destination_engine"
staging_directory=""

if [ -n "$backup_directory" ] && [ -d "$backup_directory" ]; then
  rm -rf "$backup_directory"
  backup_directory=""
fi

trap - EXIT
echo "idchain engine sync: installed $expected_digest"
