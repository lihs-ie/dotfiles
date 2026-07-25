#!/usr/bin/env python3
"""対照が「検出」ではなく「異常終了」するケースの基準モデル (正常に成立する)。"""


def main() -> int:
    print("[ok] NeverOverCap")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
