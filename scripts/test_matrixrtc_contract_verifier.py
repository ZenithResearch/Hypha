#!/usr/bin/env python3
"""Behavioral mutation tests for the MatrixRTC contract verifier."""

from __future__ import annotations

import copy
import json
import subprocess
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERIFIER = ROOT / "scripts" / "verify_matrixrtc_contract.py"
MANIFEST = ROOT / "docs" / "matrixrtc" / "contract-profile.json"
SDK_EVIDENCE = ROOT / "docs" / "matrixrtc" / "sdk-capability-evidence.json"


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


def manifest_bytes(mutator) -> bytes:
    document = json.loads(MANIFEST.read_text(encoding="utf-8"))
    mutator(document)
    return (json.dumps(document, indent=2, sort_keys=True) + "\n").encode()


def must_reject_manifest(name: str, mutator) -> None:
    with replaced(MANIFEST, manifest_bytes(mutator)):
        result = run_verifier()
    if result.returncode == 0:
        raise SystemExit(f"verifier accepted manifest mutation: {name}")


def must_reject_file(name: str, path: Path, content: bytes) -> None:
    with replaced(path, content):
        result = run_verifier()
    if result.returncode == 0:
        raise SystemExit(f"verifier accepted file mutation: {name}")


baseline = run_verifier()
if baseline.returncode != 0:
    raise SystemExit(f"baseline verifier failed:\n{baseline.stdout}")

must_reject_manifest(
    "missing mandatory sticky proposal",
    lambda d: d["profile"].__setitem__(
        "proposals", [p for p in d["profile"]["proposals"] if p["msc"] != 4354]
    ),
)
must_reject_manifest(
    "missing registry dependency",
    lambda d: d["profile"].__setitem__(
        "proposals", [p for p in d["profile"]["proposals"] if p["msc"] != 4518]
    ),
)
must_reject_manifest(
    "proposal digest drift",
    lambda d: d["profile"]["proposals"][0].__setitem__("content_sha256", "0" * 64),
)
must_reject_manifest(
    "canonical fingerprint drift",
    lambda d: d.__setitem__("profile_fingerprint_sha256", "f" * 64),
)
must_reject_manifest(
    "missing delayed schedule unstable route",
    lambda d: d["profile"]["identifiers"]["apis"]["delayed_event_schedule"].pop("unstable"),
)
must_reject_manifest(
    "wrong delayed feature flag",
    lambda d: d["profile"]["identifiers"]["feature_flags"]["delayed_events"].__setitem__(
        "unstable", "org.example.msc4140"
    ),
)
must_reject_manifest(
    "wrong delayed capability",
    lambda d: d["profile"]["identifiers"]["capabilities"]["delayed_events"].__setitem__(
        "unstable", "org.example.delayed_events"
    ),
)
must_reject_manifest(
    "wrong delayed unsigned field",
    lambda d: d["profile"]["identifiers"]["event_fields"]["delayed_event_unsigned_id"].__setitem__(
        "unstable", "org.example.delay_id"
    ),
)
must_reject_manifest(
    "legacy membership selected",
    lambda d: d["profile"]["identifiers"]["room_events"]["member"].__setitem__(
        "unstable", "org.matrix.msc3401.call.member"
    ),
)
must_reject_manifest(
    "sticky map key tuple reordered",
    lambda d: d["profile"]["protocol_requirements"]["ephemeral_map"].__setitem__(
        "key_tuple", ["room_id", "sender", "content.sticky_key", "type"]
    ),
)
must_reject_manifest(
    "sticky tie break weakened",
    lambda d: d["profile"]["protocol_requirements"]["ephemeral_map"].__setitem__(
        "tie_break", ["highest origin_server_ts"]
    ),
)
must_reject_manifest(
    "unknown registry transports allowed",
    lambda d: d["profile"]["protocol_requirements"]["registry"].__setitem__(
        "unknown_transport_types_permitted", True
    ),
)
must_reject_manifest(
    "widget-only proposal promoted",
    lambda d: d["profile"]["proposals"].append(
        {
            "msc": 4515,
            "status": "open",
            "head": "0" * 40,
            "source_path": "proposals/widget-only.md",
            "content_sha256": "0" * 64,
        }
    ),
)
must_reject_manifest(
    "legacy fallback promoted to production availability",
    lambda d: (
        d["profile"]["production_evidence"].__setitem__("qualification", "available"),
        d["profile"]["production_evidence"]["well_known"].__setitem__("has_m_rtc_foci", True),
    ),
)
must_reject_manifest(
    "current FFI fallback marked authoritative",
    lambda d: d["profile"]["sdk_matrix"]["current_upstream_source"].__setitem__(
        "ffi_direct_authenticated_transport_registry", True
    ),
)
must_reject_manifest(
    "fictional release profile",
    lambda d: d["profile"].__setitem__("id", "Released" + "2026_07"),
)

sdk_evidence = json.loads(SDK_EVIDENCE.read_text(encoding="utf-8"))
sdk_evidence["comparison"][0]["selected_profile"] = True
must_reject_file(
    "SDK comparison promotes legacy fallback",
    SDK_EVIDENCE,
    (json.dumps(sdk_evidence, indent=2, sort_keys=True) + "\n").encode(),
)

probe = ROOT / "Sources" / "ZenithMacOSClientCore" / "MatrixRTCFallbackProbe.swift"
must_reject_file(
    "app source calls legacy convenience boolean",
    probe,
    b"func qualifies() async throws -> Bool { try await client.isLivekitRtcSupported() }\n",
)

workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
must_reject_file(
    "CI omits contract verifier",
    ROOT / ".github" / "workflows" / "ci.yml",
    workflow.replace("          python3 scripts/verify_matrixrtc_contract.py\n", "").encode(),
)
must_reject_file(
    "CI omits contract mutation tests",
    ROOT / ".github" / "workflows" / "ci.yml",
    workflow.replace("          python3 scripts/test_matrixrtc_contract_verifier.py\n", "").encode(),
)

print("MatrixRTC contract verifier mutation tests passed")
