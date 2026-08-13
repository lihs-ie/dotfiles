#!/usr/bin/env bash
# dot_claude -> dot_codex Skill sync and chezmoi engine materialization contract.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
sync_script="$repo_root/scripts/sync-idchain-codex.sh"
engine_sync="$repo_root/dot_codex/idchain/executable_sync-engine.sh"
engine_source="$repo_root/dot_claude/idchain/engine"
engine_digest="$(tr -d '[:space:]' < "$repo_root/dot_codex/idchain/engine-source.sha256")"

bash "$sync_script" --check
python3 -m json.tool "$repo_root/dot_codex/hooks.json" >/dev/null

if rg -n '~/.claude|dot_claude|AskUserQuestion|\(2\) /idchain' "$repo_root/dot_codex/skills"; then
  echo "Codex Skill に Claude 固有参照が残っている" >&2
  exit 1
fi

rendered_hook="$(chezmoi --source "$repo_root" execute-template < "$repo_root/run_onchange_after_sync-idchain-codex-engine.sh.tmpl")"
if ! printf '%s' "$rendered_hook" | grep -Fq "$engine_digest"; then
  echo "run_onchange template に engine digest が埋め込まれていない" >&2
  exit 1
fi
if ! printf '%s' "$rendered_hook" | grep -Fq "$repo_root/dot_claude/idchain/engine"; then
  echo "run_onchange template が明示 source を参照していない" >&2
  exit 1
fi

work_directory="$(mktemp -d)"
trap 'rm -rf "$work_directory"' EXIT
destination="$work_directory/idchain/engine"

bash "$engine_sync" "$engine_source" "$destination" "$engine_digest"
if ! diff -qr --exclude='.lake' "$engine_source" "$destination"; then
  echo "engine 実体が正本と一致しない" >&2
  exit 1
fi

printf '\ncorruption\n' >> "$destination/Idchain.lean"
bash "$engine_sync" "$engine_source" "$destination" "$engine_digest"
if ! diff -qr --exclude='.lake' "$engine_source" "$destination"; then
  echo "engine 再同期がドリフトを修復できない" >&2
  exit 1
fi

already_current_output="$(bash "$engine_sync" "$engine_source" "$destination" "$engine_digest")"
if ! printf '%s' "$already_current_output" | grep -Fq 'already current'; then
  echo "engine 同期が current 状態を認識しない" >&2
  exit 1
fi

echo "idchain Codex sync tests: PASSED"
