#!/usr/bin/env python3
"""Validate support-triage adapter JSON.

The validator is intentionally dependency-free so it can run in any project
during onboarding or fire drills.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


REQUIRED_FIELDS = {
    "adapter_version",
    "surface",
    "provider",
    "id",
    "subject",
    "status",
    "priority",
    "created_at",
    "updated_at",
    "customer",
    "sla",
    "messages",
    "safe_actions",
    "unsafe_actions",
    "evidence",
}

FORBIDDEN_V1_FIELDS = {
    "refund_preview",
    "refund_authority",
    "full_customer_health_score",
    "raw_api_token",
    "api_token",
    "secret",
}

DANGEROUS_SAFE_ACTION_PREFIXES = (
    "send_",
    "issue_refund",
    "issue_credit",
    "plan_upgrade",
    "account_lock",
    "ban_",
    "delete_",
    "erase_",
    "privacy_request",
    "public_",
    "publish_",
    "cancel_",
)


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"{path}: invalid JSON at line {exc.lineno}: {exc.msg}") from exc


def parse_timestamp(value: Any, label: str) -> None:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{label} must be a non-empty ISO-8601 string")
    normalized = value.replace("Z", "+00:00")
    try:
        datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise ValueError(f"{label} is not ISO-8601: {value!r}") from exc


def require_object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    return value


def require_list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValueError(f"{label} must be a list")
    return value


def validate_item(item: Any, index: int) -> list[str]:
    if not isinstance(item, dict):
        raise ValueError(f"item[{index}] must be an object")

    prefix = f"item[{index}]"
    missing = sorted(REQUIRED_FIELDS - set(item))
    if missing:
        raise ValueError(f"{prefix} missing required fields: {', '.join(missing)}")

    forbidden = sorted(FORBIDDEN_V1_FIELDS & set(item))
    if forbidden:
        raise ValueError(f"{prefix} contains forbidden v1 fields: {', '.join(forbidden)}")

    if item["adapter_version"] != "support-adapter-v1":
        raise ValueError(f"{prefix}.adapter_version must be support-adapter-v1")

    for field in ("surface", "provider", "id", "subject", "status", "priority"):
        if not isinstance(item[field], str):
            raise ValueError(f"{prefix}.{field} must be a string")

    parse_timestamp(item["created_at"], f"{prefix}.created_at")
    parse_timestamp(item["updated_at"], f"{prefix}.updated_at")

    require_object(item["customer"], f"{prefix}.customer")
    require_object(item["sla"], f"{prefix}.sla")
    require_list(item["messages"], f"{prefix}.messages")

    safe_actions = require_list(item["safe_actions"], f"{prefix}.safe_actions")
    unsafe_actions = require_list(item["unsafe_actions"], f"{prefix}.unsafe_actions")
    for action_label, actions in (("safe_actions", safe_actions), ("unsafe_actions", unsafe_actions)):
        for action in actions:
            if not isinstance(action, str):
                raise ValueError(f"{prefix}.{action_label} entries must be strings")

    overlap = sorted(set(safe_actions) & set(unsafe_actions))
    if overlap:
        raise ValueError(f"{prefix} action listed as both safe and unsafe: {', '.join(overlap)}")

    mislabeled_safe = sorted(
        action
        for action in safe_actions
        if any(action.startswith(prefix_) for prefix_ in DANGEROUS_SAFE_ACTION_PREFIXES)
    )
    if mislabeled_safe:
        raise ValueError(
            f"{prefix} dangerous action listed as safe: {', '.join(mislabeled_safe)}"
        )

    evidence = require_list(item["evidence"], f"{prefix}.evidence")
    if not evidence:
        raise ValueError(f"{prefix}.evidence must contain at least one source")

    warnings: list[str] = []
    if item["status"] == "adapter_error":
        error = require_object(item.get("error"), f"{prefix}.error")
        if not isinstance(error.get("kind"), str) or not error["kind"]:
            raise ValueError(f"{prefix}.error.kind must describe the adapter failure")
        warnings.append(f"{prefix}: adapter_error reported ({error['kind']})")

    if item.get("stable_url") is None and item["status"] != "adapter_error":
        warnings.append(f"{prefix}: stable_url is null for a normal item")

    return warnings


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: validate-adapter-output.py <open-items.json>", file=sys.stderr)
        return 2

    path = Path(argv[1])
    if not path.exists():
        print(f"{path}: not found", file=sys.stderr)
        return 2

    try:
        payload = load_json(path)
        if not isinstance(payload, list):
            raise ValueError("root JSON must be an array")
        warnings: list[str] = []
        for index, item in enumerate(payload):
            warnings.extend(validate_item(item, index))
    except ValueError as exc:
        print(f"adapter validation failed: {exc}", file=sys.stderr)
        return 1

    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    print(f"adapter validation passed: {len(payload)} item(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
