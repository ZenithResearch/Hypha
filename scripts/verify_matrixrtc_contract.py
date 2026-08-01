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
README_PATH = ROOT / "README.md"
ARCHITECTURE_PATH = ROOT / "docs" / "architecture.md"
SECURITY_PATH = ROOT / "docs" / "security-model.md"
PROVENANCE_PATH = ROOT / "Vendor" / "MatrixRustSDK" / "PROVENANCE.md"
CASE_STUDY_PATH = ROOT / "docs" / "issues" / "matrixrtc-step1" / "case-study.md"
PROFILE_ID = "ca.hypha.matrixrtc.open-msc-snapshot.2026-07-30.2"
SCHEMA = "ca.hypha.matrixrtc.contract-profile-manifest.v1"
GENERATED_SWIFT_SHA256 = "7d823dda5f112ebc60887fc0ff238129b49e0173870ad616978f17b3ace5bdbc"
SDK_EVIDENCE_SHA256 = "436e34ae7c10d7832b3de48b0f67913d3f9e4b415c2687e55303f1d26fb461de"
SECTION_SHA256 = {
    "excluded_evidence": "9c2a0e9e264c2f359b67c835879e40e63edf286c7955fd45ccdf0c7ba1404d3b",
    "future_product_contract": "a68e785703677ab9464183d4eec365faca9a58309dfb3329baf00106e4125733",
    "identifiers": "692651a337e64300220c9064db3085e687dcca481aa7d860d30b4fbe2510f022",
    "non_claims": "b926ecf2df3d2ec9b1a0533814b7d3802c664843f21e8d630944015c1883f7d7",
    "production_evidence": "b74537b1d62803306457d7591a79f569588ae01f8b33b24f254b411e8e8a7a5a",
    "protocol_requirements": "1555820b9a67b8942a0e8e32a2018e666db31e6c2918af0446a922b032059c3a",
    "required_capabilities": "9cb0a4ea31f35f6bd97a6139fb6aa2ede9ce1977bb2f5fb3a5e700182bf31b69",
    "sdk_matrix": "b8c282deb2515823f54613afc56b0876126f38cddbef9a88a57f29f4f1a23d2b",
}
EXPECTED_PROPOSALS = [
    (4143, "3236b007aaceee73e579e33990dd3ec5e07841e4", "proposals/4143-matrix-rtc.md", "open", "78f14c6467a28600094c6837bab55706c0f75c4f535e671503e9fb4a11e04103"),
    (4140, "15770e6988f307499519b0cb294b95ed494171b6", "proposals/4140-delayed-events-futures.md", "open", "6becf1e8e177e9cd28fea0f668b097be703775459d5141266970169dfaf7c8ab"),
    (4195, "afdcf273e507152699ffb0cbfa3f364550f2b112", "proposals/4195-matrixrtc-livekit.md", "open", "007d7b33c29dbb2108f3df96dc9e6bd766f3e84399f18f205b44bda7a26f979c"),
    (4196, "5add2f0c96974c4996a6e5e0907018117cbb5934", "proposals/4196-matrixrtc-m-call.md", "open", "29b0307635ac3524786cd1352fd8bbaaaa488160974561a371cf735841ec0e23"),
    (4075, "39cc54743a4f2187fdee1a69909b4a84eb7af014", "proposals/4075-rtc-notification-event.md", "open", "b28513416ed3cedd81fb3d0f4b521a893a2ddf18929f58817469d7f5eadd325a"),
    (4310, "67687dc381f56c626edf6e00a2bd2c5e2d04e56b", "proposals/4310-MatrixRTC-call-decline.md", "open", "a75e97e72de589c6b23b1d95ad542f202935f8e170a42dcbc96734689743e375"),
    (4519, "db488faa1c3f234847dada8d17893d60626e869d", "proposals/4519-rtc-transports-registry.md", "open", "22aef4423a8b42561aff9e1e1333a0cfc10500c5275a3ea29359f66b275d9ae4"),
    (4354, "74fc75e1dc1301230cc3fcb7435205bf4f567ef8", "proposals/4354-sticky-events.md", "open", "1a89c37ee7b0add4e55ebef2cce0d6ccb14ecb88e18a4dfdce498737b465ee02"),
    (4518, "a066bdbdf625b7efe98fdf84bf4a8c64fe5f6eb0", "proposals/4518-registries.md", "open", "d070a21fe3d793a3f8f2088b9a00937a4b6e43118eccd502fcac09a0650c3a7b"),
]
EXPECTED_MSC4140_APIS = {
    "delayed_event_schedule": {
        "stable": "PUT /_matrix/client/v3/rooms/{roomId}/delayed_event/{eventType}/{txnId}",
        "unstable": "PUT /_matrix/client/unstable/org.matrix.msc4140/rooms/{roomId}/delayed_event/{eventType}/{txnId}",
    },
    "delayed_event_manage": {
        "actions": ["send", "cancel", "restart"],
        "stable": "POST /_matrix/client/v1/delayed_events/{delay_id}/{action}",
        "unstable": "POST /_matrix/client/unstable/org.matrix.msc4140/delayed_events/{delay_id}/{action}",
    },
    "delayed_event_list": {
        "stable": "GET /_matrix/client/v1/delayed_events",
        "unstable": "GET /_matrix/client/unstable/org.matrix.msc4140/delayed_events",
    },
    "delayed_event_get": {
        "stable": "GET /_matrix/client/v1/delayed_events/{delay_id}",
        "unstable": None,
        "unstable_status": "no unstable alias specified by the pinned MSC4140 snapshot",
    },
}
EXPECTED_MSC4354_IDENTIFIERS = {
    "content_map_key": {"stable": "sticky_key", "unstable": "msc4354_sticky_key"},
    "pdu_object": {"stable": "sticky", "unstable": "msc4354_sticky"},
    "send_query_parameter": {"stable": "sticky_duration_ms", "unstable": "org.matrix.msc4354.sticky_duration_ms"},
    "sliding_sync_extension": {"stable": None, "unstable": "org.matrix.msc4354.sticky_events"},
    "sync_section": {"stable": "sticky", "unstable": "msc4354_sticky"},
    "unsigned_ttl_field": {"stable": "unsigned.sticky_duration_ttl_ms", "unstable": "unsigned.msc4354_sticky_duration_ttl_ms"},
}
EXPECTED_REGISTRY = {
    "discovery_entries_must_be_registered": True,
    "entry_fields": ["opaque transport type", "stable or unstable status", "transport specification link"],
    "livekit_exception": "livekit is the pinned unstable type rather than msc4195.livekit",
    "process_authority": "MSC4518 registry process",
    "unknown_transport_types_permitted": False,
}
EXPECTED_NON_CLAIMS = [
    "native_session_available", "production_rtc_ready", "livekit_authorized",
    "sender_keys_implemented", "media_implemented", "call_ui_implemented",
]
EXPECTED_FUTURE_PRODUCT_CONTRACT = {
    "account_switch": {"required_actions": ["Leave and switch", "Cancel"]},
    "affordance": {
        "location": "selected_room_top_right",
        "operable_when_unavailable": True,
        "selected_room_only": True,
        "unavailable_action": "expose_unavailable_reason",
    },
    "concurrency": {"conflicting_second_call": "blocked"},
    "incoming": {
        "answers": False,
        "auto_opens": False,
        "connects": False,
        "requests_permission": False,
        "steals_focus": False,
    },
    "inspector": {
        "close_leaves_call": False,
        "escape_leaves_call": False,
        "surface": "messages_like_trailing_inspector",
    },
    "same_account_room_navigation": {
        "origin_account": "immutable",
        "origin_room": "immutable",
        "preservation": "may_preserve_only_while_visibly_bound_to_origin",
        "return_action": "Return to origin",
    },
    "scope": "future_only_nonruntime",
    "states": ["unavailable", "incoming", "pre_join", "active"],
    "unavailable_reason": {
        "accessibility_hint": "required",
        "accessibility_label": "required",
        "visible_fields": ["title", "description", "recovery"],
    },
}
EXPECTED_COMPARISON = {
    "legacy_well_known_livekit_boolean": (True, True, False),
    "core_authenticated_transport_registry": (False, True, True),
    "ffi_direct_authenticated_transport_registry_without_fallback": (False, False, True),
    "sticky_event_ephemeral_map_surface": (False, False, True),
    "slot_member_lifecycle": (False, False, True),
    "delayed_leave_lifecycle": (False, False, True),
    "profile_aware_participant_device_snapshot": (False, False, True),
    "notification_and_decline": (True, True, True),
    "sender_key_lifecycle": (False, False, True),
    "recipient_device_validation": (False, False, True),
    "bounded_transport_grant": (False, False, True),
    "registered_transport_type_validation": (False, False, True),
    "complete_native_session_surface": (False, False, True),
}
EXPECTED_SELECTED_SDK_REQUIREMENTS = {
    "authenticated_transport_registry_without_fallback",
    "bounded_transport_grant",
    "complete_native_session_surface",
    "delayed_leave_lifecycle",
    "notification_and_decline",
    "profile_aware_participant_device_snapshot",
    "recipient_device_validation",
    "registered_transport_type_validation",
    "sender_key_lifecycle",
    "slot_member_lifecycle",
    "sticky_event_ephemeral_map_surface",
}
PUBLIC_DOC_REQUIREMENTS = {
    README_PATH: (
        "## MatrixRTC contract qualification",
        "Step 1 qualifies contracts only; it does not implement calling.",
        PROFILE_ID,
        "The current Matrix Rust SDK and production deployment are unsupported.",
    ),
    ARCHITECTURE_PATH: (
        "## MatrixRTC contract boundary",
        "MatrixRTCPeerTrustClassifier",
        "MatrixRTCOriginLifecycleEvaluator",
        "future-only",
        "Current SDK and production evidence remain unsupported.",
    ),
    SECURITY_PATH: (
        "## MatrixRTC Step 1",
        "No trust classification grants media-key authority.",
        "cross-signed but not locally SAS-verified",
        "remains unresolved",
    ),
    PROVENANCE_PATH: (
        "## MatrixRTC qualification gap",
        PROFILE_ID,
        "630c781b782eb94965fb83767a39247f2d127ac31f0c89065f18711b375f8f6d",
        "unsupported",
    ),
}
FORBIDDEN_PUBLIC_DOC_CLAIMS = (
    "Released2026_07",
    "[Voice] [Video]",
    "[ Chat ] [ Canvas ] [ Call",
    "Join video call",
    "Hypha can join MatrixRTC",
    "production is RTC-ready",
    "MatrixRTC is implemented",
)


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
require(set(manifest) == {"canonicalization", "schema", "profile", "profile_fingerprint_sha256"}, "manifest root fields drift")
require(manifest["canonicalization"] == "SHA-256 of UTF-8 JSON for the profile object with keys sorted and separators ',' ':'", "manifest canonicalization rule drift")
require(manifest["schema"] == SCHEMA, "manifest schema drift")
profile = manifest["profile"]
require(isinstance(profile, dict), "profile is not an object")
require(profile.get("id") == PROFILE_ID, "profile ID drift or fictional release profile")
require(profile.get("kind") == "open_msc_snapshot", "profile kind is not an open MSC snapshot")
require(re.fullmatch(r"ca\.hypha\.matrixrtc\.open-msc-snapshot\.\d{4}-\d{2}-\d{2}\.\d+", profile["id"]) is not None, "profile ID is release-like")

