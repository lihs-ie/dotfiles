#!/usr/bin/env python3
"""Z3 モデルの雛形 — 「全入力に対して、ある一瞬」の主張を反例探索で検証する。

書き方の原則:
  1. 実装の配管 (I/O, DB, framework) を剥がし、観測可能な入力 → 結果 の純粋関数として書く
  2. 証明したい性質に **名前を付ける** (レビューで「この性質は満たす?」と会話できる)
  3. 個々の主張を HOLDS / REFUTED / ERROR に分類する

プロセス exit は主張の分類とは別の self-check 契約:
  0 = 全主張が宣言した期待結果と一致、1 = 期待結果と不一致、2 = solver unknown / 実行 ERROR。
期待が REFUTED の主張で反例が見つかった場合も self-check 成功なので exit 0 になる。

この雛形は「年齢帯 + 表示回数上限で配信可否を決める」ルールを例にしている。
自分の対象に置き換えるときは DOMAIN / predict / CLAIMS の 3 箇所だけ書き換える。
"""

from __future__ import annotations

import sys

try:
    from z3 import And, Int, Not, Or, Solver, sat, unknown, unsat
except ImportError:  # 環境未整備は「検査の失敗」と区別できるよう exit 2 にする
    print("z3 が import できません。setup-env.sh --install を実行してください。", file=sys.stderr)
    raise SystemExit(2)


# ── 1. 対象の定義域 (observable inputs) ──────────────────────────────
age = Int("age")
shown = Int("shown")  # これまでの表示回数

DOMAIN = [age >= 0, age <= 120, shown >= 0, shown <= 100]

MIN_AGE = 18
MAX_AGE = 65
CAP = 3


# ── 2. 決定関数 predict — 実装が事実上決めている仕様 ────────────────
def predict(age_value, shown_value):
    """配信するか。実装から配管を剥がして書き写した純粋述語。"""
    return And(age_value >= MIN_AGE, age_value <= MAX_AGE, shown_value < CAP)


# ── 3. 検証ヘルパ ────────────────────────────────────────────────────
def refute(name: str, claim, expect: str) -> bool:
    """claim が定義域の全入力で成り立つかを、否定の充足可能性で調べる。

    expect="HOLDS"   … 契約 (regression guard)。破れたら赤。
    expect="REFUTED" … 既知の反例。塞いだつもりで塞げていないと赤。
    """
    solver = Solver()
    solver.add(*DOMAIN)
    solver.add(Not(claim))
    result = solver.check()
    if result == sat:
        actual = "REFUTED"
    elif result == unsat:
        actual = "HOLDS"
    elif result == unknown:
        print(f"[ERROR] {name}: solver returned unknown: {solver.reason_unknown()}", file=sys.stderr)
        raise SolverUnknown
    else:
        print(f"[ERROR] {name}: unexpected solver result: {result}", file=sys.stderr)
        raise SolverUnknown
    ok = actual == expect
    print(f"[{'ok' if ok else 'NG'}] {name}: expect={expect} actual={actual}")
    if result == sat:
        print(f"      反例: {solver.model()}")
    return ok


def reachable(name: str, condition, expect: str) -> bool:
    """condition を満たす入力が存在するか。存在しなければ dead config (矛盾設定)。

    expect="LIVE" … 到達し得る / expect="DEAD" … どんな入力でも通らない
    """
    solver = Solver()
    solver.add(*DOMAIN)
    solver.add(condition)
    result = solver.check()
    if result == sat:
        actual = "LIVE"
    elif result == unsat:
        actual = "DEAD"
    elif result == unknown:
        print(f"[ERROR] {name}: solver returned unknown: {solver.reason_unknown()}", file=sys.stderr)
        raise SolverUnknown
    else:
        print(f"[ERROR] {name}: unexpected solver result: {result}", file=sys.stderr)
        raise SolverUnknown
    ok = actual == expect
    print(f"[{'ok' if ok else 'NG'}] {name}: expect={expect} actual={actual}")
    if result == sat:
        print(f"      witness: {solver.model()}")
    return ok


# ── 4. 名前付きの主張 (契約と既知の穴を並べる) ──────────────────────
class SolverUnknown(Exception):
    """Z3 が sat/unsat を確定できず、主張を ERROR と分類した。"""


def run() -> int:
    results = [
        # 契約: 未成年には配信しない
        refute("NeverServeMinor", Not(And(predict(age, shown), age < MIN_AGE)), "HOLDS"),
        # 契約: 上限に達したら配信しない (境界は cap 未満 = cap 回目で止まる)
        refute("NeverOverCap", Not(And(predict(age, shown), shown >= CAP)), "HOLDS"),
        # 到達性: このルールは誰かに配信され得る (dead config でない)
        reachable("RuleIsLive", predict(age, shown), "LIVE"),
        # 矛盾設定の例: 「18 歳未満のみ」かつ「18 歳以上」は誰にも当たらない
        reachable("ContradictorySegment", And(age < 18, age >= 18), "DEAD"),
        # 既知の穴: 65 歳超は配信対象外 — 意図か? (反例をドメインに問う材料)
        refute("ServesEveryAdult", Or(Not(age >= MIN_AGE), predict(age, shown)), "REFUTED"),
    ]
    failed = results.count(False)
    print(f"\n{len(results) - failed} ok, {failed} NG")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(run())
    except SolverUnknown:
        raise SystemExit(2)
