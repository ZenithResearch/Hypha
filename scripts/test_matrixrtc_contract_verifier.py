#!/usr/bin/env python3
"""Behavioral mutation tests for the MatrixRTC contract verifier."""

from __future__ import annotations

import json
import subprocess
from contextlib import contextmanager
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
VERIFIER = ROOT / "scripts" / "verify_matrixrtc_contract.py"
MANIFEST = ROOT / "docs" / "matrixrtc" / "contract-profile.json"
SDK_EVIDENCE = ROOT / "docs" / "matrixrtc" / "sdk-capability-evidence.json"


def run_verifier() -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["python3", str(VERIFIER)], cwd=ROOT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
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


def json_bytes(document: Any) -> bytes:
    return (json.dumps(document, indent=2, sort_keys=True) + "\n").encode()


def changed(value: Any) -> Any:
    if isinstance(value, bool):
        return not value
    if value is None:
        return "unexpected"
    if isinstance(value, int):
        return value + 1
    if isinstance(value, str):
        return value + ".drift"
    if isinstance(value, list):
        return value[1:] if value else ["unexpected"]
    raise TypeError(f"unsupported mutation value: {value!r}")


def mutate_path(document: dict[str, Any], path: tuple[Any, ...], *, remove: bool = False) -> None:
    cursor: Any = document
    for component in path[:-1]:
        cursor = cursor[component]
    if remove:
        if isinstance(cursor, list):
            cursor.pop(path[-1])
        else:
            cursor.pop(path[-1])
    else:
        cursor[path[-1]] = changed(cursor[path[-1]])


def manifest_bytes(path: tuple[Any, ...], *, remove: bool = False) -> bytes:
    document = json.loads(MANIFEST.read_text(encoding="utf-8"))
    mutate_path(document, path, remove=remove)
    return json_bytes(document)


def must_reject_manifest(name: str, path: tuple[Any, ...], expected: str, *, remove: bool = False) -> None:
    with replaced(MANIFEST, manifest_bytes(path, remove=remove)):
        result = run_verifier()
    if result.returncode == 0:
        raise SystemExit(f"verifier accepted manifest mutation: {name}")
    if expected not in result.stdout:
        raise SystemExit(
            f"verifier rejected {name} for the wrong reason; expected {expected!r}:\n{result.stdout}"
        )


def must_reject_file(name: str, path: Path, content: bytes, expected: str) -> None:
    with replaced(path, content):
        result = run_verifier()
    if result.returncode == 0:
        raise SystemExit(f"verifier accepted file mutation: {name}")
    if expected not in result.stdout:
        raise SystemExit(
            f"verifier rejected {name} for the wrong reason; expected {expected!r}:\n{result.stdout}"
        )


baseline = run_verifier()
if baseline.returncode != 0:
    raise SystemExit(f"baseline verifier failed:\n{baseline.stdout}")

# Proposal closure and every authoritative metadata component.
for field in ("head", "source_path", "status", "content_sha256"):
    must_reject_manifest(
        f"proposal {field} drift", ("profile", "proposals", 0, field),
        "proposal heads, paths, statuses, order, or source digests drift",
    )
must_reject_manifest(
    "missing mandatory sticky proposal", ("profile", "proposals", 7),
    "proposal set is not the exact nine-MSC snapshot", remove=True,
)
must_reject_manifest(
    "missing registry dependency", ("profile", "proposals", 8),
    "proposal set is not the exact nine-MSC snapshot", remove=True,
)
must_reject_manifest(
    "canonical fingerprint drift", ("profile_fingerprint_sha256",),
    "canonical profile fingerprint mismatch",
)

# Every fixed future-only product/presentation decision is semantic authority,
# not merely hash-bound prose. Mutate every leaf independently.
for path in (
    ("scope",),
    ("affordance", "location"),
    ("affordance", "selected_room_only"),
    ("affordance", "operable_when_unavailable"),
    ("affordance", "unavailable_action"),
    ("inspector", "surface"),
    ("inspector", "close_leaves_call"),
    ("inspector", "escape_leaves_call"),
    ("states",),
    ("unavailable_reason", "visible_fields"),
    ("unavailable_reason", "accessibility_label"),
    ("unavailable_reason", "accessibility_hint"),
    ("incoming", "auto_opens"),
    ("incoming", "steals_focus"),
    ("incoming", "requests_permission"),
    ("incoming", "answers"),
    ("incoming", "connects"),
    ("same_account_room_navigation", "preservation"),
    ("same_account_room_navigation", "origin_account"),
    ("same_account_room_navigation", "origin_room"),
    ("same_account_room_navigation", "return_action"),
    ("account_switch", "required_actions"),
    ("concurrency", "conflicting_second_call"),
):
    must_reject_manifest(
        f"future product contract {'/'.join(path)}",
        ("profile", "future_product_contract", *path),
        "future product contract semantics drift",
    )

