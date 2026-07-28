#!/usr/bin/env python3
"""Verify that the packaged app carries the repository's license materials verbatim."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("usage: verify_app_licenses.py REPOSITORY_ROOT APP_BUNDLE")

root = Path(sys.argv[1]).resolve()
app = Path(sys.argv[2]).resolve()
resources = app / "Contents" / "Resources" / "Licenses"

pairs = {
    root / "LICENSE": resources / "AGPL-3.0-or-later.txt",
    root / "THIRD_PARTY_NOTICES.md": resources / "THIRD_PARTY_NOTICES.md",
    root / "THIRD_PARTY_LICENSES.html": resources / "THIRD_PARTY_LICENSES.html",
}
for source in sorted((root / "LICENSES").glob("*.txt")):
    pairs[source] = resources / "LICENSES" / source.name


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

for source, packaged in pairs.items():
    if not source.is_file():
        raise SystemExit(f"source license material missing: {source.relative_to(root)}")
    if not packaged.is_file():
        raise SystemExit(f"packaged license material missing: {packaged.relative_to(app)}")
    if digest(source) != digest(packaged):
        raise SystemExit(f"packaged license material differs: {packaged.relative_to(app)}")

source_receipt = resources / "SOURCE.txt"
if not source_receipt.is_file():
    raise SystemExit("packaged source receipt missing")
receipt = source_receipt.read_text(encoding="utf-8")
if "https://github.com/ZenithResearch/Hypha" not in receipt or "Commit: " not in receipt:
    raise SystemExit("packaged source receipt is incomplete")

print("packaged license verification passed")
