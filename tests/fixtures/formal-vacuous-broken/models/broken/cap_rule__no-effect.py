#!/usr/bin/env python3
"""壊したつもりで壊れていない対照。緑で通るので run-checks.sh は失格にしなければならない。"""


def main() -> int:
    print("[ok] NeverOverCap (壊れていない)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
