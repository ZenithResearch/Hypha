#!/usr/bin/env python3
"""Behavioral tests for release metadata generation."""

from __future__ import annotations

import json
import plistlib
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "write_release_metadata.py"
COMMIT = "292d858ce32b49ebe84a69421661f486a0ef7e23"


def invoke(root: Path, *, tag: str = "v0.1.0", signing_mode: str = "adhoc", notarized: str = "false") -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "python3",
            str(SCRIPT),
            "--tag",
            tag,
            "--commit",
            COMMIT,
            "--app",
            str(root / "Hypha.app"),
            "--archive",
            str(root / "Hypha-v0.1.0-macos-arm64.zip"),
            "--gate",
            str(root / "encryption-gate.json"),
            "--signing-mode",
            signing_mode,
            "--notarized",
            notarized,
            "--output",
            str(root / "release.json"),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


with tempfile.TemporaryDirectory(prefix="hypha-release-metadata-") as temporary:
    root = Path(temporary)
    app = root / "Hypha.app"
    executable = app / "Contents" / "MacOS" / "Hypha"
    executable.parent.mkdir(parents=True)
    executable.write_bytes(b"test executable")
    with (app / "Contents" / "Info.plist").open("wb") as handle:
        plistlib.dump(
            {
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleIdentifier": "ca.zenithresearch.macos.client",
                "CFBundleExecutable": "Hypha",
                "CFBundleVersion": "1",
                "LSMinimumSystemVersion": "26.4",
            },
            handle,
        )
    (root / "Hypha-v0.1.0-macos-arm64.zip").write_bytes(b"release archive")
    (root / "encryption-gate.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "status": "passed",
                "commit_sha": COMMIT,
                "verified_at": "2026-08-05T00:46:18Z",
                "test": "live two-account proof",
                "homeserver": "synapse.zenith-research.ca",
                "evidence": {
                    "encrypted_send_and_decrypt": True,
                    "suspended_sender_restore_and_decrypt": True,
                    "temporary_accounts_remaining": 0,
                    "temporary_rooms_remaining": 0,
                },
            }
        ),
        encoding="utf-8",
    )

    success = invoke(root)
    if success.returncode != 0:
        raise SystemExit(f"valid release metadata failed:\n{success.stdout}")
    metadata = json.loads((root / "release.json").read_text(encoding="utf-8"))
    assert metadata["archive"]["archive_sha256"]
    assert metadata["bundle_identifier"] == "ca.zenithresearch.macos.client"
    assert metadata["bundle_version"] == "1"
    assert metadata["signing"] == {"distributable": False, "mode": "adhoc", "notarized": False}
    assert metadata["encryption_gate"]["commit_sha"] == COMMIT
    assert metadata["encryption_gate"]["homeserver"] == "synapse.zenith-research.ca"

    if invoke(root, tag="v0.2.0").returncode == 0:
        raise SystemExit("metadata accepted a tag that differs from the bundle version")
    if invoke(root, signing_mode="developer-id", notarized="false").returncode == 0:
        raise SystemExit("metadata accepted an unnotarized Developer ID package")
    if invoke(root, signing_mode="adhoc", notarized="true").returncode == 0:
        raise SystemExit("metadata accepted an ad-hoc notarization claim")

print("release metadata tests passed")
