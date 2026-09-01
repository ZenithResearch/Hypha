# Hypha Canvas SDK v1

This framework-neutral SDK is the only supported interface between a room template and Hypha. It exposes read-oriented room, repository, and Asset metadata plus device-local layout state. It never exposes Matrix credentials, GitHub credentials, local paths, builds, Git mutation, agents, or general network access.

Templates bundle `src/index.js`, `src/components.js`, and `styles/hypha-canvas.css` inside their validated package. Remote imports are rejected. Normal repository HTML Assets do not receive this bridge.

```html
<link rel="stylesheet" href="./sdk/hypha-canvas.css">
<hypha-room-header></hypha-room-header>
<hypha-asset-gallery></hypha-asset-gallery>
<script type="module" src="./sdk/components.js"></script>
```

The five initial elements are:

- `<hypha-room-header>`
- `<hypha-repository-status>`
- `<hypha-asset-gallery>`
- `<hypha-asset-card>`
- `<hypha-viewer-link>`

`viewer.open` requires a proven WebKit user activation. Use `viewerURL(assetID)` or `<hypha-viewer-link>`; the native host accepts only a real link activation and rejects programmatic navigation.

The Rust crate is dependency-free and defines the exact v1 method vocabulary plus a bounded request encoder suitable for a WASM module. The host application's JavaScript glue owns asynchronous delivery; arbitrary native Rust and dynamic libraries are forbidden.

Package integrity is the SHA-256 of each non-manifest file in lexicographic relative-path order, updating the hasher with `path`, NUL, file bytes, NUL. `hypha-room-template.json` is excluded so its `integrity.digest` does not become self-referential.


## Canonical contracts and authoring

The machine-readable v1 contracts live in `schemas/`:

- `bridge-request.schema.json`
- `bridge-response.schema.json`
- `capability.schema.json`
- `template-manifest.schema.json`
- `template-reference.schema.json`

`fixtures/` contains matching request, success, and typed-error envelopes. The JavaScript/TypeScript and Rust method vocabularies are checked against the request schema so one client cannot silently drift.

Use `hermes/hypha-room-designer.md` with the credential-free packet copied from Hypha’s **Canvas actions** menu. That profile restricts Hermes to an isolated static package and requires explicit confirmation before any repository or room-state publication.

## Validate and preview

Run:

```bash
npm --prefix SDK/HyphaCanvasSDK test
node SDK/HyphaCanvasSDK/scripts/package.mjs /path/to/template --write
```

The packaging command enforces Hypha’s file, type, path, symlink, offline-content, per-file, and package-size boundaries; computes the deterministic package digest; and updates only `integrity` in `hypha-room-template.json`. Hypha repeats validation in the native host before preview or publication.

The initial WCAG token, typography, motion, interaction, and colour-only review is recorded in `accessibility-report.json`. Its required fixes are already reflected in the shipped CSS; product templates still require their own semantic and keyboard review.

Serve `preview/` with any local static server to inspect the five components against a mock bridge. The mock is SDK documentation only; production templates run in Hypha’s non-persistent WKWebView with custom schemes, CSP, rate limits, capability checks, and user-gesture enforcement.
