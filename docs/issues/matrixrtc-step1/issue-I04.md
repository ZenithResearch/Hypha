# I04: reconcile public MatrixRTC contract claims and final evidence

## Owning repo

`ZenithResearch/Hypha`

## Objective

Reconcile public product/spec/provenance/non-claim surfaces and CI/static gates with the landed Step 1 contracts, then publish the full evidence-backed case study and residual Steps 2–6 complexity without implementing Step 2.

## Dependencies

- Parent initiative: https://github.com/ZenithResearch/Hypha/issues/6
- I03: https://github.com/ZenithResearch/Hypha/issues/9 — exact reviewed head required

## Complexity

- Total: 3
- Intrinsic: 3
- Existing: 1
- Remaining: 2
- Angles: public docs 2; provenance 2; CI/static quality 2; case study/estimation 2

## PR boundary

One documentation/quality/final-evidence PR. It may strengthen static gates but may not implement session/media/UI behavior.

## Commit specs

### Commit 1 — `test(matrixrtc): reject stale and overclaimed contract surfaces`

- Paths: `scripts/test_matrixrtc_contract_verifier.py`, `scripts/verify_matrixrtc_contract.py`, I04 ledger rows.
- Add RED mutation/static tests for fictional profile names, legacy fallback promotion outside generated vendor evidence, stale contradictory call-mode/detached-window claims, missing trust distinctions, missing origin binding, missing accessible unsupported semantics, and docs that claim join/media/production readiness.
- Stop at the intended RED state before docs are reconciled.

### Commit 2 — `docs(matrixrtc): reconcile public contract and provenance`

- Paths: `README.md`, `docs/architecture.md`, `docs/security-model.md`, `Vendor/MatrixRustSDK/PROVENANCE.md`, `docs/matrixrtc/**`, `docs/issues/matrixrtc-step1/**`, and the canonical vault spec (vault edit is separately logged and not committed to this repo).
- Describe Step 1 as contract qualification only; link exact profile/provenance; preserve calls as unimplemented; state current SDK and production unsupported.
- Replace fictional profile wording and supersede contradictory mode/detached-window design with the accepted top-right/trailing-inspector/origin-binding future design.
- Keep cross-signed-unverified media policy unresolved and explicit.

### Commit 3 — `docs(matrixrtc): publish Step 1 case study and residual estimates`

- Paths: `docs/issues/matrixrtc-step1/case-study.md`, `master-dag.md`, `execution-ledger.md`, `review-record.md`, `status.md`.
- Record issue/PR map, exact heads, complexity before/after, critical path, agent roles/recoveries, exact commands/results, defects and repairs, non-claims, external gates, token telemetry, and Steps 2–6 residual normalized complexity.
- Token totals come from `~/.hermes/state.db`; unavailable task baselines are labeled, never invented.

## Acceptance

- [ ] Public docs match landed runtime contract and do not claim Step 2.
- [ ] SDK provenance links the exact gap without claiming selected-profile support.
- [ ] Fictional release-style profile wording is gone from current governing surfaces.
- [ ] CI/static gates reject stale/overclaim drift.
- [ ] Case study and Steps 2–6 estimates are complete and exact-head-bound.
- [ ] Every PR remains unmerged.

## Verification

- `python3 scripts/verify_matrixrtc_contract.py`
- `python3 scripts/test_matrixrtc_contract_verifier.py`
- `python3 scripts/verify_public_release.py`
- `python3 scripts/test_public_release_verifier.py`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
- `HYPHA_SIGNING_MODE=adhoc ./build-app.sh`
- `codesign --verify --deep --strict --verbose=2 Hypha.app`
- `git diff --check`

## Non-claims

No MatrixRTC join/leave, sender-key, LiveKit, mic/camera permission, call UI, media, interoperability, or production deployment proof.

## Stop conditions

Stop if docs would outrun code, token telemetry cannot be attributed, a vault edit would expose private paths publicly, CI requires network/credentials, or any requested correction belongs to Step 2.

## Allowed paths

`README.md`, `docs/architecture.md`, `docs/security-model.md`, `Vendor/MatrixRustSDK/PROVENANCE.md`, `docs/matrixrtc/**`, `docs/issues/matrixrtc-step1/**`, `scripts/verify_matrixrtc_contract.py`, `scripts/test_matrixrtc_contract_verifier.py`, `.github/workflows/ci.yml`; separately, the named canonical vault spec and daily log.

## Stacked PR base

Branch `feat/matrixrtc-contract-reconciliation`; base `feat/matrixrtc-trust-origin-contract` at I03's exact final head.
