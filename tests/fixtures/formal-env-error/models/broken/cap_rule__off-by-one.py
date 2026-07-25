#!/usr/bin/env python3
"""正しく検出する対照 (exit 1)。基準モデル側の分類だけを切り分けるために置く。"""


def main() -> int:
    print("[NG] NeverOverCap")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
