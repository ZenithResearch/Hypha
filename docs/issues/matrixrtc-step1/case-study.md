# MatrixRTC Step 1 case study

Status: final-evidence snapshot; exact I04 head and final reviews are governed by the live stacked PR

## Outcome

Step 1 qualified one exact, nine-proposal open-MSC MatrixRTC contract profile and encoded deterministic, fail-closed SDK/server qualification, trust, secret, origin, accessibility, and future presentation contracts. It did not implement calling. The current pinned SDK, current upstream SDK evidence, and production deployment remain unsupported.

Selected profile: `ca.hypha.matrixrtc.open-msc-snapshot.2026-07-30.2`

Profile fingerprint: `630c781b782eb94965fb83767a39247f2d127ac31f0c89065f18711b375f8f6d`

No issue or PR was closed or merged. The open stacked train is an explicit execution waiver, not merge authority.

## Executable DAG and complexity

The parent initiative's 21-point score is an aggregate risk estimate and is not added to its children. The non-double-counted executable child total is 16 Fibonacci points.

| Node | Issue | Total | Intrinsic | Existing | Remaining at dispatch | Delivered boundary |
|---|---|---:|---:|---:|---:|---|
| I01 | #7 | 3 | 3 | 1 | 2 | exact source/profile, SDK matrix, offline integrity gates |
| I02 | #8 | 5 | 5 | 2 | 3 | pure fail-closed qualification evaluator and fixtures |
| I03 | #9 | 5 | 5 | 2 | 3 | trust, secret metadata, immutable origin, accessible presentation |
| I04 | #10 | 3 | 3 | 1 | 2 | public reconciliation, static drift gates, final evidence |
| **Executable total** | | **16** | **16** | **6** | **10** | parent aggregation excluded |

Every executable issue remained at residual complexity 3 or lower. At completion, Step 1 executable remaining complexity is zero; runtime MatrixRTC work belongs to Steps 2–6 and is not silently absorbed here.

## Stacked PR evidence

| Node | PR | Exact approved head | Base | Hosted checks | State |
|---|---|---|---|---|---|
| I01 | #11 | `8a87fbcac1eded59b96344019406c63b49841ae1` | `main` | two macOS checks passed | open, ready, unmerged |
| I02 | #12 | `40c742cfb9d0a1336f3ca14141ebbf09b6c14d8d` | `feat/matrixrtc-contract-profile` | two macOS checks passed | open, ready, unmerged |
| I03 | #13 | `6de688fd26fa3e2b817293e4fee1ee12e81eb8f3` | `feat/matrixrtc-qualification-evaluator` | two macOS checks passed | open, ready, unmerged |
| I04 | live stacked PR | live exact head | `feat/matrixrtc-trust-origin-contract` | live PR check API | must remain open and unmerged |

The committed I04 row is intentionally head-stable. Its exact SHA, checks, and final verdicts are posted externally on the live PR so recording them cannot create a new head that invalidates itself.

## Additive delivery train

The train preserved history; no reset, rewrite, force-push, merge, or issue closure was used.

- I01 source/profile and repairs: `64f509b`, `78dedde`, `81c7766`, `1683fe5`, `f42caad`, `ed56766`, `858fd78`, `8c01d94`, with final I01 matrix closure at `8a87fbc` on its branch.
- I02 RED/GREEN and repairs: `7376d28`, `5d8dcb4`, `e1cd1d0`, `40c742c`.
- I03 RED/GREEN: `d1caf64`, `6de688f`.
- I04 RED/docs/evidence: `5c41b9c`, `6cf5e74`, followed by this final-evidence commit.

## Review defects and repairs

1. CTO source review found that the first seven-proposal snapshot omitted mandatory MSC4354 and MSC4518 dependency closure. I01 expanded to nine exact proposal heads and content digests.
2. Protocol review found incomplete MSC4140 routes/flags/capabilities, sticky-event identifiers/ephemeral-map semantics, MSC4195 federation coverage, and bounded-grant comparison evidence. Static and mutation gates were expanded.
3. Docs/Lead review found machine-local paths and moving-head claims in public artifacts. Private paths were removed and GitHub became the live exact-head authority.
4. Product/accessibility review found lifecycle and accessibility semantics present in prose but absent from the machine contract. The future product contract gained typed unavailable fields, passive incoming behavior, dismissal semantics, and immutable origin rules.
5. I02 review found an 11-capability evaluator bound to only seven formal matrix requirements. I01 and I02 were repaired together so all 11 selected requirements and all evidence rows are exact-map checked.
6. I02 security/protocol review required expected/observed SDK source revision and capability-snapshot digest binding. Typed deterministic mismatch reasons now precede capability evaluation.
7. I03 enforced distinct authenticated, cross-signed, locally SAS-verified, invalid, revoked, unknown, and malformed states; revoked/invalid terminal precedence; missing revocation non-promotion; enum-only secret metadata; and six-dimensional origin binding.
8. I04 found stale call-mode, video-first, detached-window, and fictional release-profile language. Governing docs and the canonical vault review now use the exact open-MSC snapshot and accepted audio-first trailing-inspector contract.

Any material repair invalidated prior head-specific verdicts and triggered a fresh review cycle.

## Recovery and process evidence

