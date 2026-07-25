#!/usr/bin/env bash
# z3-tla-playbook: 検証環境を「宣言的に固める」ためのセットアップ/検証スクリプト。
#
# playbook §5「依存を宣言的に固める」の実装。nix が無い環境でも
# 「ネットワークとローカル環境に依存せず誰でも同じ結果」に近づけるため、
# 実際に入ったバージョンを formal-lock.json に記録し、以後 --check で照合する。
#
#   --init     検証ディレクトリ (既定 .formal/) を作り、テンプレートを配置する
#   --install  z3-solver (venv) と tla2tools.jar を導入し、lock に版を記録する
#   --check    lock と実環境の整合を検査する (既定動作)
#
# exit code: 0 = 要求レーンが揃っている / 1 = 不足あり / 2 = 引数エラー
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(dirname "$script_dir")"
templates_dir="$skill_dir/templates"

target_dir=".formal"
lane="both"
action="check"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) target_dir="${2:?--dir needs a value}"; shift 2 ;;
    --lane) lane="${2:?--lane needs a value}"; shift 2 ;;
    --init) action="init"; shift ;;
    --install) action="install"; shift ;;
    --check) action="check"; shift ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$lane" in
  z3|tla|both) ;;
  *) echo "--lane must be one of: z3 tla both" >&2; exit 2 ;;
esac

lock_file="$target_dir/formal-lock.json"
venv_dir="$target_dir/.venv"
tools_dir="$target_dir/tools"
jar_path="$tools_dir/tla2tools.jar"

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

read_lock_field() {
  # $1 = key。lock が無ければ空文字。jq に依存しない (環境前提を増やさない)。
  [ -f "$lock_file" ] || { printf ''; return 0; }
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$lock_file" | head -1
}

venv_python() {
  if [ -x "$venv_dir/bin/python" ]; then
    printf '%s' "$venv_dir/bin/python"
  else
    command -v python3 || true
  fi
}

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    printf 'unavailable'
  fi
}

write_lock() {
  # 実際に入ったものを記録する (推測値を書かない)。
  local z3_version="$1" jar_version="$2" jar_sha="$3"
  mkdir -p "$target_dir"
  cat > "$lock_file" <<JSON
{
  "generated_by": "z3-tla-playbook/scripts/setup-env.sh",
  "z3_solver_version": "$(json_escape "$z3_version")",
  "tla2tools_version": "$(json_escape "$jar_version")",
  "tla2tools_sha256": "$(json_escape "$jar_sha")"
}
JSON
  echo "lock updated: $lock_file"
}

do_init() {
  mkdir -p "$target_dir/models/broken" "$target_dir/specs/broken" "$tools_dir"

  # バイナリ (venv / jar) は commit しない。lock だけを版の正本にする。
  cat > "$target_dir/.gitignore" <<'IGNORE'
.venv/
tools/
states/
*.st
IGNORE

  copy_template() {
    local src="$templates_dir/$1" dest="$target_dir/$2"
    if [ ! -f "$src" ]; then
      echo "template missing: $src" >&2
      return 1
    fi
    if [ -e "$dest" ]; then
      echo "keep (exists): $dest"
    else
      cp "$src" "$dest"
      echo "created: $dest"
    fi
  }

  copy_template "model.py" "models/example_cap.py"
  copy_template "broken_model.py" "models/broken/example_cap__guard-removed.py"
  copy_template "spec.tla" "specs/Example.tla"
  copy_template "spec.cfg" "specs/Example.cfg"
  copy_template "spec.expect" "specs/Example.expect"
  # TLA+ のモジュール名はファイル名と一致する必要があるためハイフンを使わない。
  copy_template "broken_spec.tla" "specs/broken/Example__StaleRead.tla"
  copy_template "broken_spec.cfg" "specs/broken/Example__StaleRead.cfg"
  copy_template "ledger.md" "ledger.md"

  echo ""
  echo "初期化しました: $target_dir"
  echo "次: $0 --dir $target_dir --install   (依存導入)"
}

