#!/usr/bin/env bash
# z3-tla-playbook: 検証モデルを回し、「検査が実際に効いている」ことまで確認するハーネス。
#
# playbook §5 の実装。単にモデルを回すだけでは「常に緑 = 何も検証していない」に陥るため、
# 次の 3 つを同時に強制する:
#   1. self-check   — 各モデルは自分の期待判定を assert し、exit code で結果を返す
#   2. broken-variant — わざと壊した変種が **赤で捕まる** ことを確認する (load-bearing の証明)
#   3. 空でないこと  — モデルが 0 個の「空っぽの緑」を失格にする
#
# モデルの exit code 契約 (これを守らないと「クラッシュ = 検出」と誤読される):
#   0        主張どおり (検査成立)
#   1        主張が破れた (反例あり = 検査が働いた)
#   2 以上   実行エラー (依存不足・モデル自体の不備・クラッシュ)。**検査結果ではない**
# broken variant は exit 1 でのみ「捕まった」と認める。exit 2+ は異常終了として失格にする
# (venv 破損や import 失敗を「壊れた実装を検出できた」と数えないため)。
#
# 期待レイアウト (setup-env.sh --init が生成):
#   <dir>/models/*.py                     Z3 モデル。exit 0 = 主張どおり
#   <dir>/models/broken/<stem>__*.py      同モデルの壊した変種。exit != 0 が期待
#   <dir>/specs/*.tla + *.cfg + *.expect  TLA+ 仕様。expect は OK / VIOLATE
#   <dir>/specs/broken/<stem>__*.tla      壊した変種 (+ .cfg, .expect=VIOLATE)
#
# exit code: 0 = 全て期待どおり / 1 = 期待と食い違いあり / 2 = 引数・環境エラー
set -euo pipefail

target_dir=".formal"
only="both"
allow_missing_broken=0
allow_empty=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) target_dir="${2:?--dir needs a value}"; shift 2 ;;
    --only) only="${2:?--only needs a value}"; shift 2 ;;
    --allow-missing-broken) allow_missing_broken=1; shift ;;
    --allow-empty) allow_empty=1; shift ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$only" in
  z3|tla|both) ;;
  *) echo "--only must be one of: z3 tla both" >&2; exit 2 ;;
esac

[ -d "$target_dir" ] || { echo "no such directory: $target_dir (setup-env.sh --init を先に)" >&2; exit 2; }

models_dir="$target_dir/models"
specs_dir="$target_dir/specs"
jar_path="$target_dir/tools/tla2tools.jar"

python_bin="python3"
[ -x "$target_dir/.venv/bin/python" ] && python_bin="$target_dir/.venv/bin/python"

pass_count=0
fail_count=0
checked_units=0

report() {
  # $1 = PASSED/FAILED, $2 = 説明
  if [ "$1" = "PASSED" ]; then
    echo "PASSED: $2"
    pass_count=$((pass_count + 1))
  else
    echo "FAILED: $2"
    fail_count=$((fail_count + 1))
  fi
}

# ---------- Z3 レーン ----------
run_z3_lane() {
  [ -d "$models_dir" ] || return 0
  local model stem variants variant actual
  while IFS= read -r model; do
    [ -z "$model" ] && continue
    checked_units=$((checked_units + 1))
    stem="$(basename "$model" .py)"

    actual=0
    "$python_bin" "$model" >/dev/null 2>&1 || actual=$?
    if [ "$actual" -eq 0 ]; then
      report PASSED "z3 model $stem (self-check)"
    elif [ "$actual" -eq 1 ]; then
      report FAILED "z3 model $stem (self-check: 主張が破れた)"
      echo "  --- 出力 ---"
      "$python_bin" "$model" 2>&1 | sed 's/^/  /' || true
    else
      report FAILED "z3 model $stem (実行エラー exit $actual — 検査結果ではない。依存不足かモデル自体の不備)"
      echo "  --- 出力 ---"
      "$python_bin" "$model" 2>&1 | sed 's/^/  /' || true
    fi

    variants="$(find "$models_dir/broken" -maxdepth 1 -name "${stem}__*.py" 2>/dev/null | sort || true)"
    if [ -z "$variants" ]; then
      if [ "$allow_missing_broken" -eq 1 ]; then
        echo "SKIPPED: z3 model $stem に broken variant なし (--allow-missing-broken)"
      else
        report FAILED "z3 model $stem に broken variant が無い (検査が効いている証明が無い)"
      fi
    else
      while IFS= read -r variant; do
        [ -z "$variant" ] && continue
        actual=0
        "$python_bin" "$variant" >/dev/null 2>&1 || actual=$?
        if [ "$actual" -eq 1 ]; then
          report PASSED "broken variant $(basename "$variant") が赤で捕まった (exit 1)"
        elif [ "$actual" -eq 0 ]; then
          report FAILED "broken variant $(basename "$variant") が緑のまま通った (検査が効いていない)"
        else
          report FAILED "broken variant $(basename "$variant") が exit $actual で異常終了 (クラッシュ/依存不足であって検出ではない)"
          echo "  --- 出力 ---"
          "$python_bin" "$variant" 2>&1 | sed 's/^/  /' | tail -10 || true
        fi
      done <<< "$variants"
    fi
  done <<< "$(find "$models_dir" -maxdepth 1 -name '*.py' 2>/dev/null | sort || true)"
}