- The initial protocol roundtable timed out; timeout was treated as no verdict and replaced.
- The long-running Lead process exhausted two 90-iteration budgets. Recovery resumed from live Git/GitHub state without destructive operations.
- Several bounded Dev/Lead/reviewer jobs timed out after leaving either no diff or a preserved, inspectable partial diff. Writers were never duplicated against a dirty worktree.
- Two command safety denials stopped execution. The operator explicitly continued/retried; RED work was preserved and resumed rather than bypassed.
- I03's recovered RED test had two implementation-independent parenthesis errors; they were corrected before the RED commit, and the intended missing-symbol compiler failure was recaptured.
- The temporary 30-minute CTO recovery monitor was recreated and manually anchored after its first schedule failed to advance. It used duplicate-writer and non-destructive Git guards and was removed at operator direction after the overnight recovery window; no Step 1 scheduled job remains.

## Verification evidence

The final package requires all of:

- `python3 scripts/verify_matrixrtc_contract.py`
- `python3 scripts/test_matrixrtc_contract_verifier.py`
- `python3 scripts/verify_public_release.py`
- `python3 scripts/test_public_release_verifier.py`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
- `HYPHA_SIGNING_MODE=adhoc ./build-app.sh`
- `codesign --verify --deep --strict --verbose=2 Hypha.app`
- `git diff --check`
- hosted push and pull-request macOS checks
- independent exact-head protocol/spec, security/privacy, product/accessibility/QA, docs/quality, and Lead verdicts

## Provider telemetry snapshot

Snapshot boundary: provider session rows attributable to Step 1 through the I04 evidence-authoring phase. Final I04 reviewers necessarily occur after the repository snapshot; their exact provider totals belong in the operator's post-approval report. This avoids an infinite self-observation loop where adding reviewer telemetry would create a new head and invalidate those reviews.

Exactly attributable session rows: **65** (64 completed-duration rows and one resumed Lead row whose `ended_at` remained unavailable).

| Provider-reported field | Exact attributable value |
|---|---:|
| Completed session duration | 32,214.336 seconds |
| Messages | 2,471 |
| Tool calls | 1,709 |
| API calls | 720 |
| Input tokens | 5,655,264 |
| Output tokens | 391,500 |
| Cache-read tokens | 62,604,800 |
| Cache-write tokens | 0 |
| Reasoning tokens | 120,933 |

The exact session CSV snapshot had SHA-256 `9deffc2661f7ffd1461cd31b559f6be9d3738412bf206e7cff604a403e55e959`. Fields are reported separately because provider cache accounting must not be added to input/output as a synthetic billing total.

The parent CTO CLI session predates Step 1, so its Step 1-only token segment is not separable in `state.db`. Its full-session row is deliberately excluded from the attributable total rather than guessed. At snapshot it reported 6,875,994 input, 457,280 output, 208,061,440 cache-read, 0 cache-write, and 133,863 reasoning tokens across the larger multi-day session. Those values are context only, not Step 1 consumption.

Attribution query:

```sql
WITH RECURSIVE lineage(id) AS (
  VALUES('20260728_224501_ec52cd'), ('20260731_011523_3a0f8c')
  UNION
  SELECT s.id FROM sessions s JOIN lineage l ON s.parent_session_id = l.id
), selected AS (
  SELECT DISTINCT s.* FROM sessions s
  WHERE (
    s.id IN (SELECT id FROM lineage)
    AND s.id != '20260728_224501_ec52cd'
    AND datetime(s.started_at, 'unixepoch') >= '2026-07-31 07:50:00'
  ) OR s.id LIKE 'cron_7d9bba7cce41_%'
)
SELECT count(*), sum(message_count), sum(tool_call_count), sum(api_call_count),
       sum(input_tokens), sum(output_tokens), sum(cache_read_tokens),
       sum(cache_write_tokens), sum(reasoning_tokens)
FROM selected;
```

Unavailable rather than inferred: task-only parent-session tokens, cost where the provider did not supply authoritative cost, and end time/duration for the resumed Lead row.

## Normalized complexity and revised schedule

Original normalized scores totaled 492: Step 1 80, Steps 2–4 each 91, Step 5 51, and Step 6 88. Step 1 represented 16.3% of the original total. Residual Steps 2–6 total **412** normalized points:

| Residual step | Score | Share of residual |
|---|---:|---:|
| Step 2 — Rust/UniFFI seam | 91 | 22.1% |
| Step 3 — authorization/LiveKit infrastructure | 91 | 22.1% |
| Step 4 — native encrypted audio transport | 91 | 22.1% |
| Step 5 — inspector UI | 51 | 12.4% |
| Step 6 — proof/failure paths | 88 | 21.4% |

The original 20–32 sequential-engineering-day estimate implies 16.7–26.8 days for the 412/492 residual share. Step 1 exposed additional SDK/infrastructure and independent-review rework risk, so the revised planning range applies an explicit 10% risk allowance and rounds to **19–30 engineering days**. This is not a price or staffing promise.

Dependency-adjusted order remains: Steps 2 and 3 in parallel after contract qualification; Step 5 against fakes in parallel; Step 4 integration after SDK and authorization seams; Step 6 packages exact-head negative and production evidence. With work beginning Monday 2026-08-03, 19–30 business days yields **2026-08-27 through 2026-09-11**. Five additional contingency business days yield **2026-09-18**. The original expected window was 2026-08-27 through 2026-09-10 with a 2026-09-17 conservative date, so the evidence-backed revision moves the high and conservative bounds by one day rather than claiming that contract-stage agent parallelism removes runtime/infrastructure risk.

## Non-claims

Step 1 proves no MatrixRTC join or leave, membership publication, sender-key lifecycle, transport grant service, LiveKit authorization, media connection, microphone/camera permission, call UI, interoperability, or production deployment readiness. A transport connection cannot prove Matrix identity or membership. The media-key policy for valid cross-signed peers that are not locally SAS-verified remains unresolved and grants no authority.
