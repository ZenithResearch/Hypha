#!/usr/bin/env python3
"""Deterministic, offline integrity checks for Hypha's MatrixRTC contract profile."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "docs" / "matrixrtc" / "contract-profile.json"
CONTRACT_PATH = ROOT / "docs" / "matrixrtc" / "contract-profile.md"
SOURCE_VERIFICATION_PATH = ROOT / "docs" / "matrixrtc" / "source-verification.md"
SDK_EVIDENCE_PATH = ROOT / "docs" / "matrixrtc" / "sdk-capability-evidence.json"
CI_PATH = ROOT / ".github" / "workflows" / "ci.yml"
PROFILE_ID = "ca.hypha.matrixrtc.open-msc-snapshot.2026-07-30.2"
SCHEMA = "ca.hypha.matrixrtc.contract-profile-manifest.v1"
GENERATED_SWIFT_SHA256 = "7d823dda5f112ebc60887fc0ff238129b49e0173870ad616978f17b3ace5bdbc"
SDK_EVIDENCE_SHA256 = "8b185b1c03bffd54690a4710d929c96f7c3aee4dc9e648f02b3aedfece50dcdf"
SECTION_SHA256 = {
    "excluded_evidence": "9c2a0e9e264c2f359b67c835879e40e63edf286c7955fd45ccdf0c7ba1404d3b",
    "future_product_contract": "e77cc31c01894390dbb0233d70dcaa21becee829c31dcd266ee750e197ce5360",
    "identifiers": "c5c49bea7cd6d11bf0b471bc94eeb5abb1d5c696c6239c4a420e4eddada3d714",
    "non_claims": "b926ecf2df3d2ec9b1a0533814b7d3802c664843f21e8d630944015c1883f7d7",
    "production_evidence": "b74537b1d62803306457d7591a79f569588ae01f8b33b24f254b411e8e8a7a5a",
    "protocol_requirements": "1555820b9a67b8942a0e8e32a2018e666db31e6c2918af0446a922b032059c3a",
    "required_capabilities": "9cb0a4ea31f35f6bd97a6139fb6aa2ede9ce1977bb2f5fb3a5e700182bf31b69",
    "sdk_matrix": "3d4b3afd1fc0cb1b45792ddfedb9fd9724e541958035a28769fc23e2fc04e263",
}
EXPECTED_PROPOSALS = [
    (4143, "3236b007aaceee73e579e33990dd3ec5e07841e4", "proposals/4143-matrix-rtc.md", "78f14c6467a28600094c6837bab55706c0f75c4f535e671503e9fb4a11e04103"),
    (4140, "15770e6988f307499519b0cb294b95ed494171b6", "proposals/4140-delayed-events-futures.md", "6becf1e8e177e9cd28fea0f668b097be703775459d5141266970169dfaf7c8ab"),
    (4195, "afdcf273e507152699ffb0cbfa3f364550f2b112", "proposals/4195-matrixrtc-livekit.md", "007d7b33c29dbb2108f3df96dc9e6bd766f3e84399f18f205b44bda7a26f979c"),
    (4196, "5add2f0c96974c4996a6e5e0907018117cbb5934", "proposals/4196-matrixrtc-m-call.md", "29b0307635ac3524786cd1352fd8bbaaaa488160974561a371cf735841ec0e23"),
    (4075, "39cc54743a4f2187fdee1a69909b4a84eb7af014", "proposals/4075-rtc-notification-event.md", "b28513416ed3cedd81fb3d0f4b521a893a2ddf18929f58817469d7f5eadd325a"),
    (4310, "67687dc381f56c626edf6e00a2bd2c5e2d04e56b", "proposals/4310-MatrixRTC-call-decline.md", "a75e97e72de589c6b23b1d95ad542f202935f8e170a42dcbc96734689743e375"),
    (4519, "db488faa1c3f234847dada8d17893d60626e869d", "proposals/4519-rtc-transports-registry.md", "22aef4423a8b42561aff9e1e1333a0cfc10500c5275a3ea29359f66b275d9ae4"),
    (4354, "74fc75e1dc1301230cc3fcb7435205bf4f567ef8", "proposals/4354-sticky-events.md", "1a89c37ee7b0add4e55ebef2cce0d6ccb14ecb88e18a4dfdce498737b465ee02"),
    (4518, "a066bdbdf625b7efe98fdf84bf4a8c64fe5f6eb0", "proposals/4518-registries.md", "d070a21fe3d793a3f8f2088b9a00937a4b6e43118eccd502fcac09a0650c3a7b"),
]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def no_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"), object_pairs_hook=no_duplicate_pairs)
require(isinstance(manifest, dict), "manifest root is not an object")
require(
    set(manifest) == {"canonicalization", "schema", "profile", "profile_fingerprint_sha256"},
    "manifest root fields drift",
)
require(
    manifest["canonicalization"] == "SHA-256 of UTF-8 JSON for the profile object with keys sorted and separators ',' ':'",
    "manifest canonicalization rule drift",
)
require(manifest["schema"] == SCHEMA, "manifest schema drift")
profile = manifest["profile"]
require(isinstance(profile, dict), "profile is not an object")
require(profile.get("id") == PROFILE_ID, "profile ID drift or fictional release profile")
require(profile.get("kind") == "open_msc_snapshot", "profile kind is not an open MSC snapshot")
require(re.fullmatch(r"ca\.hypha\.matrixrtc\.open-msc-snapshot\.\d{4}-\d{2}-\d{2}\.\d+", profile["id"]) is not None, "profile ID is release-like")
expected_fingerprint = hashlib.sha256(canonical(profile)).hexdigest()
require(manifest["profile_fingerprint_sha256"] == expected_fingerprint, "canonical profile fingerprint mismatch")

proposals = profile.get("proposals")
require(isinstance(proposals, list) and len(proposals) == len(EXPECTED_PROPOSALS), "proposal set is not the exact nine-MSC snapshot")
actual_proposals = []
for proposal in proposals:
    require(isinstance(proposal, dict), "proposal entry is not an object")
    require(set(proposal) == {"msc", "status", "head", "source_path", "content_sha256"}, "proposal fields drift")
    require(proposal["status"] == "open", f"MSC{proposal.get('msc')} is not recorded as open")
    require(re.fullmatch(r"[0-9a-f]{40}", proposal["head"]) is not None, f"MSC{proposal.get('msc')} head is malformed")
    require(re.fullmatch(r"[0-9a-f]{64}", proposal["content_sha256"]) is not None, f"MSC{proposal.get('msc')} digest is malformed")
    actual_proposals.append((proposal["msc"], proposal["head"], proposal["source_path"], proposal["content_sha256"]))
require(actual_proposals == EXPECTED_PROPOSALS, "proposal heads, paths, order, or source digests drift")

for section, expected in SECTION_SHA256.items():
    require(section in profile, f"profile section missing: {section}")
    require(digest(profile[section]) == expected, f"profile section drift: {section}")

production = profile["production_evidence"]
require(production["qualification"] == "unsupported", "production evidence must remain unsupported")
require(production["credential_mode"] == "unauthenticated_sanitized", "production evidence is not sanitized")
require(production["well_known"]["has_m_rtc_foci"] is False, "legacy well-known evidence was promoted")
require(production["stable_transport_registry"]["http_status"] == 404, "production registry evidence drift")

sdk = profile["sdk_matrix"]
require(sdk["pinned_hypha_artifact"]["legacy_well_known_livekit_boolean"] is True, "pinned fallback gap drift")
require(sdk["pinned_hypha_artifact"]["authenticated_transport_registry"] is False, "pinned SDK transport capability overclaim")
require(sdk["current_upstream_source"]["ffi_convenience_falls_back_to_well_known"] is True, "current fallback gap drift")
require(sdk["current_upstream_source"]["ffi_direct_authenticated_transport_registry"] is False, "current FFI no-fallback capability overclaim")
require(sdk["current_upstream_source"]["complete_native_session_surface"] is False, "current SDK join capability overclaim")

sdk_evidence_bytes = SDK_EVIDENCE_PATH.read_bytes()
require(hashlib.sha256(sdk_evidence_bytes).hexdigest() == SDK_EVIDENCE_SHA256, "SDK capability evidence drift")
sdk_evidence = json.loads(sdk_evidence_bytes, object_pairs_hook=no_duplicate_pairs)
require(sdk_evidence["schema"] == "ca.hypha.matrixrtc.sdk-capability-evidence.v1", "SDK evidence schema drift")
require(sdk_evidence["qualification"] == "unsupported", "SDK evidence qualification overclaim")
require(sdk_evidence["pinned_hypha"]["commit"] == sdk["pinned_hypha_artifact"]["source_commit"], "pinned SDK evidence commit drift")
require(sdk_evidence["current_upstream"]["commit"] == sdk["current_upstream_source"]["commit"], "current SDK evidence commit drift")
require(
    sdk_evidence["current_upstream"]["files"] == sdk["current_upstream_source"]["source_evidence"],
    "current SDK evidence file digests drift",
)
for source_path, source_sha in sdk["pinned_hypha_artifact"]["source_evidence"].items():
    require(sdk_evidence["pinned_hypha"]["files"].get(source_path) == source_sha, f"pinned SDK evidence digest drift: {source_path}")
comparison = {entry["capability"]: entry for entry in sdk_evidence["comparison"]}
require(len(comparison) == len(sdk_evidence["comparison"]) == 8, "SDK capability comparison is incomplete or duplicated")
require(comparison["legacy_well_known_livekit_boolean"] == {
    "capability": "legacy_well_known_livekit_boolean",
    "current_upstream": True,
    "pinned_hypha": True,
    "selected_profile": False,
}, "legacy fallback was promoted in SDK comparison")
for capability in (
    "ffi_direct_authenticated_transport_registry_without_fallback",
    "sticky_event_ephemeral_map_surface",
    "slot_member_lifecycle",
    "delayed_leave_lifecycle",
    "sender_key_lifecycle",
    "complete_native_session_surface",
):
    require(
        comparison[capability]["pinned_hypha"] is False
        and comparison[capability]["current_upstream"] is False
        and comparison[capability]["selected_profile"] is True,
        f"SDK capability gap drift: {capability}",
    )

contract = CONTRACT_PATH.read_text(encoding="utf-8")
source_verification = SOURCE_VERIFICATION_PATH.read_text(encoding="utf-8")
require(PROFILE_ID in contract and expected_fingerprint in contract, "contract doc does not bind the exact profile")
for msc, head, source_path, source_sha in EXPECTED_PROPOSALS:
    require(f"| {msc} |" in source_verification, f"source verification row missing: MSC{msc}")
    require(head in source_verification and source_path in source_verification and source_sha in source_verification, f"source verification evidence drift: MSC{msc}")
require(source_verification.count("| MATCH |") == 9, "source verification does not contain nine matches")
require("Neither source can currently qualify Hypha to join" in contract, "SDK non-claim missing")
require("This profile does not prove native joining" in contract, "scope non-claim missing")

forbidden_profile = "Released" + "2026_07"
for path in (MANIFEST_PATH, CONTRACT_PATH, SOURCE_VERIFICATION_PATH, SDK_EVIDENCE_PATH):
    require(forbidden_profile not in path.read_text(encoding="utf-8"), f"fictional release profile survives: {path.name}")

for path in (ROOT / "Sources").rglob("*.swift"):
    text = path.read_text(encoding="utf-8")
    require("isLivekitRtcSupported" not in text, f"app source consumes legacy fallback boolean: {path.relative_to(ROOT)}")
    require("m.rtc_foci" not in text, f"app source consumes legacy well-known evidence: {path.relative_to(ROOT)}")
    require("org.matrix.msc3401.call.member" not in text, f"app source selects legacy membership: {path.relative_to(ROOT)}")

vendor_swift = ROOT / "Vendor" / "MatrixRustSDK" / "Sources" / "MatrixRustSDK" / "matrix_sdk_ffi.swift"
require(hashlib.sha256(vendor_swift.read_bytes()).hexdigest() == GENERATED_SWIFT_SHA256, "generated SDK binding drift")
require("func isLivekitRtcSupported()" in vendor_swift.read_text(encoding="utf-8"), "pinned SDK fallback evidence missing")
provenance = (ROOT / "Vendor" / "MatrixRustSDK" / "PROVENANCE.md").read_text(encoding="utf-8")
require(sdk["pinned_hypha_artifact"]["source_commit"] in provenance, "pinned SDK source commit missing from provenance")

ci = CI_PATH.read_text(encoding="utf-8")
require("python3 scripts/verify_matrixrtc_contract.py" in ci, "CI omits MatrixRTC contract verification")
require("python3 scripts/test_matrixrtc_contract_verifier.py" in ci, "CI omits MatrixRTC verifier mutation tests")

print(f"MatrixRTC contract verification passed: {expected_fingerprint}")
