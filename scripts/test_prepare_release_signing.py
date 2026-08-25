#!/usr/bin/env python3
"""Behavioral checks for fail-closed release signing preparation."""

from __future__ import annotations

import base64
import os
import stat
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "prepare-release-signing.sh"
SECRET_NAMES = (
    "MACOS_CERTIFICATE_P12",
    "MACOS_CERTIFICATE_PASSWORD",
    "RELEASE_KEYCHAIN_PASSWORD",
    "APPLE_API_KEY_P8",
    "APPLE_API_KEY_ID",
    "APPLE_API_ISSUER_ID",
)


def fixture_environment(root: Path, *, identities: int = 1) -> dict[str, str]:
    fake_bin = root / "bin"
    fake_bin.mkdir()
    security_log = root / "security.log"
    security = fake_bin / "security"
    security.write_text(
        """#!/bin/bash
set -euo pipefail
printf '%s\\n' "$*" >> "$SECURITY_LOG"
if [[ "${1:-}" == "find-identity" ]]; then
  for ((index = 1; index <= FAKE_IDENTITIES; index += 1)); do
    printf '  %d) HASH "Developer ID Application: Zenith Research (KR4YTNKK3Y)"\\n' "$index"
  done
fi
""",
        encoding="utf-8",
    )
    security.chmod(0o755)
    environment = os.environ.copy()
    environment.update(
        {
            "PATH": f"{fake_bin}:{environment['PATH']}",
            "SECURITY_LOG": str(security_log),
            "FAKE_IDENTITIES": str(identities),
            "RUNNER_TEMP": str(root / "runner"),
            "GITHUB_ENV": str(root / "github-env"),
            "MACOS_CERTIFICATE_P12": base64.b64encode(b"certificate").decode(),
            "MACOS_CERTIFICATE_PASSWORD": "certificate-password",
            "RELEASE_KEYCHAIN_PASSWORD": "keychain-password",
            "APPLE_API_KEY_P8": base64.b64encode(b"notary-key").decode(),
            "APPLE_API_KEY_ID": "KEY123",
            "APPLE_API_ISSUER_ID": "issuer-123",
        }
    )
    Path(environment["RUNNER_TEMP"]).mkdir()
    return environment


def run(environment: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["/bin/bash", str(SCRIPT)],
        cwd=ROOT,
        env=environment,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def exported_paths(path: Path) -> dict[str, Path]:
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        name, value = line.split("=", 1)
        values[name] = Path(value)
    return values


with tempfile.TemporaryDirectory(prefix="hypha-release-credentials-") as temporary:
    fixture = Path(temporary)
    environment = fixture_environment(fixture)
    result = run(environment)
    if result.returncode != 0:
        raise SystemExit(f"valid credential import failed:\n{result.stderr}")
    paths = exported_paths(Path(environment["GITHUB_ENV"]))
    assert set(paths) == {
        "HYPHA_RELEASE_CREDENTIAL_DIR",
        "HYPHA_RELEASE_KEYCHAIN_PATH",
        "HYPHA_RELEASE_CERTIFICATE_PATH",
        "HYPHA_NOTARY_KEY_PATH",
    }
    assert paths["HYPHA_RELEASE_CERTIFICATE_PATH"].read_bytes() == b"certificate"
    assert paths["HYPHA_NOTARY_KEY_PATH"].read_bytes() == b"notary-key"
    assert stat.S_IMODE(paths["HYPHA_RELEASE_CERTIFICATE_PATH"].stat().st_mode) == 0o600
    assert stat.S_IMODE(paths["HYPHA_NOTARY_KEY_PATH"].stat().st_mode) == 0o600
    security_log = (fixture / "security.log").read_text(encoding="utf-8")
    assert "-T /usr/bin/codesign" in security_log
    assert "-A" not in security_log.split()

for missing in SECRET_NAMES:
    with tempfile.TemporaryDirectory(prefix="hypha-release-missing-") as temporary:
        fixture = Path(temporary)
        environment = fixture_environment(fixture)
        environment.pop(missing)
        result = run(environment)
        assert result.returncode != 0
        assert missing in result.stderr
        assert not (fixture / "security.log").exists()

for identities in (0, 2):
    with tempfile.TemporaryDirectory(prefix="hypha-release-identity-") as temporary:
        fixture = Path(temporary)
        environment = fixture_environment(fixture, identities=identities)
        result = run(environment)
        assert result.returncode != 0
        assert f"found {identities}" in result.stderr
        assert list(Path(environment["RUNNER_TEMP"]).iterdir()) == []

print("release credential import tests passed")
