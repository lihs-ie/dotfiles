#!/usr/bin/env python3
"""Codex PreToolUse(apply_patch) guard for idchain's G2 edit gate."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


PATCH_PATH_PATTERN = re.compile(
    r"^\*\*\* (?:Add File|Update File|Delete File|Move to): (.+)$", re.MULTILINE
)


def deny(reason: str) -> None:
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
        ensure_ascii=False,
    )
    sys.stdout.write("\n")


def find_repo_root(target: Path) -> Path | None:
    current = target if target.is_dir() else target.parent
    for candidate in (current, *current.parents):
        if (candidate / "idchain" / "idchain.json").is_file():
            return candidate
    return None


def array_of_strings(config: dict[str, Any], key: str) -> tuple[str, ...]:
    value = config.get(key, [])
    if not isinstance(value, list):
        return ()
    return tuple(item.rstrip("/") for item in value if isinstance(item, str) and item.rstrip("/"))


def is_under(relative_path: str, prefix: str) -> bool:
    return relative_path == prefix or relative_path.startswith(prefix + "/")


def protected_reason(target: Path) -> str | None:
    root = find_repo_root(target)
    if root is None:
        return None

    try:
        relative_path = target.relative_to(root).as_posix()
    except ValueError:
        return None

    if is_under(relative_path, "idchain"):
        return None

    config_path = root / "idchain" / "idchain.json"
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return f"idchain: {config_path} を解析できないため実装ファイルを編集できません"

    if not isinstance(config, dict):
        return f"idchain: {config_path} が JSON object ではありません"

    allowed_prefixes = array_of_strings(config, "testFileRoots") + array_of_strings(
        config, "editAllowlist"
    )
    if any(is_under(relative_path, prefix) for prefix in allowed_prefixes):
        return None

    gate_status_path = root / "idchain" / ".gate-status.json"
    try:
        gate_status = json.loads(gate_status_path.read_text(encoding="utf-8"))
        approved = gate_status["approvedFreshSpecs"]
        unapproved = gate_status["unapprovedSpecs"]
        if not isinstance(approved, int) or isinstance(approved, bool):
            raise ValueError("approvedFreshSpecs is not an integer")
        if not isinstance(unapproved, int) or isinstance(unapproved, bool):
            raise ValueError("unapprovedSpecs is not an integer")
    except (OSError, json.JSONDecodeError, KeyError, ValueError, TypeError):
        return (
            "idchain: ゲート状態が未生成または不正です。先に "
            "(cd idchain && lake exe idchain check) を実行してください"
        )

    if approved == 0 and unapproved >= 1:
        return (
            "idchain: 未承認 SP のみの状態で実装ファイルは編集できません "
            "(G2 承認 → lake exe idchain check 後に再試行)"
        )

    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError):
        return 0

    if not isinstance(payload, dict) or payload.get("tool_name") != "apply_patch":
        return 0

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return 0
    patch = tool_input.get("command")
    if not isinstance(patch, str):
        return 0

    cwd_value = payload.get("cwd")
    cwd = Path(cwd_value) if isinstance(cwd_value, str) else Path.cwd()

    reasons: list[str] = []
    for raw_path in PATCH_PATH_PATTERN.findall(patch):
        candidate = Path(raw_path.strip())
        target = (candidate if candidate.is_absolute() else cwd / candidate).resolve(strict=False)
        reason = protected_reason(target)
        if reason is not None and reason not in reasons:
            reasons.append(reason)

    if reasons:
        deny("\n".join(reasons))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