proposals = profile.get("proposals")
require(isinstance(proposals, list) and len(proposals) == len(EXPECTED_PROPOSALS), "proposal set is not the exact nine-MSC snapshot")
actual_proposals = []
for proposal in proposals:
    require(isinstance(proposal, dict), "proposal entry is not an object")
    require(set(proposal) == {"msc", "status", "head", "source_path", "content_sha256"}, "proposal fields drift")
    actual_proposals.append((proposal["msc"], proposal["head"], proposal["source_path"], proposal["status"], proposal["content_sha256"]))
require(actual_proposals == EXPECTED_PROPOSALS, "proposal heads, paths, statuses, order, or source digests drift")

identifiers = profile["identifiers"]
apis = identifiers["apis"]
require({key: apis[key] for key in EXPECTED_MSC4140_APIS} == EXPECTED_MSC4140_APIS, "MSC4140 API identifiers drift")
require(
    identifiers["feature_flags"]["delayed_events"] == {"stable_identifiers": "org.matrix.msc4140.stable", "unstable": "org.matrix.msc4140"}
    and identifiers["capabilities"]["delayed_events"] == {"stable": "m.delayed_events", "unstable": "org.matrix.msc4140.delayed_events"}
    and identifiers["event_fields"]["delayed_event_unsigned_id"] == {"stable": "delay_id", "unstable": "org.matrix.msc4140.delay_id"},
    "MSC4140 feature, capability, or delay identifier drift",
)
require(identifiers["sticky_events"] == EXPECTED_MSC4354_IDENTIFIERS, "MSC4354 identifiers drift")
require(identifiers["feature_flags"]["sticky_events"] == {"stable_identifiers": None, "unstable": "org.matrix.msc4354"}, "MSC4354 identifiers drift")
requirements = profile["protocol_requirements"]
require(requirements["sticky_event"] == {
    "duration_ms_max": 3600000, "duration_ms_min": 0,
    "expiry_formula": "min(received_ts, origin_server_ts) + min(sticky.duration_ms, 3600000)",
    "member_events_must_be_sticky": True,
}, "MSC4354 sticky-event semantics drift")
require(requirements["ephemeral_map"] == {
    "deletion": "send a sticky event containing the sticky key with application-specific fields omitted",
    "expiry": "expire entries when event stickiness ends",
    "key_tuple": ["room_id", "sender", "type", "content.sticky_key"],
    "membership_sticky_key": "content.sticky_key MUST equal member.id",
    "refresh": "reuse the same sticky key and sticky duration",
    "tie_break": ["highest origin_server_ts + sticky.duration_ms", "highest lexicographical event_id"],
}, "MSC4354 ephemeral-map semantics drift")
require(requirements["registry"] == EXPECTED_REGISTRY, "MSC4518/4519 registry semantics drift")

