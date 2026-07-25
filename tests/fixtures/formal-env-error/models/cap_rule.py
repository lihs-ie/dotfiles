#!/usr/bin/env python3
"""基準モデル自体が実行エラーで落ちるケース (exit 2)。

「主張が破れた (exit 1)」とは別のメッセージで報告されなければ、
環境不備を検査失敗と読み違えて原因調査が遠回りになる。
"""
import sys

print("z3 が import できません (依存不足のシミュレーション)", file=sys.stderr)
raise SystemExit(2)