do_install() {
  mkdir -p "$target_dir" "$tools_dir"
  local z3_version="" jar_version="" jar_sha=""
  local failed=0

  if [ "$lane" = "z3" ] || [ "$lane" = "both" ]; then
    echo "== z3-solver (Python binding) =="
    if [ ! -d "$venv_dir" ]; then
      if command -v uv >/dev/null 2>&1; then
        uv venv "$venv_dir" >/dev/null
      else
        python3 -m venv "$venv_dir"
      fi
    fi
    if command -v uv >/dev/null 2>&1; then
      VIRTUAL_ENV="$venv_dir" uv pip install --quiet z3-solver || failed=1
    else
      "$venv_dir/bin/pip" install --quiet --upgrade pip >/dev/null 2>&1 || true
      "$venv_dir/bin/pip" install --quiet z3-solver || failed=1
    fi
    if [ "$failed" -eq 0 ]; then
      z3_version="$("$venv_dir/bin/python" -c 'import z3; print(z3.get_version_string())' 2>/dev/null || true)"
      if [ -n "$z3_version" ]; then
        echo "installed: z3 $z3_version ($venv_dir)"
      else
        echo "z3-solver の import に失敗しました" >&2
        failed=1
      fi
    else
      echo "z3-solver の導入に失敗しました (ネットワーク/権限を確認)" >&2
    fi
  fi

  if [ "$lane" = "tla" ] || [ "$lane" = "both" ]; then
    echo "== tla2tools.jar (TLC model checker) =="
    if [ -f "$jar_path" ]; then
      echo "keep (exists): $jar_path"
    else
      # 版は推測せず、実際に解決できたタグを記録する。
      local tag=""
      if command -v gh >/dev/null 2>&1; then
        tag="$(gh release view --repo tlaplus/tlaplus --json tagName -q .tagName 2>/dev/null || true)"
      fi
      if [ -z "$tag" ]; then
        tag="$(curl -fsSL https://api.github.com/repos/tlaplus/tlaplus/releases/latest 2>/dev/null \
          | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)"
      fi
      if [ -z "$tag" ]; then
        echo "tlaplus の最新タグを解決できませんでした (ネットワーク不通か API 制限)" >&2
        failed=1
      elif curl -fsSL -o "$jar_path" \
          "https://github.com/tlaplus/tlaplus/releases/download/$tag/tla2tools.jar" 2>/dev/null; then
        jar_version="$tag"
        echo "installed: tla2tools.jar $tag"
      else
        echo "tla2tools.jar のダウンロードに失敗しました ($tag)" >&2
        rm -f "$jar_path"
        failed=1
      fi
    fi
    if [ -f "$jar_path" ]; then
      jar_sha="$(sha256_of "$jar_path")"
      [ -z "$jar_version" ] && jar_version="$(read_lock_field tla2tools_version)"
    fi
  fi

  [ -z "$z3_version" ] && z3_version="$(read_lock_field z3_solver_version)"
  [ -z "$jar_version" ] && jar_version="$(read_lock_field tla2tools_version)"
  [ -z "$jar_sha" ] && jar_sha="$(read_lock_field tla2tools_sha256)"
  write_lock "$z3_version" "$jar_version" "$jar_sha"

  return "$failed"
}

do_check() {
  local missing=0
  echo "== 環境検査 (dir=$target_dir, lane=$lane) =="

  if [ "$lane" = "z3" ] || [ "$lane" = "both" ]; then
    local py; py="$(venv_python)"
    local actual=""
    if [ -n "$py" ]; then
      actual="$("$py" -c 'import z3; print(z3.get_version_string())' 2>/dev/null || true)"
    fi
    if [ -n "$actual" ]; then
      local locked; locked="$(read_lock_field z3_solver_version)"
      if [ -n "$locked" ] && [ "$locked" != "$actual" ]; then
        echo "WARN  z3-solver: $actual (lock: $locked) — 版がずれています"
      else
        echo "OK    z3-solver: $actual"
      fi
    else
      echo "MISS  z3-solver: Python から import できません → $0 --dir $target_dir --install"
      missing=1
    fi
    if command -v z3 >/dev/null 2>&1; then
      echo "OK    z3 CLI: $(z3 --version 2>/dev/null | head -1)"
    else
      echo "INFO  z3 CLI: 未導入 (Python binding があれば必須ではない)"
    fi
  fi

  if [ "$lane" = "tla" ] || [ "$lane" = "both" ]; then
    if command -v java >/dev/null 2>&1; then
      echo "OK    java: $(java -version 2>&1 | head -1)"
    else
      echo "MISS  java: TLC の実行に必要です"
      missing=1
    fi
    if [ -f "$jar_path" ]; then
      local locked_sha actual_sha
      locked_sha="$(read_lock_field tla2tools_sha256)"
      actual_sha="$(sha256_of "$jar_path")"
      if [ -n "$locked_sha" ] && [ "$locked_sha" != "unavailable" ] && [ "$locked_sha" != "$actual_sha" ]; then
        echo "WARN  tla2tools.jar: sha256 が lock と不一致 (差し替わった可能性)"
      else
        echo "OK    tla2tools.jar: $(read_lock_field tla2tools_version) ($jar_path)"
      fi
    else
      echo "MISS  tla2tools.jar: $jar_path が無い → $0 --dir $target_dir --install --lane tla"
      missing=1
    fi
  fi

  if [ "$missing" -eq 0 ]; then
    echo "-> 要求レーンは揃っています"
  else
    echo "-> 不足があります"
  fi
  return "$missing"
}

case "$action" in
  init) do_init ;;
  install) do_install ;;
  check) do_check ;;
esac
