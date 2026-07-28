#!/usr/bin/env python3
"""Behavioral mutation tests for the public-release verifier."""

from __future__ import annotations

import subprocess
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERIFIER = ROOT / "scripts" / "verify_public_release.py"


def run_verifier() -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["python3", str(VERIFIER)],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


@contextmanager
def replaced(path: Path, content: bytes):
    original = path.read_bytes() if path.exists() else None
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    try:
        yield
    finally:
        if original is None:
            path.unlink(missing_ok=True)
        else:
            path.write_bytes(original)


def must_reject(name: str, path: Path, content: bytes) -> None:
    with replaced(path, content):
        result = run_verifier()
    if result.returncode == 0:
        raise SystemExit(f"verifier accepted mutation: {name}")


baseline = run_verifier()
if baseline.returncode != 0:
    raise SystemExit(f"baseline verifier failed:\n{baseline.stdout}")

license_path = ROOT / "LICENSE"
must_reject("fake AGPL phrase", license_path, b"GNU AFFERO GENERAL PUBLIC LICENSE\n")

workflow_path = ROOT / ".github" / "workflows" / "ci.yml"
workflow = workflow_path.read_text(encoding="utf-8")
must_reject(
    "mutable action",
    workflow_path,
    (workflow + "\n  probe:\n    runs-on: macos-26\n    steps:\n      - uses: example/action@main\n").encode(),
)
must_reject(
    "job write-all permissions",
    workflow_path,
    (workflow + "\n  probe:\n    permissions: write-all\n    runs-on: macos-26\n    steps: []\n").encode(),
)
must_reject(
    "quoted job write permission",
    workflow_path,
    (workflow + "\n  probe:\n    permissions:\n      contents: \"write\"\n    runs-on: macos-26\n    steps: []\n").encode(),
)
must_reject(
    "mutable container image",
    workflow_path,
    (workflow + "\n  probe:\n    runs-on: macos-26\n    container: example/image:latest\n    steps: []\n").encode(),
)
must_reject(
    "local action without recursive policy",
    workflow_path,
    (workflow + "\n  probe:\n    runs-on: macos-26\n    steps:\n      - uses: ./.github/actions/probe\n").encode(),
)

notices_path = ROOT / "THIRD_PARTY_NOTICES.md"
notices = notices_path.read_text(encoding="utf-8")
needle = "| `addr2line` |"
line = next(line for line in notices.splitlines() if line.startswith(needle))
parts = line.split(" | ")
parts[3] = "`Proprietary`"
mutated_line = " | ".join(parts)
must_reject(
    "proprietary normalized dependency license",
    notices_path,
    notices.replace(line, mutated_line, 1).encode(),
)
fake_parts = line.split(" | ")
fake_parts[0] = "| `substituted-valid-package`"
fake_parts[1] = "`1.0.0`"
fake_parts[5] = "[source](https://crates.io/api/v1/crates/substituted-valid-package/1.0.0/download)"
must_reject(
    "valid-looking package row substitution",
    notices_path,
    notices.replace(line, " | ".join(fake_parts), 1).encode(),
)

security_path = ROOT / "SECURITY.md"
security = security_path.read_text(encoding="utf-8")
must_reject(
    "redirected security endpoint",
    security_path,
    security.replace(
        "https://github.com/ZenithResearch/Hypha/security/advisories/new",
        "https://attacker.invalid/security/advisories/new",
    ).encode(),
)

must_reject(
    "additional mutable workflow",
    ROOT / ".github" / "workflows" / "probe.yaml",
    b"name: probe\non: push\npermissions: {}\njobs:\n  probe:\n    runs-on: macos-26\n    steps:\n      - uses: example/action@main\n",
)
must_reject(
    "escaped pull-request-target trigger",
    ROOT / ".github" / "workflows" / "probe.yaml",
    b'name: probe\n"on":\n  push:\n  pull_request:\n  "pull_request\\u005ftarget":\npermissions:\n  contents: read\njobs:\n  probe:\n    runs-on: macos-26\n    steps: []\n',
)
must_reject(
    "mutable reusable workflow",
    ROOT / ".github" / "workflows" / "probe.yaml",
    b'name: probe\n"on":\n  push:\n  pull_request:\npermissions:\n  contents: read\njobs:\n  probe:\n    uses: example/repository/.github/workflows/build.yml@main\n',
)
must_reject(
    "reusable workflow secret inheritance",
    ROOT / ".github" / "workflows" / "probe.yaml",
    b'name: probe\n"on":\n  push:\n  pull_request:\npermissions:\n  contents: read\njobs:\n  probe:\n    uses: example/repository/.github/workflows/build.yml@0123456789abcdef0123456789abcdef01234567\n    secrets: inherit\n',
)
must_reject(
    "UTF-16 tracked candidate",
    ROOT / "public-release-probe.txt",
    "private path probe".encode("utf-16"),
)
must_reject(
    "UTF-8-compatible unreviewed container",
    ROOT / "public-release-probe.bin",
    b"valid UTF-8 bytes in an unreviewed container",
)

print("public-release verifier mutation tests passed")
