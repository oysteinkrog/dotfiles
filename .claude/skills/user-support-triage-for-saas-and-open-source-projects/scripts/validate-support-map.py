#!/usr/bin/env python3
"""Validate a project's .claude/support-triage map.

The validator is intentionally dependency-free. It checks that onboarding
created the files future agents rely on, that high-risk runbooks exist, and
that known gaps are explicit instead of being hidden in prose.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


REQUIRED_FILES = [
    "README.md",
    "00-intake.md",
    "01-architecture.md",
    "02-channels.md",
    "03-decision-matrix.md",
    "05-policies.md",
    "06-recurring-issues.md",
    "07-secrets.md",
    "08-voice.md",
    "09-knowledge-base.md",
    "10-metrics.md",
    "12-gap-dispositions.md",
    "adapter-capabilities.json",
    "handoffs/support-handoff.json",
    "_detection.json",
]

REQUIRED_DIRS = [
    "04-templates",
    "11-runbooks",
    "artifacts",
    "artifacts/evidence",
    "artifacts/drafts",
    "artifacts/approvals",
    "artifacts/sends",
    "artifacts/verification",
    "artifacts/manifests",
    "handoffs",
    "outcomes",
    "scripts",
]

REQUIRED_RUNBOOKS = [
    "REFUND.md",
    "SECURITY-DISCLOSURE.md",
    "GDPR-DSAR.md",
    "HOSTILE-USER.md",
    "OUTAGE-COMMS.md",
]

ALLOWED_GAP_DISPOSITIONS = {
    "confirmed",
    "not-applicable",
    "manual-only",
    "blocked-by-access",
    "provider-gap",
    "policy-gap",
    "evidence-gap",
    "deferred",
    "unknown",
}

REQUIRED_HANDOFF_FIELDS = {
    "schema",
    "project",
    "generated_at",
    "owner_required",
    "customer_visible_sends_blocked_until_approved",
    "current_state",
    "next_owner",
    "artifacts",
    "gap_dispositions",
}


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"{path}: invalid JSON at line {exc.lineno}: {exc.msg}") from exc


def has_token(path: Path, token: str) -> bool:
    try:
        return token in path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return False


def validate_support_map(root: Path) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []

    if not root.exists():
        return [f"{root}: does not exist"], warnings
    if not root.is_dir():
        return [f"{root}: is not a directory"], warnings

    for rel in REQUIRED_FILES:
        path = root / rel
        if not path.is_file():
            errors.append(f"missing required file: {rel}")

    for rel in REQUIRED_DIRS:
        path = root / rel
        if not path.is_dir():
            errors.append(f"missing required directory: {rel}")

    for name in REQUIRED_RUNBOOKS:
        path = root / "11-runbooks" / name
        if not path.is_file():
            errors.append(f"missing high-risk runbook: 11-runbooks/{name}")

    list_open = root / "scripts" / "list-open.sh"
    if not list_open.is_file():
        errors.append("missing adapter dispatcher: scripts/list-open.sh")
    else:
        if not has_token(list_open, "support-adapter-v1"):
            warnings.append("scripts/list-open.sh does not mention support-adapter-v1")
        if not (list_open.stat().st_mode & 0o111):
            warnings.append("scripts/list-open.sh is not executable")

    post_reply = root / "scripts" / "post-reply.sh"
    if not post_reply.is_file():
        warnings.append("scripts/post-reply.sh missing; sends are manual-only until documented")
    else:
        post_reply_text = post_reply.read_text(encoding="utf-8", errors="replace").lower()
        if "approval" not in post_reply_text and "confirm" not in post_reply_text:
            warnings.append("scripts/post-reply.sh does not mention approval/confirmation")

    capabilities_path = root / "adapter-capabilities.json"
    if capabilities_path.is_file():
        try:
            capabilities = load_json(capabilities_path)
            if not isinstance(capabilities, dict):
                errors.append("adapter-capabilities.json root must be an object")
            elif capabilities.get("adapter_version") != "support-adapter-v1":
                errors.append("adapter-capabilities.json adapter_version must be support-adapter-v1")
        except ValueError as exc:
            errors.append(str(exc))

    detection_path = root / "_detection.json"
    if detection_path.is_file():
        try:
            detection = load_json(detection_path)
            if not isinstance(detection, dict):
                errors.append("_detection.json root must be an object")
        except ValueError as exc:
            errors.append(str(exc))

    handoff_path = root / "handoffs" / "support-handoff.json"
    if handoff_path.is_file():
        try:
            handoff = load_json(handoff_path)
            if not isinstance(handoff, dict):
                errors.append("handoffs/support-handoff.json root must be an object")
            elif handoff.get("schema") != "support-handoff-v1":
                errors.append("handoffs/support-handoff.json schema must be support-handoff-v1")
            else:
                missing_handoff = sorted(REQUIRED_HANDOFF_FIELDS - set(handoff))
                if missing_handoff:
                    errors.append(
                        "handoffs/support-handoff.json missing required fields: "
                        + ", ".join(missing_handoff)
                    )
                if "artifacts" in handoff and not isinstance(handoff["artifacts"], dict):
                    errors.append("handoffs/support-handoff.json artifacts must be an object")
                if "gap_dispositions" in handoff and not isinstance(handoff["gap_dispositions"], list):
                    errors.append("handoffs/support-handoff.json gap_dispositions must be a list")
                if handoff.get("customer_visible_sends_blocked_until_approved") is not True:
                    warnings.append("handoffs/support-handoff.json should block customer-visible sends until approved")
                if "next_owner" not in handoff:
                    warnings.append("handoffs/support-handoff.json should name next_owner")
                if "support_archetypes" not in handoff:
                    warnings.append("handoffs/support-handoff.json should list support_archetypes")
                if "support_intelligence" not in handoff:
                    warnings.append("handoffs/support-handoff.json should include support_intelligence loop status")
                if "validation" not in handoff:
                    warnings.append("handoffs/support-handoff.json should include validation status")
        except ValueError as exc:
            errors.append(str(exc))

    gap_path = root / "12-gap-dispositions.md"
    policies_path = root / "05-policies.md"
    intake_path = root / "00-intake.md"
    channels_path = root / "02-channels.md"
    themes_path = root / "vocabularies" / "themes.md"
    if gap_path.is_file():
        text = gap_path.read_text(encoding="utf-8").lower()
        if not any(disposition in text for disposition in ALLOWED_GAP_DISPOSITIONS):
            warnings.append("12-gap-dispositions.md has no explicit gap disposition terms")
    if policies_path.is_file() and "TBD-OWNER" in policies_path.read_text(encoding="utf-8"):
        warnings.append("05-policies.md still contains TBD-OWNER; keep high-risk automation disabled")
    if intake_path.is_file():
        text = intake_path.read_text(encoding="utf-8").lower()
        if "complexity band" not in text:
            warnings.append("00-intake.md should record the support complexity band")
        if "lifecycle mode" not in text:
            warnings.append("00-intake.md should record lifecycle mode")
        if not any(token in text for token in ("owner-answer:", "code:", "ticket:", "issue:", "provider-doc:", "metric:", "outcome:", "fire-drill:")):
            warnings.append("00-intake.md should include at least one source anchor")
    if channels_path.is_file():
        text = channels_path.read_text(encoding="utf-8").lower()
        if "manual" not in text:
            warnings.append("02-channels.md should name any manual-only channels or state none")
        if "cadence" not in text:
            warnings.append("02-channels.md should record review cadence for manual/community channels")
    if not themes_path.is_file():
        warnings.append("vocabularies/themes.md missing; VoC/product feedback loops are disabled until documented")

    return errors, warnings


def main(argv: list[str]) -> int:
    json_mode = False
    args: list[str] = []
    for arg in argv[1:]:
        if arg == "--json":
            json_mode = True
        else:
            args.append(arg)

    if len(args) != 1:
        print("usage: validate-support-map.py [--json] <project/.claude/support-triage>", file=sys.stderr)
        return 2

    root = Path(args[0]).resolve()
    errors, warnings = validate_support_map(root)
    ok = not errors

    if json_mode:
        print(json.dumps({"ok": ok, "root": str(root), "errors": errors, "warnings": warnings}, indent=2))
    else:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        for warning in warnings:
            print(f"warning: {warning}", file=sys.stderr)
        if ok:
            print(f"support map validation passed: {root}")

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
