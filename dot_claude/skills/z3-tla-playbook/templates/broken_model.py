#!/usr/bin/env python3
"""broken variant の雛形 — 「検査が実際に効いている」ことを証明するための対照。

model.py から **ガードを 1 つ外しただけ** の版。run-checks.sh はこれが赤 (exit != 0)
になることを要求する。緑のまま通るなら、その検査は何も守っていない。

対応表: models/example_cap.py の MIN_AGE ガードを predict から取り除いた版。
"""

from __future__ import annotations

import sys

try:
    from z3 import And, Int, Not, Or, Solver, sat, unsat
except ImportError:
    print("z3 が import できません。setup-env.sh --install を実行してください。", file=sys.stderr)
    raise SystemExit(2)


age = Int("age")
shown = Int("shown")

DOMAIN = [age >= 0, age <= 120, shown >= 0, shown <= 100]

MIN_AGE = 18
MAX_AGE = 65
CAP = 3


def predict(age_value, shown_value):
    # ↓ 意図的な欠陥: 下限年齢ガードを外している
    return And(age_value <= MAX_AGE, shown_value < CAP)


def refute(name: str, claim, expect: str) -> bool:
    solver = Solver()
    solver.add(*DOMAIN)
    solver.add(Not(claim))
    result = solver.check()
    actual = "REFUTED" if result == sat else "HOLDS"
    ok = actual == expect
    print(f"[{'ok' if ok else 'NG'}] {name}: expect={expect} actual={actual}")
    if result == sat:
        print(f"      反例: {solver.model()}")
    return ok


def reachable(name: str, condition, expect: str) -> bool:
    solver = Solver()
    solver.add(*DOMAIN)
    solver.add(condition)
    result = solver.check()
    actual = "DEAD" if result == unsat else "LIVE"
    ok = actual == expect
    print(f"[{'ok' if ok else 'NG'}] {name}: expect={expect} actual={actual}")
    return ok


def run() -> int:
    results = [
        refute("NeverServeMinor", Not(And(predict(age, shown), age < MIN_AGE)), "HOLDS"),
        refute("NeverOverCap", Not(And(predict(age, shown), shown >= CAP)), "HOLDS"),
        reachable("RuleIsLive", predict(age, shown), "LIVE"),
        reachable("ContradictorySegment", And(age < 18, age >= 18), "DEAD"),
        refute("ServesEveryAdult", Or(Not(age >= MIN_AGE), predict(age, shown)), "REFUTED"),
    ]
    failed = results.count(False)
    print(f"\n{len(results) - failed} ok, {failed} NG")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(run())
