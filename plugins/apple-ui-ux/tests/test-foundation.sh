#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d -t apple-ui-ux-foundation.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT

if [[ -f "$plugin_root/dot_codex-plugin/plugin.json" ]]; then
  cmp "$plugin_root/.codex-plugin/plugin.json" "$plugin_root/dot_codex-plugin/plugin.json"
fi
if [[ -f "$plugin_root/dot_claude-plugin/plugin.json" ]]; then
  cmp "$plugin_root/.claude-plugin/plugin.json" "$plugin_root/dot_claude-plugin/plugin.json"
fi

jq -e '.name == "apple-ui-ux" and .od.kind == "bundle" and .od.capabilities == ["prompt:inject", "fs:read", "fs:write"]' \
  "$plugin_root/open-design.json" >/dev/null
while IFS= read -r relative; do
  test -f "$plugin_root/${relative#./}"
done < <(jq -r '.compat.agentSkills[].path, .compat.claudePlugins[].path' "$plugin_root/open-design.json")
test -f "$plugin_root/design-systems/apple-public-ui-ux/DESIGN.md"

python3 "$plugin_root/scripts/approval_gate.py" validate-foundation

mkdir -p "$test_root/design/apple-ui-ux/artifacts"
cp "$plugin_root/tests/fixtures/apple-ui-ux-spec.yaml" "$test_root/design/apple-ui-ux/apple-ui-ux-spec.yaml"
cp "$plugin_root/tests/fixtures/today.html" "$test_root/design/apple-ui-ux/artifacts/today.html"

python3 "$plugin_root/scripts/approval_gate.py" validate-spec --project-root "$test_root"
python3 "$plugin_root/scripts/approval_gate.py" approve \
  --project-root "$test_root" \
  --approved-by fixture-user \
  --confirm APPROVE
python3 "$plugin_root/scripts/approval_gate.py" check-approval --project-root "$test_root"

printf '%s\n' '<!-- tampered -->' >> "$test_root/design/apple-ui-ux/artifacts/today.html"
if python3 "$plugin_root/scripts/approval_gate.py" check-approval --project-root "$test_root" >/dev/null 2>&1; then
  echo "ERROR: changed design artifact retained approval" >&2
  exit 1
fi

if (cd "$plugin_root" && rg -n '\[TODO:' . --glob '!tests/test-foundation.sh'); then
  echo "ERROR: scaffold placeholder found" >&2
  exit 1
fi

echo "OK: apple-ui-ux foundation tests"
