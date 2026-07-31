# Hypha MatrixRTC contract profile

Status: qualified contract snapshot; runtime availability unsupported
Profile ID: `ca.hypha.matrixrtc.open-msc-snapshot.2026-07-30.1`
Canonical profile fingerprint: `bddeae87e3a2da8bb19b662465448b7fa0bc4e96fbc39954db83defe0f5c041f`

## Boundary

This profile is an exact composition of seven **open** Matrix Specification Proposals. It is not a released Matrix version. Any proposal byte, head, digest, identifier, state-key rule, API route, or required-capability change creates a new profile and requires migration review.

The machine-readable authority is [`contract-profile.json`](contract-profile.json). Its fingerprint is SHA-256 over canonical compact sorted-key JSON of the nested `profile` object; the fingerprint field is excluded from its own preimage.

## Selected protocol

- MSC4143 slots/members: `m.rtc.slot` / `org.matrix.msc4143.rtc.slot`; `m.rtc.member` / `org.matrix.msc4143.rtc.member`.
- Default room call application/slot: `m.call` / `m.call#ROOM`.
- Required encrypted-room profile: `m.per_member` / `org.matrix.msc4143.per_member`.
- Sender-key to-device event: `m.rtc.encryption_key` / `org.matrix.msc4143.rtc.encryption_key`.
- Notification: `m.rtc.notification` / `org.matrix.msc4075.rtc.notification`; acknowledgement `m.call.ring.ack` / `org.matrix.msc4075.call.ring.ack`.
- Decline: `m.rtc.decline` / `org.matrix.msc4310.rtc.decline`.
- Authenticated transport discovery: stable `GET /_matrix/client/v1/rtc/transports`; unstable `GET /_matrix/client/unstable/org.matrix.msc4143/rtc/transports`.
- Stale membership cleanup requires the MSC4140 delayed-event schedule/manage lifecycle.

The legacy `org.matrix.msc3401.call.member`, `m.rtc_foci`, the generated `isLivekitRtcSupported()` convenience boolean, and MSC4515 widget-only discovery are explicitly outside selected-profile availability. They may be recorded only as diagnostic gaps.

## SDK capability gap

The pinned Hypha artifact source is `f4889ec898e77d8b8c9013adadd77f3d0901fc2d`. It exposes useful earlier observation/notification/decline and OpenID surfaces, but its LiveKit boolean reads legacy well-known foci and it lacks the complete selected slot/member/delayed-leave/sender-key/grant/session surface.

Current upstream at `43565c555072cc8002450ece96bd5a90e2b4a0b5` adds authenticated transport discovery, but the FFI convenience method still falls back to well-known evidence and upstream still does not provide a complete native MatrixRTC session. Neither source can currently qualify Hypha to join.

## Production-safe unsupported evidence

The 2026-07-31 credential-free probes contain only endpoint kind, status class, selected feature presence, and safe Matrix error code. Well-known exposes no legacy foci; versions omits both selected feature flags; the stable transport registry returns HTTP 404 `M_UNRECOGNIZED`. No header, token, raw body, account, room, device, key, grant, or credential is retained. The only valid classification is `unsupported`.

## Product and authority decisions

Future call presentation uses a top-right room affordance and a Messages-like trailing inspector for unavailable, incoming, pre-join, and active states. Navigation may preserve a later active call only while the surface remains visibly bound to the originating account and room; navigation never changes call authority. Step 1 implements none of that UI or lifecycle.

Peer-device terminology must keep authenticated, cross-signed, locally SAS-verified, invalid, and revoked states distinct. Whether a valid cross-signed device without local peer verification receives media keys remains unresolved. Invalid and revoked devices fail closed.

## Non-claims

This profile does not prove native joining, interoperability, transport authorization, sender-key/frame encryption, media, microphone/camera permission, call UI, LiveKit deployment, or production readiness.
