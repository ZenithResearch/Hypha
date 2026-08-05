#!/usr/bin/env python3
"""Write deterministic release metadata bound to a packaged Hypha archive."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--gate", type=Path, required=True)
    parser.add_argument("--signing-mode", choices=("developer-id", "adhoc"), required=True)
    parser.add_argument("--notarized", choices=("true", "false"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    tag_match = re.fullmatch(r"v(\d+\.\d+\.\d+)", args.tag)
    if tag_match is None:
        raise SystemExit("release tag must use vMAJOR.MINOR.PATCH")
    if re.fullmatch(r"[0-9a-f]{40}", args.commit) is None:
        raise SystemExit("release commit must be a full lowercase Git SHA")
    if not args.archive.is_file():
        raise SystemExit("release archive is missing")

    info_path = args.app / "Contents" / "Info.plist"
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    gate = json.loads(args.gate.read_text(encoding="utf-8"))
    if gate.get("schema_version") != 1 or gate.get("status") != "passed":
        raise SystemExit("encryption gate has not passed")
    gate_commit = gate.get("commit_sha")
    if not isinstance(gate_commit, str) or re.fullmatch(r"[0-9a-f]{40}", gate_commit) is None:
        raise SystemExit("encryption gate commit is invalid")
    evidence = gate.get("evidence")
    if not isinstance(evidence, dict):
        raise SystemExit("encryption gate evidence is missing")
    required_evidence = {
        "encrypted_send_and_decrypt": True,
        "suspended_sender_restore_and_decrypt": True,
        "temporary_accounts_remaining": 0,
        "temporary_rooms_remaining": 0,
    }
    if any(evidence.get(key) != value for key, value in required_evidence.items()):
        raise SystemExit("encryption gate evidence is incomplete")

    version = tag_match.group(1)
    if info.get("CFBundleShortVersionString") != version:
        raise SystemExit("release tag does not match CFBundleShortVersionString")
    executable = info.get("CFBundleExecutable")
    if executable != "Hypha" or not (args.app / "Contents" / "MacOS" / executable).is_file():
        raise SystemExit("packaged Hypha executable is missing")
    if info.get("CFBundleIdentifier") != "ca.zenithresearch.macos.client":
        raise SystemExit("packaged bundle identity changed")
    if info.get("LSMinimumSystemVersion") != "26.4":
        raise SystemExit("packaged minimum macOS version changed")

    notarized = args.notarized == "true"
    if args.signing_mode == "developer-id" and not notarized:
        raise SystemExit("Developer ID release metadata requires notarization")
    if args.signing_mode == "adhoc" and notarized:
        raise SystemExit("ad-hoc package cannot claim notarization")

    metadata = {
        "schema_version": 1,
        "product": "Hypha",
        "version": version,
        "tag": args.tag,
        "commit_sha": args.commit,
        "source": f"https://github.com/ZenithResearch/Hypha/tree/{args.commit}",
        "platform": "macos",
        "architecture": "arm64",
        "minimum_macos": info.get("LSMinimumSystemVersion"),
        "bundle_identifier": info.get("CFBundleIdentifier"),
        "bundle_executable": executable,
        "bundle_version": info.get("CFBundleVersion"),
        "signing": {
            "mode": args.signing_mode,
            "notarized": notarized,
            "distributable": args.signing_mode == "developer-id" and notarized,
        },
        "archive": {
            "name": args.archive.name,
            "size_bytes": args.archive.stat().st_size,
            "archive_sha256": sha256(args.archive),
        },
        "encryption_gate": {
            "status": gate["status"],
            "commit_sha": gate_commit,
            "verified_at": gate.get("verified_at"),
            "test": gate.get("test"),
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
