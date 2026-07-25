#!/usr/bin/env python3
"""依存不足で落ちる対照 (exit 2)。

「非 0 なら捕まえた」と数えると、venv 破損や import 失敗が
「壊れた実装を検出できた」に化ける。run-checks.sh はこれを失格にしなければならない。
"""
import sys

print("z3 が import できません (依存不足のシミュレーション)", file=sys.stderr)
raise SystemExit(2)