require(
    identifiers["feature_flags"]["matrixrtc"] == {"stable_identifiers": "org.matrix.msc4143.stable", "unstable": "org.matrix.msc4143"}
    and identifiers["encryption"] == {"stable": "m.per_member", "unstable": "org.matrix.msc4143.per_member"}
    and identifiers["room_events"]["slot"] == {"stable": "m.rtc.slot", "state_key": "{application_type}#{application_slot_id}", "unstable": "org.matrix.msc4143.rtc.slot"}
    and identifiers["room_events"]["member"] == {"stable": "m.rtc.member", "state_key": None, "sticky_key": "member.id", "unstable": "org.matrix.msc4143.rtc.member"}
    and identifiers["to_device_events"]["encryption_key"] == {"stable": "m.rtc.encryption_key", "unstable": "org.matrix.msc4143.rtc.encryption_key"}
    and apis["transport_registry"] == {"authentication": "matrix_access_token", "stable": "GET /_matrix/client/v1/rtc/transports", "unstable": "GET /_matrix/client/unstable/org.matrix.msc4143/rtc/transports"},
    "MSC4143 identifiers drift",
)
require(
    apis["livekit_token"] == {"proposal_route": "POST /_matrix/client/v1/rtc/livekit/get_token"}
    and apis["livekit_federation_token"] == {"proposal_route": "POST /_matrix/federation/v1/rtc/livekit/get_token"}
    and apis["livekit_delegate_delayed_leave"] == {"proposal_route": "POST /_matrix/client/v1/rtc/livekit/delegate_delayed_leave"},
    "MSC4195 identifiers drift",
)
require(identifiers["application"] == {
    "call_id_field": "m.call.id", "default_room_slot": "m.call#ROOM",
    "intent_field": "m.call.intent", "type": "m.call",
}, "MSC4196 identifiers drift")
require(
    identifiers["room_events"]["notification"] == {"stable": "m.rtc.notification", "unstable": "org.matrix.msc4075.rtc.notification"}
    and identifiers["to_device_events"]["ring_ack"] == {"stable": "m.call.ring.ack", "unstable": "org.matrix.msc4075.call.ring.ack"},
    "MSC4075 identifiers drift",
)
require(identifiers["room_events"]["decline"] == {"stable": "m.rtc.decline", "unstable": "org.matrix.msc4310.rtc.decline"}, "MSC4310 identifiers drift")
require(profile["non_claims"] == EXPECTED_NON_CLAIMS, "required non-claims drift")
require(
    profile["future_product_contract"] == EXPECTED_FUTURE_PRODUCT_CONTRACT,
    "future product contract semantics drift",
)

