#!/usr/bin/env bash
# z3-tla-playbook の共通正本と Codex 配布物の同期・独立性を検証する。
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
sync_script="$repo_root/scripts/sync-z3-tla-playbook-codex.sh"
source_skill="$repo_root/dot_claude/skills/z3-tla-playbook"
codex_skill="$repo_root/dot_codex/skills/z3-tla-playbook"
codex_runtime_root="${CODEX_HOME:-$HOME/.codex}"
validator="$codex_runtime_root/skills/.system/skill-creator/scripts/quick_validate.py"

bash "$sync_script" --check

test -f "$validator" || {
  echo "FAILED: quick_validate.py not found: $validator" >&2
  exit 1
}

# 実リポジトリを汚さず、ずれを確実に検出して --write で修復できることを検査する。
drift_root="$(mktemp -d)"
trap 'rm -rf "$drift_root"' EXIT
mkdir -p "$drift_root/source" "$drift_root/codex"
cp -R "$source_skill" "$drift_root/source/z3-tla-playbook"
cp -R "$codex_skill" "$drift_root/codex/z3-tla-playbook"
drift_source="$drift_root/source/z3-tla-playbook"
drift_codex="$drift_root/codex/z3-tla-playbook"
printf '\n<!-- intentional drift -->\n' >> "$drift_codex/SKILL.md"
if Z3_TLA_ALLOW_TEMP_OVERRIDE=1 Z3_TLA_SOURCE_SKILL="$drift_source" Z3_TLA_CODEX_SKILL="$drift_codex" \
    bash "$sync_script" --check >/dev/null 2>&1; then
  echo "FAILED: --check accepted intentional drift" >&2
  exit 1
fi
Z3_TLA_ALLOW_TEMP_OVERRIDE=1 Z3_TLA_SOURCE_SKILL="$drift_source" Z3_TLA_CODEX_SKILL="$drift_codex" \
  bash "$sync_script" --write >/dev/null
Z3_TLA_ALLOW_TEMP_OVERRIDE=1 Z3_TLA_SOURCE_SKILL="$drift_source" Z3_TLA_CODEX_SKILL="$drift_codex" \
  bash "$sync_script" --check >/dev/null
echo "PASSED: drift detection and repair"

if Z3_TLA_ALLOW_TEMP_OVERRIDE=1 Z3_TLA_SOURCE_SKILL="$drift_source" Z3_TLA_CODEX_SKILL="$drift_source" \
    bash "$sync_script" --write >/dev/null 2>&1; then
  echo "FAILED: sync accepted source=destination" >&2
  exit 1
fi
if Z3_TLA_ALLOW_TEMP_OVERRIDE=1 Z3_TLA_SOURCE_SKILL="$drift_source" Z3_TLA_CODEX_SKILL="$repo_root" \
    bash "$sync_script" --write >/dev/null 2>&1; then
  echo "FAILED: sync accepted repository root as destination" >&2
  exit 1
fi
if Z3_TLA_SOURCE_SKILL="$drift_source" Z3_TLA_CODEX_SKILL="$drift_codex" \
    bash "$sync_script" --write >/dev/null 2>&1; then
  echo "FAILED: sync accepted temporary override without opt-in" >&2
  exit 1
fi

missing_parent="$drift_root/must-not-exist/nested"
if Z3_TLA_ALLOW_TEMP_OVERRIDE=1 Z3_TLA_SOURCE_SKILL="$drift_source" \
    Z3_TLA_CODEX_SKILL="$missing_parent/not-the-required-basename" \
    bash "$sync_script" --write >/dev/null 2>&1; then
  echo "FAILED: sync accepted invalid basename under missing parent" >&2
  exit 1
fi
if [ -e "$drift_root/must-not-exist" ]; then
  echo "FAILED: rejected destination created its parent directory" >&2
  exit 1
fi
echo "PASSED: destructive destination guards"

# 最初の mv が旧 package を退避した直後に同期 process へ TERM を送り、EXIT cleanup の復元を検査する。
signal_root="$drift_root/signal"
mkdir -p "$signal_root/source" "$signal_root/dest" "$signal_root/bin"
cp -R "$source_skill" "$signal_root/source/z3-tla-playbook"
cp -R "$codex_skill" "$signal_root/dest/z3-tla-playbook"
printf '%s\n' '<!-- old package sentinel -->' >> "$signal_root/dest/z3-tla-playbook/SKILL.md"
signal_source="$signal_root/source/z3-tla-playbook"
signal_dest="$signal_root/dest/z3-tla-playbook"
apply_patch_marker="$signal_root/mv-seen"
cat > "$signal_root/bin/mv" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
marker="${Z3_TLA_SIGNAL_MARKER:?}"
if [ ! -e "$marker" ]; then
  /bin/mv "$@"
  : > "$marker"
  kill -TERM "$PPID"
  exit 0
