#!/usr/bin/env python3
"""run-checks.sh の契約検証用 fixture (正例)。

ハーネスが見るのは exit code だけなので、fixture は z3 に依存させない
(CI/他マシンでも同じ結果になるようにするため)。
"""
CAP = 3


def predict(shown: int) -> bool:
    return shown < CAP


def main() -> int:
    holds = all(predict(n) for n in range(CAP)) and not predict(CAP)
    print(f"[{'ok' if holds else 'NG'}] NeverOverCap")
    return 0 if holds else 1


if __name__ == "__main__":
    raise SystemExit(main())