sdk = profile["sdk_matrix"]
expected_sdk_capabilities = {
    "pinned_hypha_artifact": {
        "legacy_well_known_livekit_boolean": True, "authenticated_transport_registry": False,
        "bounded_transport_grant": False, "complete_native_session_surface": False,
        "delayed_leave_lifecycle": False, "sender_key_lifecycle": False,
        "slot_member_lifecycle": False, "sticky_event_ephemeral_map_surface": False,
        "profile_aware_participant_device_snapshot": False,
        "notification_and_decline": True, "recipient_device_validation": False,
        "registered_transport_type_validation": False,
        "ffi_decline_surface": True, "ffi_legacy_active_call_observation": True,
        "ffi_notification_projection": True, "ffi_openid_token_surface": True,
    },
    "current_upstream_source": {
        "authenticated_transport_registry": True, "bounded_transport_grant": False,
        "complete_native_session_surface": False, "ffi_convenience_falls_back_to_well_known": True,
        "ffi_direct_authenticated_transport_registry": False, "sticky_event_ephemeral_map_surface": False,
        "profile_aware_participant_device_snapshot": False,
        "notification_and_decline": True, "recipient_device_validation": False,
        "registered_transport_type_validation": False,
    },
    "selected_profile_requires": {
        "authenticated_transport_registry_without_fallback": True, "bounded_transport_grant": True,
        "complete_native_session_surface": True, "delayed_leave_lifecycle": True,
        "sender_key_lifecycle": True, "slot_member_lifecycle": True,
        "sticky_event_ephemeral_map_surface": True,
        "profile_aware_participant_device_snapshot": True,
        "notification_and_decline": True, "recipient_device_validation": True,
        "registered_transport_type_validation": True,
    },
}
for column, expected in expected_sdk_capabilities.items():
    require(all(sdk[column].get(key) is value for key, value in expected.items()), "SDK manifest capability matrix drift")
