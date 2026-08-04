# I03: define MatrixRTC trust, secret, accessibility, and origin boundaries

## Owning repo

`ZenithResearch/Hypha`

## Objective

Define distinct peer-device trust evidence, terminal invalid/revoked behavior, non-secret qualification surfaces, accessible unsupported presentation, and immutable origin account/room lifecycle binding without deciding media-key policy or implementing calls.

## Dependencies

- Parent initiative: https://github.com/ZenithResearch/Hypha/issues/6
- I02: https://github.com/ZenithResearch/Hypha/issues/8 — exact reviewed head required

## Complexity

- Total: 5
- Intrinsic: 5
- Existing: 2
- Remaining: 3
- Angles: peer trust 3; privacy/secret boundary 2; lifecycle binding 3; accessibility semantics 2

## PR boundary

One SDK-neutral security/product contract PR. No sender keys, transport grants, media, permission prompts, or SwiftUI call surface.

## Commit specs

### Commit 1 — `test(matrixrtc): specify trust and origin invariants`

- Paths: `Tests/ZenithMacOSClientCoreTests/MatrixRTCSecurityContractTests.swift`, I03 ledger rows.
- Add RED tests distinguishing authenticated, cross-signed, locally SAS-verified, invalid, revoked, unknown, and malformed evidence.
- Prove invalid/revoked terminal precedence; SAS cannot imply current cross-sign/device chain; missing revocation evidence cannot promote trust.
- Prove room navigation preserves immutable origin presentation while account/session/origin-room invalidation fails closed; mutations require exact account/homeserver/room/device/profile/generation.
- Prove safe descriptions and unsupported accessibility semantics contain no secret classes.

### Commit 2 — `feat(matrixrtc): bind trust and lifecycle contracts`

- Paths: `Sources/ZenithMacOSClientCore/MatrixRTCSecurityContract.swift`, I03 ledger rows.
- Add peer trust classifier, secret-kind ownership metadata without secret values, immutable origin lifecycle evaluator, and typed accessible unsupported presentation.
- Preserve future top-right affordance + Messages-like trailing-inspector decisions as presentation contract only.
- Keep the policy for cross-signed but not locally verified devices explicitly unresolved; the classifier grants no media-key authority.

## Acceptance

- [ ] Five required trust terms remain semantically distinct.
- [ ] Invalid and revoked evidence fail closed and cannot be overridden.
- [ ] No secret value/raw authorization type can enter public qualification evidence.
- [ ] Navigation cannot silently rebind account/room authority.
- [ ] Unsupported reasons expose title, description, accessibility label, and hint without UI implementation.
- [ ] Product decisions are preserved as future contract, not current capability.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MatrixRTCSecurityContractTests`
- `python3 scripts/verify_matrixrtc_contract.py`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
- `git diff --check`

## Non-claims

No device is authorized for media keys by this issue; no call is preserved at runtime; no UI, MatrixRTC session, sender-key distribution, transport, or permission behavior is implemented.

## Stop conditions

Stop if trust classification needs unowned SDK evidence, if secret-bearing values enter the types/tests, if navigation semantics require runtime session behavior, or if the unresolved media-key policy is guessed.

## Allowed paths

`Sources/ZenithMacOSClientCore/MatrixRTCSecurityContract.swift`, `Tests/ZenithMacOSClientCoreTests/MatrixRTCSecurityContractTests.swift`, `docs/issues/matrixrtc-step1/**`.

## Stacked PR base

Branch `feat/matrixrtc-trust-origin-contract`; base `feat/matrixrtc-qualification-evaluator` at I02's exact final head.
