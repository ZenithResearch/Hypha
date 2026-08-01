# MatrixRTC Step 1 execution ledger

Status: I04 FINAL EVIDENCE ACTIVE
Last reconciled base: `a6f425b91946b3177410abcadc2155bbc58feff7`
Recovery rule: preserve all commits and dirty files; never reset, clean, rewrite, merge, close issues, or start Step 2.

Current-state authority: live PR heads and GitHub check/review APIs. This committed ledger records historical completed checkpoints only; it never promotes a hosted result or review verdict to a moving head. Exact-head verdicts belong on each PR as external immutable evidence, avoiding a commit that invalidates its own SHA claim.

## Baseline evidence

- Worktree clean on `feat/matrixrtc-contract-profile` at exact `origin/main`.
- Baseline local: `swift test` — 217 executed, 3 skipped, 0 failures.
- Baseline local: `swift build` — PASS.
- Public-release verifier and mutation tests — PASS.
- Latest push-triggered main CI for exact base — PASS: https://github.com/ZenithResearch/Hypha/actions/runs/30598391301
- Pinned SDK artifact SHA-256: `ca8796d0f065ade3787de2f18693afd940914ce2e35f807ccf479d2f14c5c565`.
- Generated Swift binding SHA-256: `7d823dda5f112ebc60887fc0ff238129b49e0173870ad616978f17b3ace5bdbc`.
- Current upstream SDK inspected: `43565c555072cc8002450ece96bd5a90e2b4a0b5`.
- Current sanitized production probe: well-known has no `m.rtc_foci`; versions has neither `org.matrix.msc4143` flag; unauthenticated stable transport path returns HTTP 404 `M_UNRECOGNIZED`. This is unsupported evidence, not authorization to probe with credentials.

## Train

| Node | Issue | Branch/head | PR/base | Local gates | Hosted CI | Exact-head reviews | State |
|---|---|---|---|---|---|---|---|
| I01 | [#7](https://github.com/ZenithResearch/Hypha/issues/7) | `feat/matrixrtc-contract-profile` / `8a87fbc` | [#11](https://github.com/ZenithResearch/Hypha/pull/11) / `main` | verifier/mutations, 217 tests, build, diff passed | two exact-head checks passed | all specialist + Lead verdicts approved | open, ready, unmerged |
| I02 | [#8](https://github.com/ZenithResearch/Hypha/issues/8) | `feat/matrixrtc-qualification-evaluator` / `40c742c` | [#12](https://github.com/ZenithResearch/Hypha/pull/12) / I01 | focused 37/full 254 tests, build/verifiers/audits passed | two exact-head checks passed | all specialist + Lead verdicts approved | open, ready, unmerged |
| I03 | [#9](https://github.com/ZenithResearch/Hypha/issues/9) | `feat/matrixrtc-trust-origin-contract` / `6de688f` | [#13](https://github.com/ZenithResearch/Hypha/pull/13) / I02 | focused 24/full 278 tests, build/verifiers/audits passed | two exact-head checks passed | all specialist + Lead verdicts approved | open, ready, unmerged |
| I04 | [#10](https://github.com/ZenithResearch/Hypha/issues/10) | `feat/matrixrtc-contract-reconciliation` / live PR head | live stacked PR / I03 | final package gates must pass | live PR check API | live PR external exact-head verdicts | final evidence active; do not merge |

## Recovery checkpoints

- Roundtable synthesized in `roundtable.md`.
- All nine proposal files were independently downloaded at their exact heads and matched their recorded SHA-256 digests.
- The interrupted Commit 2 developer left no shared diff and is treated as failed; no partial work was adopted.
- Additive repair `78dedde` pins MSC4354 and MSC4518, every selected MSC4140 unstable identifier, sticky-map requirements, and exact SDK source evidence without rewriting Commit 1.
- Commit 2 local verification passed offline contract/source/static mutation gates plus the complete existing CI-equivalent package gate.
- Commit 2 implementation head `81c7766a33f547f0113bb0d97eb3078349292c1d` passed both hosted push and pull-request CI. This ledger checkpoint changes the PR head, so all final review lanes and hosted checks bind to the resulting checkpoint head instead.
- Historical head `858fd789152b0781f188b7f346ae02cfc8eeff49` records the additive I01 protocol repair and passed local contract/public-release verifier and mutation suites, 217 Swift tests (3 skipped), Swift build, diff check, and hosted runs [30623549433](https://github.com/ZenithResearch/Hypha/actions/runs/30623549433) and [30623546079](https://github.com/ZenithResearch/Hypha/actions/runs/30623546079). These facts are checkpoint-bound and make no claim about a later head.
- Master DAG and issue packets are authoritative for scope.
- Open PRs do not authorize merge or ordinary downstream readiness; stacked execution is the explicit operator waiver only.
- I01 final exact head `8a87fbcac1eded59b96344019406c63b49841ae1` closed the 11-capability SDK requirement/evidence matrix and passed all exact-head lanes.
- I02 final exact head `40c742cfb9d0a1336f3ca14141ebbf09b6c14d8d` bound expected/observed SDK revision and snapshot digest and passed all exact-head lanes.
- I03 final exact head `6de688fd26fa3e2b817293e4fee1ee12e81eb8f3` delivered the trust, secret metadata, immutable-origin, accessibility, and future inspector contracts and passed all exact-head lanes.
- I04 RED commit `5c41b9cbd1f6942400f13d2f5ecb83502609e0d5` made stale/overclaimed public surfaces fail before reconciliation. Docs commit `6cf5e74f0b50508b0a065ceb4a0dbaa1d01ef568` reconciled governing public claims and exact SDK provenance. Final evidence is head-stable and governed by the live I04 PR.
