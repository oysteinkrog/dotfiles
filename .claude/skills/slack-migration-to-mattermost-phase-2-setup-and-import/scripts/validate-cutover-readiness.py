#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import sys


def load_optional_json(path_str: str) -> dict:
    if not path_str:
        return {}
    path = Path(path_str)
    if not path.exists():
        raise FileNotFoundError(path)
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"json root must be an object: {path}")
    return payload


def dict_field(payload: dict, key: str, errors: list[str], label: str) -> dict:
    value = payload.get(key, {})
    if value in ("", None):
        return {}
    if not isinstance(value, dict):
        errors.append(f"{label} must be a JSON object")
        return {}
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description="Fail-closed cutover readiness gate for Phase 2.")
    parser.add_argument("--handoff-json", required=True)
    parser.add_argument("--config-report", required=True)
    parser.add_argument("--staging-report", required=True)
    parser.add_argument("--restore-report", default="")
    parser.add_argument("--evidence-pack", default="")
    parser.add_argument("--live-report", default="")
    parser.add_argument("--edge-report", default="")
    parser.add_argument("--smoke-report", default="")
    parser.add_argument("--reconciliation-report", default="")
    parser.add_argument("--activation-report", default="")
    parser.add_argument("--smtp-proof", default="")
    parser.add_argument("--rollback-owner", default="")
    parser.add_argument("--output-json", required=True)
    args = parser.parse_args()

    errors: list[str] = []
    warnings: list[str] = []

    try:
        handoff = load_optional_json(args.handoff_json)
        config = load_optional_json(args.config_report)
        staging = load_optional_json(args.staging_report)
        restore = load_optional_json(args.restore_report)
        evidence_pack = load_optional_json(args.evidence_pack)
        live = load_optional_json(args.live_report)
        edge = load_optional_json(args.edge_report)
        smoke = load_optional_json(args.smoke_report)
        reconciliation = load_optional_json(args.reconciliation_report)
        activation = load_optional_json(args.activation_report)
    except FileNotFoundError as exc:
        print(f"error: missing readiness input: {exc}", file=sys.stderr)
        return 1
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"error: invalid readiness input json: {exc}", file=sys.stderr)
        return 1

    final_package = dict_field(handoff, "final_package", errors, "handoff.final_package")
    if not final_package.get("sha256"):
        errors.append("handoff json is missing final package sha256")
    if config.get("status") != "passed":
        errors.append("Mattermost config validation did not pass")
    if staging.get("status") != "success":
        errors.append("staging rehearsal did not report success")
    if args.live_report and live.get("status") != "passed":
        errors.append("live stack verification did not pass")
    if args.edge_report and edge.get("status") != "passed":
        errors.append("Cloudflare edge verification did not pass")
    if args.smoke_report and smoke.get("status") != "passed":
        errors.append("post-import smoke tests did not pass")
    if args.reconciliation_report and reconciliation.get("status") != "matched":
        errors.append("handoff vs import reconciliation detected drift")
    if args.activation_report and activation.get("status") != "passed":
        errors.append("activation verification did not pass")
    if args.restore_report and restore.get("status") != "success":
        errors.append("restore drill did not report success")
    if args.evidence_pack and not evidence_pack.get("files"):
        warnings.append("evidence pack contains no files")
    if args.smtp_proof and not Path(args.smtp_proof).exists():
        errors.append(f"missing smtp proof artifact: {args.smtp_proof}")
    if not args.rollback_owner:
        errors.append("rollback owner must be specified")

    payload = {
        "status": "ready" if not errors else "blocked",
        "errors": errors,
        "warnings": warnings,
        "rollback_owner": args.rollback_owner,
        "workspace": handoff.get("workspace", ""),
        "checks": {
            "config": config.get("status", ""),
            "staging": staging.get("status", ""),
            "live": live.get("status", "") if args.live_report else "",
            "edge": edge.get("status", "") if args.edge_report else "",
            "smoke": smoke.get("status", "") if args.smoke_report else "",
            "reconciliation": reconciliation.get("status", "") if args.reconciliation_report else "",
            "activation": activation.get("status", "") if args.activation_report else "",
            "restore": restore.get("status", "") if args.restore_report else "",
        },
    }

    output = Path(args.output_json)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {output}")

    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("cutover readiness validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
