#!/usr/bin/env python3
"""正例モデルの境界を 1 ずらした対照。run-checks.sh はこれが赤になることを要求する。"""
CAP = 3


def predict(shown: int) -> bool:
    return shown <= CAP  # 意図的な欠陥: 境界が 1 ずれている


def main() -> int:
    holds = all(predict(n) for n in range(CAP)) and not predict(CAP)
    print(f"[{'ok' if holds else 'NG'}] NeverOverCap")
    return 0 if holds else 1


if __name__ == "__main__":
    raise SystemExit(main())
