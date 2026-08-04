# I02: add a fail-closed MatrixRTC qualification evaluator

## Owning repo

`ZenithResearch/Hypha`

## Objective

Add a pure SDK-neutral contract that reports selected-profile availability only from fresh, same-profile, authenticated, complete server+SDK evidence and rejects fallback-only, mixed, stale, malformed, missing, or unsupported evidence with typed reasons.

## Dependencies

- Parent initiative: https://github.com/ZenithResearch/Hypha/issues/6
- I01: https://github.com/ZenithResearch/Hypha/issues/7 — exact reviewed head required

## Complexity

- Total: 5
- Intrinsic: 5
- Existing: 2
- Remaining: 3
- Angles: typed domain contract 3; fail-closed evaluation 3; rejection matrix 3; owned fixtures 2

## PR boundary

One SDK-neutral core contract PR. No live networking, FFI session join, UI, permissions, transport, or media.

## Commit specs

### Commit 1 — `test(matrixrtc): specify fail-closed qualification outcomes`

- Paths: `Tests/ZenithMacOSClientCoreTests/MatrixRTCQualificationTests.swift`, `docs/matrixrtc/fixtures/**`, I02 ledger rows.
- Add RED tests for an exact hypothetical complete profile and for every reject family: missing snapshot, digest mismatch, missing/disabled/malformed feature advertisement, authenticated endpoint unsupported/malformed, fallback-only discovery, true convenience boolean without authoritative evidence, stale evidence, mixed profile/generation/origin, missing SDK session/crypto/notification/lifecycle capability, and the current production fixture.
- Prove deterministic reason ordering and no raw payload/token fixture fields.
- Stop after the intended missing-symbol/behavior RED state; do not add production implementation in this commit.

### Commit 2 — `feat(matrixrtc): evaluate selected-profile evidence`

- Paths: `Sources/ZenithMacOSClientCore/MatrixRTCQualification.swift`, I02 ledger rows.
- Add immutable evidence/profile/origin types, closed capability/reason enums, a pure evaluator, deterministic ordering, freshness checks, and safe descriptions.
- `m.rtc_foci` and `isLivekitRtcSupported()` are diagnostic-only and can never satisfy selected-profile availability.
- Acceptance evidence: all I02 tests GREEN; source imports no SwiftUI, AVFoundation, LiveKit, or network stack.

## Acceptance

- [ ] Only complete authoritative evidence yields `.available`.
- [ ] Fallback-only/mixed/stale/malformed/missing/unsupported evidence yields typed `.unavailable`.
- [ ] Current production fixture is unsupported.
- [ ] Current pinned SDK gap blocks availability.
- [ ] Evidence is origin/profile/generation-bound and deterministic.
- [ ] No secret/raw-response-bearing fields exist.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MatrixRTCQualificationTests`
- `python3 scripts/verify_matrixrtc_contract.py`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
- `git diff --check`

## Non-claims

The evaluator is not a live probe, SDK adapter, session joiner, transport grant, crypto implementation, media layer, or UI availability wiring.

## Stop conditions

Stop if a positive result would depend on legacy fallback, caller-supplied raw bodies/secrets, an unpinned profile, wall-clock/network nondeterminism, or a decision owned by Step 2.

## Allowed paths

`Sources/ZenithMacOSClientCore/MatrixRTCQualification.swift`, `Tests/ZenithMacOSClientCoreTests/MatrixRTCQualificationTests.swift`, `docs/matrixrtc/fixtures/**`, `docs/issues/matrixrtc-step1/**`.

## Stacked PR base

Branch `feat/matrixrtc-qualification-evaluator`; base `feat/matrixrtc-contract-profile` at I01's exact final head.
