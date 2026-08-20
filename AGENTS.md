# Agent Rules

These rules apply to this repository and all agent sessions within it.

---

## Repeated Dev-Server Module Resolution Failures

For any Next.js/Turbopack app under this directory, repeated user-side `Module not found` / `Can't resolve` traces from `next dev` must be debugged from the import trace first.

Do not keep treating the problem as stale process state, port collision, package-manager cache, or user restart error just because an agent-side `require.resolve`, build, or separate dev server works. If the user immediately reproduces the same trace, inspect the exact source files in the trace and fix the failing import edge.

Standard response pattern:

1. Read the traced source file(s), parent layout/route, package manifest, lockfile, `tsconfig`, and framework config.
2. Compare the dependency model against the import site: npm package, workspace package, `file:` tarball, symlink, or source vendoring.
3. If a bare package import is fragile on an app-shell hot path, prefer a robust local import or properly owned workspace package over repeated relink/reinstall attempts.
4. Keep only one dependency model active. Remove obsolete tarballs, lockfile entries, or package references that preserve a false model.
5. Verify by removing/searching the failing import string when appropriate, then run the user's exact dev command plus targeted tests/build.

This rule generalizes the Gallery Web `@zenith/review-sdk` incident: Node and builds could resolve a vendored `file:` package, but the user's `next dev` repeatedly failed the app-shell bare import. The durable fix was to inspect the traced provider, vendor the SDK runtime as local source, import it by relative path, and remove the stale package/tarball dependency model.

---

## Changelog

Maintain `CHANGELOG.md` in [Keep a Changelog](https://keepachangelog.com) format.

**After each commit**, add an entry under `## [Unreleased]` using the format:

```
- <what changed> — <why it was changed / what problem it solves>
```

Categories: `### Added` · `### Changed` · `### Fixed` · `### Removed`

The *why* is required. The diff shows what changed — the changelog records the
reasoning that won't survive in the code.

Skip entries for: whitespace-only commits, immediately reverted commits,
lock file bumps with no behavioral intent change.

Never promote `[Unreleased]` to a version block without an explicit instruction.

If `CHANGELOG.md` does not exist yet, create it:

```markdown
# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]
```