# MSC4140: every stable/unstable API route, the intentional no-alias state,
# actions, flags, capability, and delay identifier.
for api, fields in {
    "delayed_event_schedule": ("stable", "unstable"),
    "delayed_event_manage": ("stable", "unstable", "actions"),
    "delayed_event_list": ("stable", "unstable"),
    "delayed_event_get": ("stable", "unstable", "unstable_status"),
}.items():
    for field in fields:
        must_reject_manifest(
            f"MSC4140 {api} {field}", ("profile", "identifiers", "apis", api, field),
            "MSC4140 API identifiers drift",
        )
for section, field in (
    ("feature_flags", "delayed_events"),
    ("capabilities", "delayed_events"),
    ("event_fields", "delayed_event_unsigned_id"),
):
    for variant in ("stable_identifiers", "unstable") if section == "feature_flags" else ("stable", "unstable"):
        must_reject_manifest(
            f"MSC4140 {field} {variant}",
            ("profile", "identifiers", section, field, variant),
            "MSC4140 feature, capability, or delay identifier drift",
        )

# MSC4354: every identifier and every sticky/ephemeral-map semantic.
for identifier, variants in {
    "send_query_parameter": ("stable", "unstable"),
    "pdu_object": ("stable", "unstable"),
    "sync_section": ("stable", "unstable"),
    "content_map_key": ("stable", "unstable"),
    "unsigned_ttl_field": ("stable", "unstable"),
    "sliding_sync_extension": ("stable", "unstable"),
}.items():
    for variant in variants:
        must_reject_manifest(
            f"MSC4354 {identifier} {variant}",
            ("profile", "identifiers", "sticky_events", identifier, variant),
            "MSC4354 identifiers drift",
        )
for variant in ("stable_identifiers", "unstable"):
    must_reject_manifest(
        f"MSC4354 feature flag {variant}",
        ("profile", "identifiers", "feature_flags", "sticky_events", variant),
        "MSC4354 identifiers drift",
    )
for field in ("duration_ms_min", "duration_ms_max", "expiry_formula", "member_events_must_be_sticky"):
    must_reject_manifest(
        f"MSC4354 sticky event {field}",
        ("profile", "protocol_requirements", "sticky_event", field),
        "MSC4354 sticky-event semantics drift",
    )
for field in ("key_tuple", "expiry", "deletion", "refresh", "membership_sticky_key", "tie_break"):
    must_reject_manifest(
        f"MSC4354 ephemeral map {field}",
        ("profile", "protocol_requirements", "ephemeral_map", field),
        "MSC4354 ephemeral-map semantics drift",
    )

# MSC4518/4519 registry authority, registration, metadata, exception, and rejection.
for field in (
    "process_authority", "discovery_entries_must_be_registered", "entry_fields",
    "livekit_exception", "unknown_transport_types_permitted",
):
    must_reject_manifest(
        f"MSC4518/4519 registry {field}",
        ("profile", "protocol_requirements", "registry", field),
        "MSC4518/4519 registry semantics drift",
    )