require(
    set(sdk["selected_profile_requires"]) == EXPECTED_SELECTED_SDK_REQUIREMENTS,
    "selected profile SDK requirement closure drift",
)

production = profile["production_evidence"]
require(production["qualification"] == "unsupported", "production evidence must remain unsupported")
require(production["credential_mode"] == "unauthenticated_sanitized", "production evidence is not sanitized")
require(production["well_known"]["has_m_rtc_foci"] is False, "legacy well-known evidence was promoted")
require(production["stable_transport_registry"]["http_status"] == 404, "production registry evidence drift")

expected_fingerprint = hashlib.sha256(canonical(profile)).hexdigest()
require(manifest["profile_fingerprint_sha256"] == expected_fingerprint, "canonical profile fingerprint mismatch")
for section, expected in SECTION_SHA256.items():
    require(section in profile, f"profile section missing: {section}")
    require(digest(profile[section]) == expected, f"profile section drift: {section}")

sdk_evidence_bytes = SDK_EVIDENCE_PATH.read_bytes()
sdk_evidence = json.loads(sdk_evidence_bytes, object_pairs_hook=no_duplicate_pairs)
require(sdk_evidence["schema"] == "ca.hypha.matrixrtc.sdk-capability-evidence.v1", "SDK evidence schema drift")
require(sdk_evidence["qualification"] == "unsupported", "SDK evidence qualification overclaim")
require(sdk_evidence["pinned_hypha"]["commit"] == sdk["pinned_hypha_artifact"]["source_commit"], "pinned SDK evidence commit drift")
require(sdk_evidence["current_upstream"]["commit"] == sdk["current_upstream_source"]["commit"], "current SDK evidence commit drift")
require(sdk_evidence["current_upstream"]["files"] == sdk["current_upstream_source"]["source_evidence"], "current SDK evidence file digests drift")
for source_path, source_sha in sdk["pinned_hypha_artifact"]["source_evidence"].items():
    require(sdk_evidence["pinned_hypha"]["files"].get(source_path) == source_sha, f"pinned SDK evidence digest drift: {source_path}")
