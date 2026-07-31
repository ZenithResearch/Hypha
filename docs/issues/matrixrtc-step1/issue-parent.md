# Initiative: qualify Hypha's MatrixRTC contract profile (Step 1 only)

## Owning repo

`ZenithResearch/Hypha`

## Objective

Qualify one exact open-MSC MatrixRTC proposal snapshot, bind it to explicit SDK/server/security/product evidence, and prove the current Hypha artifact and production deployment are unsupported without legacy fallback.

## Dependencies

- `origin/main@a6f425b91946b3177410abcadc2155bbc58feff7`
- Pinned SDK source `f4889ec898e77d8b8c9013adadd77f3d0901fc2d`
- Current upstream SDK evidence `43565c555072cc8002450ece96bd5a90e2b4a0b5`
- Nine open MSC heads and digests recorded by I01, including mandatory MSC4354 and MSC4518 dependencies

## Complexity

- Total: 21
- Intrinsic: 21
- Existing: 8
- Remaining: 13
- Angles: protocol 8; SDK 5; security/privacy 5; product/accessibility 3; QA/docs 3

## PR boundary

Coordination initiative only. It authorizes no direct implementation PR and no direct commits. Execution occurs exclusively through the four child issues below.

## Commit specs

No commits are authorized by this parent. Each child owns its exact commit train.

## Child DAG

- [I01 — source snapshot/profile and deterministic integrity gates](https://github.com/ZenithResearch/Hypha/issues/7)
- [I02 — fail-closed qualification evaluator and fixtures](https://github.com/ZenithResearch/Hypha/issues/8)
- [I03 — device-trust, secret, origin, and accessibility contracts](https://github.com/ZenithResearch/Hypha/issues/9)
- [I04 — public docs/provenance/CI/case-study reconciliation](https://github.com/ZenithResearch/Hypha/issues/10)

Dependency chain: I01 → I02 → I03 → I04.

## Acceptance

- [ ] Every child remaining complexity is <=3.
- [ ] Every child has one reviewable stacked PR.
- [ ] Every exact head has green required CI and APPROVE/MERGE_READY verdicts from spec, protocol, security/privacy, product/accessibility/QA, docs/quality, and Lead review lanes.
- [ ] The fictional July 2026 release-style profile label does not survive current governing surfaces.
- [ ] Current production remains typed unsupported.
- [ ] Final case study and residual Steps 2–6 estimates are complete.
- [ ] No PR is merged; no issue is manually closed; Step 2 is not started.

## Verification

See `docs/issues/matrixrtc-step1/master-dag.md` and `execution-ledger.md`; each child pins its commands.

## Non-claims

No native MatrixRTC session, media, sender-key machinery, LiveKit transport, permissions, call UI, or production RTC readiness is implemented or proven.

## Stop conditions

Stop and harden the DAG if an MSC/source pin cannot be verified, a child exceeds remaining complexity 3, a repo boundary changes, a secret-bearing/live credential probe becomes necessary, or any child would implement Step 2.

## Allowed paths

None directly. Child issues own all repository paths.

## Stacked PR base

None; coordination-only initiative.
