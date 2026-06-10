#!/usr/bin/env bash
# agent-policy-kit: 対象リポジトリの言語・構成・既存ガードを検出して報告する (Detect phase)。
# 使い方: bash detect-langs.sh [repo_root]
set -euo pipefail

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$root"

echo "repo_root=$root"
echo "repo_name=$(basename "$root")"

# 言語検出
langs=""
[ -n "$(find . -maxdepth 3 -name '*.cabal' -not -path '*/dist-newstyle/*' 2>/dev/null | head -1)" ] && langs="${langs}haskell "
{ [ -f package.json ] || [ -f pnpm-workspace.yaml ]; } && langs="${langs}typescript "
[ -f go.mod ] && langs="${langs}go "
[ -f composer.json ] && langs="${langs}php "
{ [ -f pyproject.toml ] || [ -f setup.py ]; } && langs="${langs}python "
[ -f Cargo.toml ] && langs="${langs}rust "
echo "languages=${langs:-unknown}"

# モノレポ構成
echo "--- apps/packages ---"
find . -maxdepth 2 -type d \( -name 'applications' -o -name 'apps' -o -name 'packages' -o -name 'services' \) -not -path '*/node_modules/*' 2>/dev/null
find applications apps packages services -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -20

# 既存ガード
echo "--- existing guards ---"
[ -f scripts/fitness/hook.sh ] && echo "fitness_hook=scripts/fitness/hook.sh"
[ -d .ast-grep/rules ] && echo "ast_grep_rules=$(ls .ast-grep/rules 2>/dev/null | tr '\n' ',')"
[ -f sgconfig.yml ] && echo "ast_grep_config=sgconfig.yml"
find . -maxdepth 3 -name '.hlint.yaml' -not -path '*/dist-newstyle/*' 2>/dev/null | sed 's/^/hlint_config=/'
[ -f .claude/settings.json ] && echo "claude_settings=.claude/settings.json"
echo "--- ci ---"
ls .github/workflows/*.yml 2>/dev/null | sed 's/^/workflow=/' || echo "no workflows"

# 既に kit を適用済みか
echo "--- kit status ---"
for f in AGENTS.md wiring_manifest.yml ci/allowlist.yml scripts/verify-no-prod-doubles.sh scripts/agent-policy-hook.sh .github/workflows/pr-gate.yml; do
  [ -e "$f" ] && echo "present=$f" || echo "absent=$f"
done