fi
exec /bin/mv "$@"
SH
chmod +x "$signal_root/bin/mv"
signal_exit=0
PATH="$signal_root/bin:$PATH" Z3_TLA_SIGNAL_MARKER="$apply_patch_marker" \
  Z3_TLA_ALLOW_TEMP_OVERRIDE=1 Z3_TLA_SOURCE_SKILL="$signal_source" Z3_TLA_CODEX_SKILL="$signal_dest" \
  bash "$sync_script" --write >/dev/null 2>&1 || signal_exit=$?
test "$signal_exit" -eq 143 || {
  echo "FAILED: signal-interrupted sync returned $signal_exit instead of 143" >&2
  exit 1
}
grep -Fq '<!-- old package sentinel -->' "$signal_dest/SKILL.md" || {
  echo "FAILED: signal-interrupted sync did not restore old package" >&2
  exit 1
}
if find "$signal_root/dest" -maxdepth 1 -name '.z3-tla-playbook.sync.*' | grep -q .; then
  echo "FAILED: signal-interrupted sync left staging directories" >&2
  exit 1
fi
echo "PASSED: signal-interrupted swap restores previous package"

source_count="$(find "$source_skill" -type f | wc -l | tr -d '[:space:]')"
codex_count="$(find "$codex_skill" -type f | wc -l | tr -d '[:space:]')"
if [ "$source_count" != "$codex_count" ]; then
  echo "FAILED: package file count differs (source=$source_count codex=$codex_count)" >&2
  exit 1
fi

for relative in \
  scripts/executable_setup-env.sh \
  scripts/executable_run-checks.sh \
  templates/model.py \
  templates/broken_model.py \
  templates/spec.tla \
  templates/spec.cfg \
  templates/spec.expect \
  templates/broken_spec.tla \
  templates/broken_spec.cfg \
  templates/ledger.md \
  reference/bug-catalog.md \
  reference/extraction-questions.md; do
  test -f "$codex_skill/$relative" || {
    echo "FAILED: Codex package file missing: $relative" >&2
    exit 1
  }
done

script_count=0
for script in "$codex_skill"/scripts/executable_*.sh; do
  script_count=$((script_count + 1))
  head -1 "$script" | grep -Fqx '#!/usr/bin/env bash' || {
    echo "FAILED: executable_ script has no bash shebang: $script" >&2
    exit 1
  }
done
test "$script_count" -eq 2 || {
  echo "FAILED: expected 2 executable_ scripts, got $script_count" >&2
  exit 1
}
echo "PASSED: executable source attributes and shebangs"

chezmoi_dump="$drift_root/chezmoi-dump.json"
chezmoi --source "$repo_root" dump > "$chezmoi_dump"
for target in \
  .codex/skills/z3-tla-playbook/scripts/setup-env.sh \
  .codex/skills/z3-tla-playbook/scripts/run-checks.sh; do
  permission="$(jq -r --arg target "$target" '.[$target].perm' "$chezmoi_dump")"
  test "$permission" = "493" || {
    echo "FAILED: chezmoi target is not executable: $target (perm=$permission)" >&2
    exit 1
  }
done
echo "PASSED: chezmoi renders Codex scripts with mode 0755"

if rg -n '\.claude|または /z3-tla-playbook|idchain|proven-done' "$codex_skill"; then
  echo "FAILED: Codex package contains host drift or development-pipeline coupling" >&2
  exit 1
fi

if rg -n 'z3-tla-playbook' \
  "$repo_root/dot_claude/skills/idchain-spec/SKILL.md" \
  "$repo_root/dot_claude/skills/proven-done/SKILL.md"; then
  echo "FAILED: independent debugger is referenced by idchain/proven-done" >&2
  exit 1
fi

python3 "$validator" "$source_skill"
python3 "$validator" "$codex_skill"

SKILL_DIR="dot_claude/skills/z3-tla-playbook" bash "$repo_root/tests/z3-tla-playbook-tests.sh"
SKILL_DIR="dot_codex/skills/z3-tla-playbook" bash "$repo_root/tests/z3-tla-playbook-tests.sh"

echo "z3-tla-playbook Codex sync tests: PASSED"
