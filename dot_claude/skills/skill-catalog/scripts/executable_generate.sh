#!/bin/bash
# skill-catalog generate — 全 skill の棚卸しデータ (USAGE.md) を再生成する
# - 使用実績: ~/.claude/projects/*/*.jsonl の Skill 呼び出しを集計
# - 在庫: ~/.claude/skills/*/SKILL.md の name + description 先頭
# - 未使用リスト: 呼び出し実績 0 の自作 skill (アーカイブ候補)
# usage: generate.sh
set -eu

SKILLS_ROOT="${SKILLS_ROOT:-$HOME/.claude/skills}"
PROJECTS_ROOT="${PROJECTS_ROOT:-$HOME/.claude/projects}"
OUTPUT="$SKILLS_ROOT/skill-catalog/USAGE.md"
GENERATED_AT=$(date '+%Y-%m-%d %H:%M')

work_directory=$(mktemp -d)
trap 'rm -rf "$work_directory"' EXIT

# --- 1. 使用実績集計 ------------------------------------------------------
usage_file="$work_directory/usage.txt"
grep -oh '"skill":"[^"]*"' "$PROJECTS_ROOT"/*/*.jsonl 2>/dev/null \
  | sed 's/"skill":"//; s/"$//' \
  | sort | uniq -c | sort -rn \
  | awk '{print $2 "|" $1}' > "$usage_file" || true

usage_count_of() {
  local skill_name="$1"
  local line
  line=$(grep -m1 "^${skill_name}|" "$usage_file" 2>/dev/null || true)
  if [ -n "$line" ]; then
    printf '%s' "${line#*|}"
  else
    printf '0'
  fi
}

# --- 2. 在庫スキャン ------------------------------------------------------
inventory_file="$work_directory/inventory.txt"
: > "$inventory_file"
for skill_directory in "$SKILLS_ROOT"/*/; do
  skill_manifest="$skill_directory/SKILL.md"
  [ -f "$skill_manifest" ] || continue
  skill_name=$(basename "$skill_directory")
  description=$(sed -n 's/^description: *//p' "$skill_manifest" | head -1 | tr -d '"' | cut -c1-140)
  [ -n "$description" ] || description='(description なし)'
  count=$(usage_count_of "$skill_name")
  printf '%s|%s|%s\n' "$count" "$skill_name" "$description" >> "$inventory_file"
done

total_skills=$(wc -l < "$inventory_file" | tr -d ' ')
unused_skills=$(awk -F'|' '$1 == 0' "$inventory_file" | wc -l | tr -d ' ')

# --- 3. USAGE.md 出力 -----------------------------------------------------
{
  echo "# Skill 棚卸しデータ (自動生成)"
  echo
  echo "生成日時: $GENERATED_AT / 自作 skill 総数: $total_skills / 未使用: $unused_skills"
  echo
  echo "このファイルは \`scripts/generate.sh\` が上書きする。手で編集しない。"
  echo "ルーティング判断の正本は同ディレクトリの INDEX.md。"
  echo
  echo "## 使用実績ランキング (transcripts 全期間)"
  echo
  echo "| 回数 | skill | description (先頭) |"
  echo "|---:|---|---|"
  sort -t'|' -k1,1nr "$inventory_file" | awk -F'|' '$1 > 0 {printf "| %s | %s | %s |\n", $1, $2, $3}'
  echo
  echo "## 呼び出し実績のある plugin / 外部 skill (在庫外)"
  echo
  echo '```'
  while IFS='|' read -r used_name used_count; do
    if ! awk -F'|' -v n="$used_name" '$2 == n {found=1} END {exit !found}' "$inventory_file"; then
      printf '%5s  %s\n' "$used_count" "$used_name"
    fi
  done < "$usage_file"
  echo '```'
  echo
  echo "## 未使用 skill (アーカイブ候補)"
  echo
  echo "| skill | description (先頭) |"
  echo "|---|---|"
  sort -t'|' -k2,2 "$inventory_file" | awk -F'|' '$1 == 0 {printf "| %s | %s |\n", $2, $3}'
} > "$OUTPUT"

echo "generated: $OUTPUT"
echo "skills: $total_skills (unused: $unused_skills)"