comparison = {entry["capability"]: entry for entry in sdk_evidence["comparison"]}
actual_comparison = {
    capability: (entry.get("pinned_hypha"), entry.get("current_upstream"), entry.get("selected_profile"))
    for capability, entry in comparison.items()
}
require(len(comparison) == len(sdk_evidence["comparison"]) and actual_comparison == EXPECTED_COMPARISON, "SDK capability comparison drift")
require(hashlib.sha256(sdk_evidence_bytes).hexdigest() == SDK_EVIDENCE_SHA256, "SDK capability evidence drift")

contract = CONTRACT_PATH.read_text(encoding="utf-8")
source_verification = SOURCE_VERIFICATION_PATH.read_text(encoding="utf-8")
require(PROFILE_ID in contract and expected_fingerprint in contract, "contract doc does not bind the exact profile")
for msc, head, source_path, _status, source_sha in EXPECTED_PROPOSALS:
    require(f"| {msc} |" in source_verification, f"source verification row missing: MSC{msc}")
    require(head in source_verification and source_path in source_verification and source_sha in source_verification, f"source verification evidence drift: MSC{msc}")
require(source_verification.count("| MATCH |") == 9, "source verification does not contain nine matches")
require("Neither source can currently qualify Hypha to join" in contract, "SDK non-claim missing")
require("This profile does not prove native joining" in contract, "scope non-claim missing")
require("POST /_matrix/federation/v1/rtc/livekit/get_token" in contract, "MSC4195 federation token route missing from contract doc")
require("POST /_matrix/federation/v1/rtc/livekit/get_token" in source_verification, "MSC4195 federation token route missing from source verification doc")
require("bounded_transport_grant = false" in contract and "requires it as `true`" in contract, "bounded grant comparison missing from contract doc")

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
provenance = PROVENANCE_PATH.read_text(encoding="utf-8")
require(sdk["pinned_hypha_artifact"]["source_commit"] in provenance, "pinned SDK source commit missing from provenance")
for path, required_phrases in PUBLIC_DOC_REQUIREMENTS.items():
    text = path.read_text(encoding="utf-8")
    for phrase in required_phrases:
        require(phrase in text, f"public MatrixRTC contract claim missing: {path.relative_to(ROOT)}: {phrase}")
for path in (*PUBLIC_DOC_REQUIREMENTS, CONTRACT_PATH, CASE_STUDY_PATH):
    text = path.read_text(encoding="utf-8")
    for claim in FORBIDDEN_PUBLIC_DOC_CLAIMS:
        require(claim not in text, f"stale or overclaimed MatrixRTC surface: {path.relative_to(ROOT)}: {claim}")
for path in (README_PATH, ARCHITECTURE_PATH, SECURITY_PATH):
    text = path.read_text(encoding="utf-8")
    require("isLivekitRtcSupported() proves availability" not in text, f"legacy fallback promoted in public docs: {path.relative_to(ROOT)}")
ci = CI_PATH.read_text(encoding="utf-8")
require("python3 scripts/verify_matrixrtc_contract.py" in ci, "CI omits MatrixRTC contract verification")
require("python3 scripts/test_matrixrtc_contract_verifier.py" in ci, "CI omits MatrixRTC verifier mutation tests")

print(f"MatrixRTC contract verification passed: {expected_fingerprint}")
