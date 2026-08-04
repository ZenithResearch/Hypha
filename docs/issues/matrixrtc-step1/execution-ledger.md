# MatrixRTC Step 1 execution ledger

Status: ACTIVE
Last reconciled base: `a6f425b91946b3177410abcadc2155bbc58feff7`
Recovery rule: preserve all commits and dirty files; never reset, clean, rewrite, merge, close issues, or start Step 2.

Current-state authority: live [PR #11](https://github.com/ZenithResearch/Hypha/pull/11) head and GitHub check/review APIs. This committed ledger records historical completed checkpoints only; it never promotes a hosted result or review verdict to the moving current head. Exact-head verdicts belong on the PR as external immutable evidence, avoiding a commit that invalidates its own SHA claim.

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
| I01 | [#7](https://github.com/ZenithResearch/Hypha/issues/7) | `feat/matrixrtc-contract-profile` / live PR head | [#11](https://github.com/ZenithResearch/Hypha/pull/11) / `main` | historical local results are recorded below | live PR #11 check API | live PR #11 review API and external exact-head verdict evidence | active; do not merge |
| I02 | [#8](https://github.com/ZenithResearch/Hypha/issues/8) | `feat/matrixrtc-qualification-evaluator` / PENDING | PENDING / I01 | pending | pending | pending | blocked |
| I03 | [#9](https://github.com/ZenithResearch/Hypha/issues/9) | `feat/matrixrtc-trust-origin-contract` / PENDING | PENDING / I02 | pending | pending | pending | blocked |
| I04 | [#10](https://github.com/ZenithResearch/Hypha/issues/10) | `feat/matrixrtc-contract-reconciliation` / PENDING | PENDING / I03 | pending | pending | pending | blocked |

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
