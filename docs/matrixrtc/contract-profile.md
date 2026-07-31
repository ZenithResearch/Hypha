# Hypha MatrixRTC contract profile

Status: qualified contract snapshot; runtime availability unsupported
Profile ID: `ca.hypha.matrixrtc.open-msc-snapshot.2026-07-30.2`
Canonical profile fingerprint: `adb98379d638458b2e1e327e598222fccabfb8b91fca0ccd206908bd988257df`

## Boundary

This profile is an exact composition of nine **open** Matrix Specification Proposals. It includes MSC4354 because MSC4143 requires Sticky Events and its ephemeral-map algorithm, and MSC4518 because MSC4519 depends on registry semantics. It is not a released Matrix version. Any proposal byte, head, digest, identifier, state-key rule, API route, or required-capability change creates a new profile and requires migration review.

The machine-readable authority is [`contract-profile.json`](contract-profile.json). Its fingerprint is SHA-256 over canonical compact sorted-key JSON of the nested `profile` object; the fingerprint field is excluded from its own preimage.

## Selected protocol

- MSC4143 slots/members: `m.rtc.slot` / `org.matrix.msc4143.rtc.slot`; `m.rtc.member` / `org.matrix.msc4143.rtc.member`.
- Default room call application/slot: `m.call` / `m.call#ROOM`.
- Required encrypted-room profile: `m.per_member` / `org.matrix.msc4143.per_member`.
- Sender-key to-device event: `m.rtc.encryption_key` / `org.matrix.msc4143.rtc.encryption_key`.
- Notification: `m.rtc.notification` / `org.matrix.msc4075.rtc.notification`; acknowledgement `m.call.ring.ack` / `org.matrix.msc4075.call.ring.ack`.
- Decline: `m.rtc.decline` / `org.matrix.msc4310.rtc.decline`.
- Authenticated transport discovery: stable `GET /_matrix/client/v1/rtc/transports`; unstable `GET /_matrix/client/unstable/org.matrix.msc4143/rtc/transports`.
- MSC4195 token APIs include client `POST /_matrix/client/v1/rtc/livekit/get_token`, authenticated federation `POST /_matrix/federation/v1/rtc/livekit/get_token`, and delegated leave `POST /_matrix/client/v1/rtc/livekit/delegate_delayed_leave`.
- MSC4140 delayed events use stable schedule/manage/list routes and the exact unstable `org.matrix.msc4140` schedule/manage/list routes. The pinned snapshot specifies no unstable alias for the single-event lookup.
- MSC4140 feature flags are `org.matrix.msc4140` and `org.matrix.msc4140.stable`; its capability is `m.delayed_events` / `org.matrix.msc4140.delayed_events`; its sender-visible unsigned field is `delay_id` / `org.matrix.msc4140.delay_id`.
- MSC4354 membership events are sticky. The selected ephemeral map key is `(room_id, sender, type, content.sticky_key)`, with last-to-expire then highest-lexicographical-event-ID tie-breaking; membership `sticky_key` equals `member.id`.
- MSC4354 selected identifiers include the stable/unstable send query parameter, PDU object, sync section, content map key, unsigned TTL field, feature flag, and Sliding Sync extension recorded in the manifest.
- MSC4518 supplies registry-process authority. MSC4519 discovery accepts only registered opaque transport types with stability and specification metadata; the pinned unstable LiveKit exception uses `livekit`.

The legacy `org.matrix.msc3401.call.member`, `m.rtc_foci`, the generated `isLivekitRtcSupported()` convenience boolean, and MSC4515 widget-only discovery are explicitly outside selected-profile availability. They may be recorded only as diagnostic gaps.

## SDK capability gap

The pinned Hypha artifact source is `f4889ec898e77d8b8c9013adadd77f3d0901fc2d`. It exposes useful earlier observation/notification/decline and OpenID surfaces, but its LiveKit boolean reads legacy well-known foci and it lacks direct authenticated no-fallback transport discovery plus the complete selected sticky-map/slot/member/delayed-leave/sender-key/grant/session surface. The manifest binds these claims to exact source-file and generated-binding digests.

Current upstream at `43565c555072cc8002450ece96bd5a90e2b4a0b5` adds authenticated core transport discovery, but exposes no direct no-fallback FFI qualification surface: the FFI convenience method still falls back to well-known evidence. Upstream also lacks the selected sticky-map/session primitives and explicitly does not provide a complete native MatrixRTC session. The pinned artifact and current upstream both have `bounded_transport_grant = false`; the selected profile requires it as `true`. Neither source can currently qualify Hypha to join.

## Production-safe unsupported evidence

The 2026-07-31 credential-free probes contain only endpoint kind, status class, selected feature presence, and safe Matrix error code. Well-known exposes no legacy foci; versions omits both selected feature flags; the stable transport registry returns HTTP 404 `M_UNRECOGNIZED`. No header, token, raw body, account, room, device, key, grant, or credential is retained. The only valid classification is `unsupported`.

## Product and authority decisions

Future call presentation uses an operable top-right room affordance and a Messages-like trailing inspector for unavailable, incoming, pre-join, and active states, so keyboard and VoiceOver users can inspect an unavailable reason. Incoming calls never auto-open, steal focus, prompt permissions, answer, or connect media; closing the inspector or pressing Escape changes presentation only. Same-account room navigation may preserve a later active call only while the surface remains visibly bound to the immutable originating account and room and offers Return to origin. Account switching requires Leave and switch or Cancel, and a second call is blocked. Navigation never changes call authority. Step 1 implements none of that UI or lifecycle.

Peer-device terminology must keep authenticated, cross-signed, locally SAS-verified, invalid, and revoked states distinct. Invalid, revoked, and non-cross-signed devices fail closed. Whether a valid cross-signed device without local peer verification receives media keys remains unresolved and must be selected before any media-key implementation.

## Non-claims

This profile does not prove native joining, interoperability, transport authorization, sender-key/frame encryption, media, microphone/camera permission, call UI, LiveKit deployment, or production readiness.
