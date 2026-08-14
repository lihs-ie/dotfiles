#!/usr/bin/env python3
"""Validate Apple UI/UX contracts and bind explicit design approval to digests."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import UTC, date, datetime
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError as exc:  # pragma: no cover - environment failure path
    raise SystemExit(f"approval_gate.py requires PyYAML: {exc}") from exc


PLUGIN_ROOT = Path(__file__).resolve().parent.parent
SPEC_RELATIVE = Path("design/apple-ui-ux/apple-ui-ux-spec.yaml")
APPROVAL_RELATIVE = Path("design/apple-ui-ux/approval.yaml")
EXPECTED_RULES = {
    "NAV-001", "NAV-002", "NAV-003", "BRG-001", "TYP-001", "TYP-002",
    "SPC-001", "CLR-001", "HIT-001", "ACC-001", "ACC-002",
    "GST-001", "MOT-001", "GLS-001", "SPL-001", "WIN-001",
    "PTR-001", "KEY-001", "PCL-001", "PRV-001", "DST-001",
}


class ContractError(RuntimeError):
    pass


def load_yaml(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise ContractError(f"missing file: {path}")
    loaded = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(loaded, dict):
        raise ContractError(f"expected YAML object: {path}")
    return loaded


def load_json(path: Path) -> dict[str, Any]:
    loaded = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(loaded, dict):
        raise ContractError(f"expected JSON object: {path}")
    return loaded


def validate_document(document: dict[str, Any], schema_name: str, source: Path) -> None:
    schema = load_json(PLUGIN_ROOT / "schemas" / schema_name)
    errors: list[str] = []
    validate_value(document, schema, "<root>", errors)
    if errors:
        raise ContractError("\n".join(f"{source}: {error}" for error in errors))


def validate_value(value: Any, schema: dict[str, Any], location: str, errors: list[str]) -> None:
    """Validate the JSON Schema subset used by this plugin without external packages."""
    declared_types = schema.get("type")
    if declared_types is not None:
        choices = declared_types if isinstance(declared_types, list) else [declared_types]
        predicates = {
            "object": lambda item: isinstance(item, dict),
            "array": lambda item: isinstance(item, list),
            "string": lambda item: isinstance(item, str),
            "integer": lambda item: isinstance(item, int) and not isinstance(item, bool),
            "number": lambda item: isinstance(item, (int, float)) and not isinstance(item, bool),
            "boolean": lambda item: isinstance(item, bool),
            "null": lambda item: item is None,
        }
        if not any(predicates[kind](value) for kind in choices):
            errors.append(f"{location}: expected type {choices}, got {type(value).__name__}")
            return

    if "const" in schema and value != schema["const"]:
        errors.append(f"{location}: expected constant {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{location}: value {value!r} is not in {schema['enum']!r}")

    if isinstance(value, dict):
        required = schema.get("required", [])
        for key in required:
            if key not in value:
                errors.append(f"{location}: missing required property {key!r}")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            for key in value:
                if key not in properties:
                    errors.append(f"{location}: unexpected property {key!r}")
        for key, child in value.items():
            if key in properties:
                validate_value(child, properties[key], f"{location}.{key}", errors)

    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            errors.append(f"{location}: expected at least {schema['minItems']} items")
        if schema.get("uniqueItems"):
            serialized = [json.dumps(item, sort_keys=True, ensure_ascii=False) for item in value]
            if len(serialized) != len(set(serialized)):
                errors.append(f"{location}: items must be unique")
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, child in enumerate(value):
                validate_value(child, item_schema, f"{location}[{index}]", errors)

    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            errors.append(f"{location}: string is shorter than {schema['minLength']}")
        pattern = schema.get("pattern")
        if pattern and re.search(pattern, value) is None:
            errors.append(f"{location}: value does not match {pattern!r}")
        if schema.get("format") == "date":
            try:
                date.fromisoformat(value)
            except ValueError:
                errors.append(f"{location}: invalid ISO date")
        if schema.get("format") == "date-time":
            try:
                datetime.fromisoformat(value.replace("Z", "+00:00"))
            except ValueError:
                errors.append(f"{location}: invalid ISO date-time")

    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{location}: value is below minimum {schema['minimum']}")


def ensure_unique(items: list[dict[str, Any]], label: str) -> set[str]:
    identifiers = [str(item.get("identifier", "")) for item in items]
    duplicates = sorted({item for item in identifiers if identifiers.count(item) > 1})
    if duplicates:
        raise ContractError(f"duplicate {label} identifiers: {', '.join(duplicates)}")
    return set(identifiers)


def validate_foundation() -> None:
    evidence_path = PLUGIN_ROOT / "evidence" / "registry.yaml"
    evidence_doc = load_yaml(evidence_path)
    validate_document(evidence_doc, "evidence-registry.schema.json", evidence_path)
    evidence_items = evidence_doc["evidence"]
    evidence_identifiers = ensure_unique(evidence_items, "evidence")
    evidence_levels = {item["identifier"]: item["level"] for item in evidence_items}

    profile_identifiers: set[str] = set()
    for profile_path in sorted((PLUGIN_ROOT / "profiles").glob("*.yaml")):
        profile = load_yaml(profile_path)
        validate_document(profile, "profile.schema.json", profile_path)
        identifier = profile["identifier"]
        if identifier in profile_identifiers:
            raise ContractError(f"duplicate profile identifier: {identifier}")
        profile_identifiers.add(identifier)

    rule_path = PLUGIN_ROOT / "rules" / "rules.yaml"
    rule_doc = load_yaml(rule_path)
    validate_document(rule_doc, "rule-catalog.schema.json", rule_path)
    rules = rule_doc["rules"]
    rule_identifiers = ensure_unique(rules, "rule")
    if rule_identifiers != EXPECTED_RULES:
        missing = sorted(EXPECTED_RULES - rule_identifiers)
        extra = sorted(rule_identifiers - EXPECTED_RULES)
        raise ContractError(f"rule catalog mismatch; missing={missing}, extra={extra}")

    for rule in rules:
        unknown_evidence = sorted(set(rule["evidence"]) - evidence_identifiers)
        if unknown_evidence:
            raise ContractError(f"{rule['identifier']}: unknown evidence {unknown_evidence}")
        unknown_profiles = sorted(set(rule.get("profiles", [])) - profile_identifiers)
        if unknown_profiles:
            raise ContractError(f"{rule['identifier']}: unknown profiles {unknown_profiles}")
        if rule["enforcement"] == "hard":
            levels = {evidence_levels[item] for item in rule["evidence"]}
            if not levels.intersection({"L1", "L2"}):
                raise ContractError(f"{rule['identifier']}: hard rule lacks L1/L2 evidence")

    print(json.dumps({
        "result": "pass",
        "profiles": sorted(profile_identifiers),
        "rules": len(rule_identifiers),
        "evidence": len(evidence_identifiers),
    }, ensure_ascii=False))


def project_file(project_root: Path, relative: Path) -> Path:
    root = project_root.resolve()
    candidate = (root / relative).resolve()
    if candidate != root and root not in candidate.parents:
        raise ContractError(f"path escapes project root: {relative}")
    return candidate


def validate_spec(project_root: Path, *, require_review_ready: bool = False) -> dict[str, Any]:
    spec_path = project_file(project_root, SPEC_RELATIVE)
    spec = load_yaml(spec_path)
    validate_document(spec, "apple-ui-ux-spec.schema.json", spec_path)

    if require_review_ready and spec["design_status"] != "review_ready":
        raise ContractError("design_status must be review_ready before approval")
    if require_review_ready and not spec.get("selected_direction"):
        raise ContractError("selected_direction is required before approval")
    if "mixed" in spec["frameworks"] and len(spec["frameworks"]) != 1:
        raise ContractError("frameworks must use mixed alone or list concrete frameworks without mixed")

    for screen in spec["screens"]:
        required_states = {"populated", "empty", "loading", "error"}
        missing_states = sorted(required_states - set(screen["states"]))
        if missing_states:
            raise ContractError(f"{screen['identifier']}: missing review states {missing_states}")
        if set(screen["devices"]) != {"iphone", "ipad"}:
            raise ContractError(f"{screen['identifier']}: both iphone and ipad review artifacts are required")
        if set(screen["appearances"]) != {"light", "dark"}:
            raise ContractError(f"{screen['identifier']}: both light and dark review artifacts are required")
        dynamic_type = set(screen["dynamic_type"])
        if "all-12" not in dynamic_type and not {"standard", "accessibility-maximum"}.issubset(dynamic_type):
            raise ContractError(f"{screen['identifier']}: standard and accessibility-maximum Dynamic Type are required")

    if not any(profile.startswith("ios") for profile in spec["profiles"]):
        raise ContractError("an iOS profile is required")
    if not any(profile.startswith("ipados") for profile in spec["profiles"]):
        raise ContractError("an iPadOS profile is required")

    for change in spec["behavior_changes"]:
        if require_review_ready and change["approval"] == "pending":
            raise ContractError(f"pending behavior change blocks approval: {change['description']}")

    today = date.today()
    for exception in spec.get("exceptions", []):
        expiry = date.fromisoformat(exception["expires_at"])
        if expiry < today:
            raise ContractError(f"expired exception for {exception['rule']}: {expiry.isoformat()}")

    for artifact in spec["artifacts"]:
        artifact_path = project_file(project_root, Path(artifact["path"]))
        if not artifact_path.exists():
            raise ContractError(f"missing design artifact: {artifact['path']}")

    return spec


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def sha256_path(path: Path) -> str:
    if path.is_symlink():
        raise ContractError(f"approval artifacts must not be symlinks: {path}")
    if path.is_file():
        return sha256_file(path)
    if not path.is_dir():
        raise ContractError(f"unsupported artifact: {path}")
    digest = hashlib.sha256()
    files = sorted(item for item in path.rglob("*") if item.is_file())
    if not files:
        raise ContractError(f"artifact directory is empty: {path}")
    for item in files:
        if item.is_symlink():
            raise ContractError(f"approval artifacts must not contain symlinks: {item}")
        digest.update(item.relative_to(path).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(sha256_file(item).encode("ascii"))
        digest.update(b"\0")
    return f"sha256:{digest.hexdigest()}"


def approve(project_root: Path, approved_by: str, confirmation: str) -> None:
    if confirmation != "APPROVE":
        raise ContractError("approval requires --confirm APPROVE")
    spec = validate_spec(project_root, require_review_ready=True)
    spec_path = project_file(project_root, SPEC_RELATIVE)
    approved_at = datetime.now(UTC).replace(microsecond=0)
    artifacts = []
    for artifact in spec["artifacts"]:
        relative = Path(artifact["path"])
        artifacts.append({
            "path": relative.as_posix(),
            "sha256": sha256_path(project_file(project_root, relative)),
        })
    approval = {
        "schema_version": "1.0",
        "identifier": f"{spec['identifier']}-approval-{approved_at.strftime('%Y%m%d%H%M%S')}",
        "status": "approved",
        "project": spec["identifier"],
        "approved_by": approved_by,
        "approved_at": approved_at.isoformat().replace("+00:00", "Z"),
        "design_backend": spec["design_backend"],
        "profiles": spec["profiles"],
        "spec_digest": sha256_file(spec_path),
        "artifacts": artifacts,
        "invalidation": "any_digest_change",
    }
    approval_path = project_file(project_root, APPROVAL_RELATIVE)
    validate_document(approval, "approval.schema.json", approval_path)
    approval_path.parent.mkdir(parents=True, exist_ok=True)
    approval_path.write_text(yaml.safe_dump(approval, sort_keys=False, allow_unicode=True), encoding="utf-8")
    print(json.dumps({"result": "approved", "approval": str(approval_path)}, ensure_ascii=False))


def check_approval(project_root: Path) -> None:
    spec = validate_spec(project_root, require_review_ready=True)
    approval_path = project_file(project_root, APPROVAL_RELATIVE)
    approval = load_yaml(approval_path)
    validate_document(approval, "approval.schema.json", approval_path)
    if approval["project"] != spec["identifier"]:
        raise ContractError("approval project does not match the specification")
    if approval["design_backend"] != spec["design_backend"]:
        raise ContractError("approval design backend does not match the specification")
    if approval["profiles"] != spec["profiles"]:
        raise ContractError("approval profiles do not match the specification")
    spec_digest = sha256_file(project_file(project_root, SPEC_RELATIVE))
    if approval["spec_digest"] != spec_digest:
        raise ContractError("specification digest changed after approval")
    expected = {item["path"]: item["sha256"] for item in approval["artifacts"]}
    actual_paths = {item["path"] for item in spec["artifacts"]}
    if set(expected) != actual_paths:
        raise ContractError("approved artifact set does not match the specification")
    for relative, expected_digest in expected.items():
        actual_digest = sha256_path(project_file(project_root, Path(relative)))
        if actual_digest != expected_digest:
            raise ContractError(f"artifact digest changed after approval: {relative}")
    print(json.dumps({"result": "pass", "approval": str(approval_path)}, ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    subcommands = root.add_subparsers(dest="command", required=True)
    subcommands.add_parser("validate-foundation")
    validate = subcommands.add_parser("validate-spec")
    validate.add_argument("--project-root", required=True, type=Path)
    approve_parser = subcommands.add_parser("approve")
    approve_parser.add_argument("--project-root", required=True, type=Path)
    approve_parser.add_argument("--approved-by", required=True)
    approve_parser.add_argument("--confirm", required=True)
    check = subcommands.add_parser("check-approval")
    check.add_argument("--project-root", required=True, type=Path)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "validate-foundation":
            validate_foundation()
        elif args.command == "validate-spec":
            spec = validate_spec(args.project_root)
            print(json.dumps({"result": "pass", "specification": spec["identifier"]}, ensure_ascii=False))
        elif args.command == "approve":
            approve(args.project_root, args.approved_by, args.confirm)
        elif args.command == "check-approval":
            check_approval(args.project_root)
        else:  # pragma: no cover
            raise ContractError(f"unsupported command: {args.command}")
    except (ContractError, ValueError, OSError, json.JSONDecodeError, yaml.YAMLError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
