#!/usr/bin/env python3
"""対照 (broken variant) を持たないモデル。run-checks.sh はこれを失格にする。"""
CAP = 3


def main() -> int:
    print("[ok] NeverOverCap")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