# Semantic identifier families not owned by MSC4140/4354.
for family, paths in {
    "MSC4143": (
        ("feature_flags", "matrixrtc", "stable_identifiers"),
        ("feature_flags", "matrixrtc", "unstable"),
        ("encryption", "stable"), ("encryption", "unstable"),
        ("room_events", "slot", "stable"), ("room_events", "slot", "unstable"),
        ("room_events", "slot", "state_key"),
        ("room_events", "member", "stable"), ("room_events", "member", "unstable"),
        ("room_events", "member", "state_key"), ("room_events", "member", "sticky_key"),
        ("to_device_events", "encryption_key", "stable"),
        ("to_device_events", "encryption_key", "unstable"),
        ("apis", "transport_registry", "stable"),
        ("apis", "transport_registry", "unstable"),
        ("apis", "transport_registry", "authentication"),
    ),
    "MSC4195": (
        ("apis", "livekit_token", "proposal_route"),
        ("apis", "livekit_federation_token", "proposal_route"),
        ("apis", "livekit_delegate_delayed_leave", "proposal_route"),
    ),
    "MSC4196": (
        ("application", "type"), ("application", "call_id_field"),
        ("application", "intent_field"), ("application", "default_room_slot"),
    ),
    "MSC4075": (
        ("room_events", "notification", "stable"),
        ("room_events", "notification", "unstable"),
        ("to_device_events", "ring_ack", "stable"),
        ("to_device_events", "ring_ack", "unstable"),
    ),
    "MSC4310": (
        ("room_events", "decline", "stable"),
        ("room_events", "decline", "unstable"),
    ),
}.items():
    for path in paths:
        must_reject_manifest(
            f"{family} semantic identifier {'/'.join(path)}",
            ("profile", "identifiers", *path), f"{family} identifiers drift",
        )

# Every mechanically represented SDK capability is flipped in all three
# manifest columns and all three evidence columns, including bounded grants.
manifest_sdk_capabilities = {
    "pinned_hypha_artifact": (
        "legacy_well_known_livekit_boolean", "authenticated_transport_registry",
        "bounded_transport_grant", "complete_native_session_surface",
        "delayed_leave_lifecycle", "sender_key_lifecycle", "slot_member_lifecycle",
        "sticky_event_ephemeral_map_surface", "ffi_decline_surface",
        "ffi_legacy_active_call_observation", "ffi_notification_projection",
        "ffi_openid_token_surface",
    ),
    "current_upstream_source": (
        "authenticated_transport_registry", "bounded_transport_grant",
        "complete_native_session_surface", "ffi_convenience_falls_back_to_well_known",
        "ffi_direct_authenticated_transport_registry", "sticky_event_ephemeral_map_surface",
    ),
    "selected_profile_requires": (
        "authenticated_transport_registry_without_fallback", "bounded_transport_grant",
        "complete_native_session_surface", "delayed_leave_lifecycle",
        "sender_key_lifecycle", "slot_member_lifecycle", "sticky_event_ephemeral_map_surface",
    ),
}
for column, capabilities in manifest_sdk_capabilities.items():
    for capability in capabilities:
        must_reject_manifest(
            f"SDK manifest {column} {capability}",
            ("profile", "sdk_matrix", column, capability),
            "SDK manifest capability matrix drift",
        )

sdk_document = json.loads(SDK_EVIDENCE.read_text(encoding="utf-8"))
for index, entry in enumerate(sdk_document["comparison"]):
    for column in ("pinned_hypha", "current_upstream", "selected_profile"):
        mutated = json.loads(SDK_EVIDENCE.read_text(encoding="utf-8"))
        mutated["comparison"][index][column] = not entry[column]
        must_reject_file(
            f"SDK evidence {entry['capability']} {column}", SDK_EVIDENCE,
            json_bytes(mutated), "SDK capability comparison drift",
        )

# Every required non-claim must remain explicit.
manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
for index in reversed(range(len(manifest["profile"]["non_claims"]))):
    must_reject_manifest(
        f"required nonclaim removed at {index}", ("profile", "non_claims", index),
        "required non-claims drift", remove=True,
    )

must_reject_manifest(
    "fictional release profile", ("profile", "id"),
    "profile ID drift or fictional release profile",
)
probe = ROOT / "Sources" / "ZenithMacOSClientCore" / "MatrixRTCFallbackProbe.swift"
must_reject_file(
    "app source calls legacy convenience boolean", probe,
    b"func qualifies() async throws -> Bool { try await client.isLivekitRtcSupported() }\n",
    "app source consumes legacy fallback boolean",
)
workflow_path = ROOT / ".github" / "workflows" / "ci.yml"
workflow = workflow_path.read_text(encoding="utf-8")
must_reject_file(
    "CI omits contract verifier", workflow_path,
    workflow.replace("          python3 scripts/verify_matrixrtc_contract.py\n", "").encode(),
    "CI omits MatrixRTC contract verification",
)
must_reject_file(
    "CI omits contract mutation tests", workflow_path,
    workflow.replace("          python3 scripts/test_matrixrtc_contract_verifier.py\n", "").encode(),
    "CI omits MatrixRTC verifier mutation tests",
)

print("MatrixRTC contract verifier mutation tests passed")
