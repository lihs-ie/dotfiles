#!/usr/bin/env bash
# agent-policy: iterations.json の failure_class を検証する。
# - 未知 enum → exit 1
# - 末尾 3 entries 同一 failure_class (collapsed loop) → exit 2
# - file 未存在 → exit 0 (初回前)
# - failure_class 空 → exit 1
# - 正常 → exit 0
# 使い方: verify-failure-class.sh [path/to/iterations.json]
set -euo pipefail

VALID_CLASSES="product test-oracle harness-env flaky wiring-integration"

target="${1:-.agent-evidence/iterations.json}"

if [ ! -f "$target" ]; then
  echo "verify-failure-class: $target not found (OK — first run)" >&2
  exit 0
fi

# JSON parsing: jq preferred, python3 fallback
if command -v jq >/dev/null 2>&1; then
  classes="$(jq -r '.iterations[].failure_class // empty' "$target" 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
  classes="$(python3 -c "
import json, sys
data = json.load(open('$target'))
for i in data.get('iterations', []):
    fc = i.get('failure_class', '')
    print(fc)
" 2>/dev/null)"
else
  echo "verify-failure-class: WARNING: neither jq nor python3 found; skipping check" >&2
  exit 0
fi

if [ -z "$classes" ]; then
  echo "verify-failure-class: ERROR: no failure_class entries found (empty or missing)" >&2
  exit 1
fi

# Check for unknown classes
while IFS= read -r cls; do
  if [ -z "$cls" ]; then
    echo "verify-failure-class: ERROR: empty failure_class" >&2
    exit 1
  fi
  found=0
  for valid in $VALID_CLASSES; do
    if [ "$cls" = "$valid" ]; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "verify-failure-class: ERROR: unknown failure_class '$cls' (valid: $VALID_CLASSES)" >&2
    exit 1
  fi
done <<< "$classes"

# Check for collapsed loop (last 3 entries all same class)
total=$(echo "$classes" | wc -l | tr -d ' ')
if [ "$total" -ge 3 ]; then
  last3=$(echo "$classes" | tail -3)
  uniq_count=$(echo "$last3" | sort -u | wc -l | tr -d ' ')
  if [ "$uniq_count" -eq 1 ]; then
    last_cls=$(echo "$last3" | head -1)
    echo "verify-failure-class: ERROR: collapsed loop detected — last 3 iterations all have failure_class='$last_cls'" >&2
    exit 2
  fi
fi

echo "verify-failure-class: OK"
exit 0
