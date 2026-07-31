# MatrixRTC Step 1 source-qualification roundtable

Status: SYNTHESIZED
Reviewed base: `a6f425b91946b3177410abcadc2155bbc58feff7`
Upstream SDK head inspected: `43565c555072cc8002450ece96bd5a90e2b4a0b5`

## Protocol / SDK evidence

- The seven selected MSCs are open proposals. The profile is an exact proposal snapshot, not a released Matrix version.
- MSC4143 at `3236b007aaceee73e579e33990dd3ec5e07841e4` defines stable/unstable pairs for `m.rtc.slot`, `m.rtc.member`, `m.per_member`, and `m.rtc.encryption_key`, plus feature flags `org.matrix.msc4143` and `org.matrix.msc4143.stable`.
- MSC4196 fixes the room calling application and default slot as `m.call` / `m.call#ROOM`.
- MSC4519 fixes authenticated transport discovery as `GET /_matrix/client/v1/rtc/transports`, with unstable path `/_matrix/client/unstable/org.matrix.msc4143/rtc/transports`.
- The pinned artifact source `f4889ec898e77d8b8c9013adadd77f3d0901fc2d` exposes a legacy well-known-backed `is_livekit_rtc_supported`; it does not expose a complete native MatrixRTC session.
- Current upstream `43565c555072cc8002450ece96bd5a90e2b4a0b5` adds authenticated transport discovery but its FFI convenience boolean still falls back to well-known data. Upstream still states the client is not supposed to join MatrixRTC sessions yet.

Verdict before repairs: BLOCKED.

The first protocol reviewer was interrupted without a verdict. A sole replacement reviewer completed the read-only lane and also returned BLOCKED. It specifically required a canonical manifest fingerprint, an exhaustive stable/unstable registry (including MSC4140 and MSC4519 endpoint spellings), explicit MSC3401/MSC4515 exclusion, and a pinned/current/required SDK capability matrix. Those findings are retained in I01 and I02 rather than averaged away.

## Security / privacy evidence

- No fail-closed qualification model exists at the reviewed base.
- Legacy `m.rtc_foci` or `isLivekitRtcSupported()` must be diagnostic-only and cannot satisfy selected-profile availability.
- Missing, disabled, malformed, stale, mixed-profile, fallback-only, and incomplete SDK evidence need distinct typed rejections.
- RTC peer trust must not reuse the current own-device enum. It must distinguish authenticated, cross-signed, locally SAS-verified, invalid, and revoked states; invalid and revoked take terminal precedence.
- Qualification evidence must exclude access tokens, OpenID tokens, sender keys, transport grants, authorization headers, raw response bodies, and private account/room data from public fixtures or descriptions.
- Preserved navigation must retain immutable origin account/homeserver/room/device/profile/evidence-generation binding and reject mutation through a different context.

Verdict before repairs: BLOCKED.

## Product / accessibility / QA evidence

- Future UI decisions are fixed but not implemented in Step 1: a top-right room call affordance opens a Messages-like trailing inspector for unavailable, incoming, pre-join, and active states.
- Navigation may preserve a future call only while the surface stays visibly bound to the originating account and room.
- Unsupported state requires typed reason codes plus safe title, description, accessibility label, and accessibility hint; a disabled control must not hide the reason.
- The July 27 vault draft contains stale, contradictory call-mode/detached-window diagrams and a fictional July 2026 release-style profile label.
- CI has no MatrixRTC manifest, stale-profile, fallback-rejection, fixture, or non-claim gate.

Verdict before repairs: BLOCKED.

## Lead synthesis

No blocker is discarded by vote. Step 1 is split into four serialized, repo-local PR boundaries:

1. I01 pins source snapshots, identifiers, SDK gaps, sanitized unsupported evidence, and deterministic source gates.
2. I02 adds the pure fail-closed availability/evaluator contract and owned negative fixtures.
3. I03 adds peer-device trust, secret-boundary, accessibility-presentation, and immutable origin lifecycle contracts.
4. I04 reconciles public docs/provenance/non-claims, expands CI/static gates, and records the final case study.

Each child has residual complexity at most 3. No child implements MatrixRTC session/media transport, sender keys, LiveKit, permissions, call UI, or production RTC deployment.
