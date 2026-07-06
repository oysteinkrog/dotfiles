#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import sys
import zipfile


TOP_LEVEL_METADATA = {
    "channels.json",
    "groups.json",
    "dms.json",
    "mpims.json",
    "users.json",
    "org_users.json",
    "integration_logs.json",
}
NON_MESSAGE_PARTS = {"__uploads", "sidecars", "workflows", "emoji"}


def load_json_from_zip(archive: zipfile.ZipFile, name: str):
    with archive.open(name) as handle:
        return json.load(handle)


def path_is_message_json(name: str) -> bool:
    path = Path(name)
    return (
        path.suffix == ".json"
        and len(path.parts) >= 2
        and path.name not in TOP_LEVEL_METADATA
        and all(part not in NON_MESSAGE_PARTS for part in path.parts)
    )


def normalize_key(value: str) -> str:
    return value.strip().lower()


def iter_upload_keys(path: Path):
    candidates = [
        path.name,
        path.stem,
        path.parent.name,
        path.as_posix(),
    ]
    if len(path.parts) >= 2:
        candidates.append("/".join(path.parts[-2:]))
    for candidate in candidates:
        normalized = normalize_key(candidate)
        if normalized:
            yield normalized


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate emails, file downloads, emoji, and sidecar coverage in an enriched Slack export.")
    parser.add_argument("--archive", required=True)
    parser.add_argument("--output-json", default="")
    parser.add_argument("--require-uploads", action="store_true")
    args = parser.parse_args()

    archive_path = Path(args.archive)
    if not archive_path.exists():
        print(f"error: archive not found: {archive_path}", file=sys.stderr)
        return 1

    errors: list[str] = []
    warnings: list[str] = []
    missing_file_refs: list[dict] = []
    missing_email_users: list[str] = []
    file_refs = 0
    uploads = 0
    emoji_assets = 0
    sidecar_assets = 0
    workflow_assets = 0

    try:
        with zipfile.ZipFile(archive_path) as archive:
            names = archive.namelist()

            if "users.json" in names:
                users = load_json_from_zip(archive, "users.json")
            elif "org_users.json" in names:
                users = load_json_from_zip(archive, "org_users.json")
            else:
                users = []
                warnings.append("archive has no users.json or org_users.json")

            for user in users:
                username = user.get("name") or user.get("id") or "unknown-user"
                profile = user.get("profile", {})
                if not profile.get("email"):
                    missing_email_users.append(str(username))

            upload_entries = [
                name for name in names if "__uploads/" in name and not name.endswith("/")
            ]
            uploads = len(upload_entries)
            emoji_assets = len(
                [
                    name
                    for name in names
                    if "emoji/" in name and not name.endswith("/") and not name.endswith(".json")
                ]
            )
            sidecar_assets = len(
                [name for name in names if "sidecars/" in name and not name.endswith("/")]
            )
            workflow_assets = len(
                [name for name in names if "workflows/" in name and not name.endswith("/")]
            )

            upload_keys = set()
            for name in upload_entries:
                upload_path = Path(name)
                upload_keys.update(iter_upload_keys(upload_path))

            for name in names:
                if not path_is_message_json(name):
                    continue
                try:
                    messages = load_json_from_zip(archive, name)
                except json.JSONDecodeError as exc:
                    warnings.append(f"{name}: invalid json skipped during enrichment validation: {exc}")
                    continue
                if not isinstance(messages, list):
                    continue
                for message in messages:
                    if not isinstance(message, dict):
                        warnings.append(f"{name}: encountered non-object message entry during validation")
                        continue
                    file_objects = message.get("files", [])
                    if not isinstance(file_objects, list):
                        warnings.append(
                            f"{name}: message {message.get('ts', '')} has non-list files payload"
                        )
                        continue
                    for file_obj in file_objects:
                        if not isinstance(file_obj, dict):
                            warnings.append(
                                f"{name}: message {message.get('ts', '')} has non-object file entry"
                            )
                            continue
                        file_refs += 1
                        file_id = str(file_obj.get("id", ""))
                        file_name = Path(str(file_obj.get("name", ""))).name
                        url = str(file_obj.get("url_private_download") or file_obj.get("url_private") or "")
                        url_name = Path(url.split("?", 1)[0]).name
                        candidate_keys = {
                            normalize_key(file_id),
                            normalize_key(file_name),
                            normalize_key(url_name),
                        }
                        if file_id and file_name:
                            candidate_keys.add(normalize_key(f"{file_id}/{file_name}"))
                        if any(key and key in upload_keys for key in candidate_keys):
                            continue
                        missing_file_refs.append(
                            {
                                "file_id": file_id,
                                "file_name": file_name,
                                "source_message_ts": message.get("ts", ""),
                                "url": url,
                            }
                        )
    except zipfile.BadZipFile:
        print(f"error: invalid zip file: {archive_path}", file=sys.stderr)
        return 1

    if args.require_uploads and file_refs > 0 and uploads == 0:
        errors.append("attachments were referenced but no __uploads/ entries were found")
    if missing_email_users:
        warnings.append(f"{len(missing_email_users)} users are still missing email addresses")
    if missing_file_refs:
        warnings.append(f"{len(missing_file_refs)} file references do not match downloaded upload entries")

    report = {
        "archive": str(archive_path),
        "users_missing_email": missing_email_users,
        "file_references": file_refs,
        "uploaded_files": uploads,
        "missing_file_references": missing_file_refs[:200],
        "emoji_assets": emoji_assets,
        "sidecar_assets": sidecar_assets,
        "workflow_assets": workflow_assets,
        "errors": errors,
        "warnings": warnings,
    }

    if args.output_json:
        output_path = Path(args.output_json)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {output_path}")

    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