# ---------- TLA+ レーン ----------
# TLC の結果を OK / VIOLATE / ERROR の 3 値に分類する。
# 非 0 exit を一律 VIOLATE にすると parse error を「反例が出た」と誤読するため分ける。
classify_tlc() {
  local tla="$1" cfg="$2" out_file="$3"
  local dir base exit_code=0
  dir="$(dirname "$tla")"
  base="$(basename "$tla")"
  ( cd "$dir" && java -XX:+UseSerialGC -cp "$jar_abs" tlc2.TLC \
      -config "$(basename "$cfg")" -cleanup "$base" ) > "$out_file" 2>&1 || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    printf 'OK'
    return 0
  fi
  if grep -qE 'is violated|Temporal properties were violated|Deadlock reached|Assumption .* is false' "$out_file"; then
    printf 'VIOLATE'
  else
    printf 'ERROR'
  fi
}

run_tla_lane() {
  [ -d "$specs_dir" ] || return 0
  local specs
  specs="$(find "$specs_dir" -maxdepth 1 -name '*.tla' 2>/dev/null | sort || true)"
  [ -z "$specs" ] && return 0

  if [ ! -f "$jar_path" ]; then
    echo "SKIPPED: TLA+ 仕様があるが $jar_path が無い (setup-env.sh --install --lane tla)"
    if [ "$allow_missing_broken" -eq 0 ]; then
      report FAILED "TLA+ レーンが実行不能 (tla2tools.jar 不在)"
    fi
    return 0
  fi
  if ! command -v java >/dev/null 2>&1; then
    report FAILED "TLA+ レーンが実行不能 (java 不在)"
    return 0
  fi
  jar_abs="$(cd "$(dirname "$jar_path")" && pwd)/$(basename "$jar_path")"

  local tla stem cfg expect actual out_file variants variant
  out_file="$(mktemp)"
  trap 'rm -f "$out_file"' RETURN

  while IFS= read -r tla; do
    [ -z "$tla" ] && continue
    checked_units=$((checked_units + 1))
    stem="$(basename "$tla" .tla)"
    cfg="$specs_dir/$stem.cfg"
    if [ ! -f "$cfg" ]; then
      report FAILED "TLA+ spec $stem に $stem.cfg が無い"
      continue
    fi
    expect="OK"
    [ -f "$specs_dir/$stem.expect" ] && expect="$(tr -d '[:space:]' < "$specs_dir/$stem.expect")"

    actual="$(classify_tlc "$tla" "$cfg" "$out_file")"
    if [ "$actual" = "$expect" ]; then
      report PASSED "TLA+ spec $stem ($actual, 期待どおり)"
    else
      report FAILED "TLA+ spec $stem (期待 $expect / 実際 $actual)"
      sed 's/^/  /' "$out_file" | tail -30
    fi

    if [ "$expect" = "OK" ]; then
      variants="$(find "$specs_dir/broken" -maxdepth 1 -name "${stem}__*.tla" 2>/dev/null | sort || true)"
      if [ -z "$variants" ]; then
        if [ "$allow_missing_broken" -eq 1 ]; then
          echo "SKIPPED: TLA+ spec $stem に broken variant なし (--allow-missing-broken)"
        else
          report FAILED "TLA+ spec $stem に broken variant が無い (検査が効いている証明が無い)"
        fi
      else
        while IFS= read -r variant; do
          [ -z "$variant" ] && continue
          local v_stem v_cfg
          v_stem="$(basename "$variant" .tla)"
          v_cfg="$specs_dir/broken/$v_stem.cfg"
          [ -f "$v_cfg" ] || v_cfg="$cfg"
          actual="$(classify_tlc "$variant" "$v_cfg" "$out_file")"
          if [ "$actual" = "VIOLATE" ]; then
            report PASSED "broken variant $v_stem が反例で捕まった"
          else
            report FAILED "broken variant $v_stem が $actual (VIOLATE のはず — 検査が効いていない)"
          fi
        done <<< "$variants"
      fi
    fi
  done <<< "$specs"
}

echo "== run-checks (dir=$target_dir, only=$only) =="
if [ "$only" = "z3" ] || [ "$only" = "both" ]; then
  run_z3_lane
fi
if [ "$only" = "tla" ] || [ "$only" = "both" ]; then
  run_tla_lane
fi

if [ "$checked_units" -eq 0 ]; then
  if [ "$allow_empty" -eq 1 ]; then
    echo "検証対象なし (--allow-empty)"
    exit 0
  fi
  echo "FAILED: 検証対象が 0 件 (空っぽの緑は失格。models/ か specs/ にモデルを置くこと)" >&2
  exit 1
fi

echo ""
echo "Results: $pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ] || exit 1
exit 0
