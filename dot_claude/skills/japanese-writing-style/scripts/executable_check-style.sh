#!/usr/bin/env bash
# japanese-writing-style: 助詞直後の読点と見出し文体の候補を列挙する
# 出力は「違反候補」であり最終判断は読み手が行う (誤読防止・接続句の例外があるため)
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $(basename "$0") <file.md> [<file.md>...]" >&2
  exit 2
fi

exit_code=0

for file in "$@"; do
  if [ ! -f "$file" ]; then
    echo "ERROR: file not found: $file" >&2
    exit_code=2
    continue
  fi

  hits="$(awk '
    /^```/ { in_fence = !in_fence; next }
    in_fence { next }
    /^#+ / {
      if ($0 ~ /(です|ます|ました|ません|でした|でしょう|する|した)$/ || $0 ~ /。/) {
        printf "%s:%d:heading:%s\n", FILENAME, FNR, $0
      }
      next
    }
    /(は、|を、|が、|で、|など、)/ {
      printf "%s:%d:comma:%s\n", FILENAME, FNR, $0
    }
    /^[ \t]*[-*] \*\*[^*]+\*\* *[::]/ {
      printf "%s:%d:boldlabel:%s\n", FILENAME, FNR, $0
    }
    /。.+/ {
      printf "%s:%d:newline:%s\n", FILENAME, FNR, $0
    }
  ' "$file")"

  if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
    if [ "$exit_code" -eq 0 ]; then
      exit_code=1
    fi
  fi
done

if [ "$exit_code" -eq 0 ]; then
  echo "OK: 候補なし"
fi
exit "$exit_code"
