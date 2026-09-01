# Multi-repository Rooms, Assets, and Canvas Implementation Plan

> **Status:** Draft specification and implementation plan. This document does not claim that the described feature is implemented.
>
> **For Hermes:** Implement one task at a time. Run contract review before code review for every task that changes Matrix state, `out.json`, template manifests, or the canvas bridge.

**Goal:** Evolve Hypha's existing single-repository room into a backward-compatible repository set of at most 42 attachments, project validated output files into a stable room Assets graph, and let users create local or repository-published room canvases with Hermes through a sandboxed, capability-versioned API and component SDK.

**Architecture:** Keep Matrix room state as the shared repository identity layer and keep secrets, local checkouts, builds, caches, and personal layout state device-local. Add one collection model with a legacy primary mirror, a per-attachment local-binding store, an immutable remote-output cache, a validated asset index, and a separate custom-canvas runtime. The native Assets surface is always authoritative and remains available when a custom template fails.

**Tech stack:** Swift 6-compatible SwiftPM, SwiftUI, Matrix Rust SDK adapter, URLSession/provider adapters, Security.framework/Keychain, security-scoped bookmarks, WKWebView with non-persistent storage and custom schemes, static HTML/CSS/ES modules, WebAssembly, a framework-neutral JavaScript/TypeScript SDK, and Rust-to-WASM bindings.

---

## Locked product decisions

1. A joined non-Space room may contain zero to 42 repository attachments.
2. A single-repository room retains today's presentation and legacy compatibility.
3. Repository membership is one atomic Matrix state value rather than 42 independently racing state events.
4. The authoritative collection uses a new event type, `ca.zenithresearch.hypha.repositories`, with state key `room`. An older client therefore cannot erase the collection by writing its singular state.
5. The existing event type `ca.zenithresearch.hypha.repository` and state key `primary` remain a derived compatibility mirror containing only the primary attachment.
6. A version-two empty collection is the tombstone for removing the final repository; the legacy mirror is cleared with empty content so older clients fail closed instead of reopening stale content.
7. Collection and legacy-mirror writes are reconciled explicitly. The collection is authoritative whenever it exists.
8. Attachment IDs, not repository URLs, are stable identity. The same repository may be attached at different refs when the user does so deliberately.
9. The 42-item limit is enforced by models, decoders, writers, UI, fixtures, and encoded-state-size checks.
10. GitHub credentials are configured once globally, stored only in the platform credential store, and never copied into a room attachment or local binding.
11. Remote verified output has priority. A verified cache and then a selected local `out/` directory are lower-priority fallbacks.
12. Hypha never runs a build merely because a room is opened, attached, refreshed, or missing output.
13. **Rebuild** is an explicit local action with command review, confirmation, cancellation, rollback, and a visible result.
14. Every repository's `out/` directory is its asset root. Relative paths are preserved and never flattened across repositories.
15. Asset identity is the tuple `(room_id, attachment_id, relative_path, content_digest)`.
16. A file becomes an Asset only after the path boundary and renderer classification succeed.
17. `out.json` metadata and filename extensions are hints; byte/container evidence is authoritative for remote or cached files.
18. Existing version-two manifests remain declared-only unless they opt into additive recognized-file discovery. This prevents a client update from exposing outputs that an existing writer intentionally omitted.
19. The standard native room and Assets view are permanent fallbacks.
20. The ordinary HTML artifact viewer remains non-scriptable. Custom templates use a separate WKWebView runtime and security policy.
21. Rust template source runs only after compilation to WebAssembly. Native dynamic libraries and arbitrary executables are forbidden.
22. The canvas bridge is capability-versioned, read-oriented, and framework-neutral.
23. Version one of the bridge exposes no Matrix mutation, Git mutation, build execution, agent execution, credential access, or general network capability.
24. Templates are local packages during authoring and preview. A shared template is published as a content-addressed asset in an attached repository; raw template markup is not stored directly in Matrix state.
25. Hermes receives room/asset metadata and SDK documentation, never Matrix or GitHub secrets.
26. Template validation and preview complete before a room administrator publishes a shared template reference.

## Current baseline

The current `origin/main` implementation has the following relevant behavior:

- `MatrixRoomRepositoryAttachment` stores one attachment at event type `ca.zenithresearch.hypha.repository` and state key `primary`.
- The room state shape contains `v`, `repository`, `name`, `output_directory`, and `manifest`.
- `HyphaRoomRepositoryLocalBindingStore` keys one security-scoped bookmark and build command by room ID.
- `HyphaArtifactOutputResolver` supports version-one manifests, version-two declared artifacts, and discovery when no manifest is present.
- A version-two `artifacts` array is currently authoritative; undeclared supported files do not appear.
- The format registry maps PowerPoint, PDF, HTML, images, Markdown, and text-like files to viewers.
- Builds already use an output snapshot and rollback boundary and require local confirmation.
- The current HTML artifact preview disables JavaScript, uses non-persistent web storage, denies network navigation, and confines reads to its bundle root.
- GitHub is configured globally, but the temporary token fallback is currently held only for the app session.
- Remote repository verification does not yet materialize `out/` automatically.

The feature therefore requires more than changing a singular property to an array. It adds persisted migration, remote output materialization, durable credential policy, an asset graph, and a second bounded web runtime.

## Terminology

- **Repository set:** the atomic shared list of zero to 42 room attachments.
- **Attachment:** one remote repository identity plus its requested ref and fixed output coordinates.
- **Primary attachment:** the repository mirrored to older single-repository clients.
- **Materialization:** bytes resolved for an attachment from remote, cache, or local fallback without building.
- **Asset:** one validated renderer entry point beneath an attachment's output root.
- **Asset graph:** the repository-grouped, path-preserving room projection consumed by native UI and canvases.
- **Canvas:** a custom room presentation package hosted by Hypha in a dedicated sandbox.
- **Template package:** a content-addressed static bundle containing the canvas entry point, dependencies, and manifest.
- **Component SDK:** framework-neutral components and bindings that call the versioned canvas bridge.

---

## Contract A: Matrix repository set

The authoritative collection is stored at event type `ca.zenithresearch.hypha.repositories` and state key `room`.

~~~json
{
  "v": 2,
  "primary": "investor-deck",
  "repositories": [
    {
      "id": "investor-deck",
      "repository": "https://github.com/ZenithResearch/InvestorDeck",
      "name": "InvestorDeck",
      "output_directory": "out",
      "manifest": "out.json",
      "requested_ref": "main",
      "resolved_commit": "0123456789abcdef0123456789abcdef01234567"
    }
  ]
}
~~~

Rules:

- `v` must equal `2`.
- `repositories` contains zero to 42 entries.
- Every `id` is unique and matches `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`.
- Non-empty collections require `primary` and it must name an entry.
- Empty collections omit `primary`.
- Repository URLs are normalized before comparison and encoding.
- `requested_ref` is a user-readable branch, tag, or commit request.
- `resolved_commit`, when present, is a full immutable commit identifier verified by the provider.
- Output coordinates are strict relative paths with current defaults `out` and `out.json`.
- The encoded event stays below an explicit conservative size budget in addition to the 42-entry limit.
- Unknown additive fields are ignored. Unknown versions fail closed.

The existing singular event at `ca.zenithresearch.hypha.repository` / `primary` remains the compatibility mirror. For a non-empty collection, it contains the unchanged current version-one shape derived from the authoritative primary attachment:

~~~json
{
  "v": 1,
  "repository": "https://github.com/ZenithResearch/InvestorDeck",
  "name": "InvestorDeck",
  "output_directory": "out",
  "manifest": "out.json"
}
~~~

New readers prefer the collection event and fall back to the singular event only when no collection event exists. New writers send the collection first, then reconcile the derived singular mirror. If mirror delivery fails, the collection remains authoritative and Hypha exposes a retryable compatibility-mirror warning rather than rolling back or guessing.

An old client may update the singular mirror, but it cannot overwrite the collection. New Hypha detects mirror divergence and requires an explicit operator choice to replace the primary from that legacy value or restore the derived mirror; it never merges the legacy write automatically.

Removing the final repository writes `{"v":2,"repositories":[]}` to the collection event and empty content to the singular event. Old readers then fail closed without retaining stale repository content.

## Contract B: local repository bindings

Introduce persistence version two:

~~~json
{
  "!room:example.org": {
    "investor-deck": {
      "bookmark": "<opaque security-scoped bookmark>",
      "build_command": "npm run build"
    }
  }
}
~~~

Rules:

- The new defaults key is `ca.zenithresearch.hypha.room-repository-bindings.v2`.
- Bookmarks and build commands remain device-local and attachment-scoped.
- A version-one room binding migrates only when the room normalizes to exactly one attachment.
- Migration verifies bookmark resolution, writes v2, and retains v1 until v2 is successfully read after relaunch.
- Removing an attachment deletes only its local binding after Matrix accepts the shared mutation.
- A local binding never changes the shared requested ref or resolved commit.

## Contract C: `out/out.json` recognized-file discovery

Add an optional version-two field:

~~~json
{
  "version": 2,
  "asset_discovery": {
    "mode": "recognized"
  },
  "primary": "deck",
  "artifacts": [
    {
      "id": "deck",
      "path": "slides/deck.pptx",
      "title": "Quarterly deck",
      "viewer": "slideshow"
    }
  ],
  "path": "slides/deck.pptx",
  "format": "pptx",
  "viewer": "quickLook"
}
~~~

Semantics:

- Omission preserves current version-two declared-only behavior.
- `mode: recognized` adds every supported, validated entry point beneath `out/`.
- Declared artifact metadata overlays the discovered entry with the same relative path.
- Declared artifact IDs remain stable; discovered-only IDs are deterministic path-derived IDs.
- The declared primary remains primary.
- `out.json` never becomes an Asset.
- Files used only as HTML/canvas bundle dependencies are not promoted unless independently recognized.
- Unsupported files may exist only as bounded bundle dependencies and never receive a viewer.
- Version-one behavior remains unchanged and unknown discovery modes fail closed.

The JSON Schema, Swift decoder, semantic resolver, canonical example, fixtures, and documentation change together.

## Contract D: room Asset model

~~~json
{
  "id": "investor-deck:slides/deck.pptx",
  "attachment_id": "investor-deck",
  "path": "slides/deck.pptx",
  "title": "Quarterly deck",
  "format": "pptx",
  "media_type": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  "renderer": "slideshow",
  "content_digest": "sha256:...",
  "source": {
    "kind": "remote",
    "resolved_commit": "0123456789abcdef0123456789abcdef01234567",
    "stale": false
  }
}
~~~

Rules:

- `path` is relative to that attachment's output root.
- Display trees group by attachment and preserve every path segment below `out/`.
- `id` is stable within an attachment/ref snapshot; `content_digest` distinguishes revisions.
- Remote and cached assets require byte/container preflight.
- Local assets use the same path, symlink, and renderer compatibility checks.
- Asset snapshots are immutable. A failed refresh preserves the last successful snapshot as stale.
- Configurable count, total-byte, per-file, path-depth, and bundle budgets protect indexing. The user-facing 42-repository limit is not a file-system denial-of-service control.

## Contract E: remote materialization

Resolution order:

1. Fetch and validate output for the room's current `resolved_commit`.
2. Use an immutable verified cache for that same commit when the remote is unavailable.
3. Use a selected local checkout's existing `out/` as lower-priority fallback.
4. Offer **Rebuild** only through a selected local checkout after an explicit action.

Requirements:

- Resolve mutable refs to immutable commits before bytes become current.
- Refresh shared state only after successful resolution and validation.
- Key caches by normalized repository, commit, output directory, manifest, and contract revision.
- Store digests and safe provenance, never credentials or authorization headers.
- Stage and validate downloads before atomic promotion.
- Reject redirects across unapproved origins, path traversal, link escapes, unsupported modes, and budget violations.
- Never pull, reset, clean, or modify the user's selected local checkout.
- A failed remote refresh never triggers a build.

## Contract F: room canvas template

Package manifest:

~~~json
{
  "schema": "hypha.room-template.v1",
  "entry": "index.html",
  "sdk_version": "1",
  "capabilities": [
    "room.read",
    "repositories.list",
    "assets.list",
    "assets.read",
    "viewer.open",
    "layout_state.read",
    "layout_state.write"
  ],
  "integrity": {
    "algorithm": "sha256",
    "digest": "..."
  }
}
~~~

Shared templates use a separate Matrix state event:

- event type: `ca.zenithresearch.hypha.room_template`;
- state key: `active`.

~~~json
{
  "v": 1,
  "source": {
    "kind": "repository_asset",
    "repository_id": "room-layout",
    "path": "templates/room/hypha-room-template.json",
    "resolved_commit": "0123456789abcdef0123456789abcdef01234567",
    "sha256": "..."
  }
}
~~~

The shared reference contains no markup, secret, local path, or build command. A personal override may select a different validated local package without mutating room state.

Package rules:

- Entry/dependency paths stay below one package root.
- Packages may contain HTML, CSS, local ES modules, images, fonts, and WASM.
- Rust source is compiled to WASM before validation and is never executed directly.
- Remote scripts/styles, unrestricted fetch, popups, downloads, top navigation, file URLs, dynamic native code, `eval`, and unsigned extensions are forbidden.
- Digest, SDK major, entry point, dependency graph, and capabilities are verified before load.
- Any failure falls back to the standard room without removing native Assets or chat.

## Contract G: canvas bridge

The transport is versioned request/reply JSON over a narrow native WKWebView message handler. The canonical contract is language-neutral; TypeScript and Rust/WASM packages are bindings.

Request:

~~~json
{
  "v": 1,
  "id": "request-uuid",
  "method": "assets.list",
  "params": {
    "repository_id": "investor-deck",
    "prefix": "slides/"
  }
}
~~~

Success:

~~~json
{
  "v": 1,
  "id": "request-uuid",
  "ok": true,
  "result": []
}
~~~

Failure:

~~~json
{
  "v": 1,
  "id": "request-uuid",
  "ok": false,
  "error": {
    "code": "capability_denied",
    "message": "The template did not declare assets.list."
  }
}
~~~

Version-one methods:

- `room.get_metadata`;
- `repositories.list`;
- `assets.list`;
- `assets.get_metadata`;
- `assets.get_url`;
- `viewer.open`;
- `layout_state.get`; and
- `layout_state.set`.

Rules:

- Every method maps to one declared capability and bounded parameter/result schema.
- Asset URLs are opaque, short-lived, room-scoped custom-scheme URLs.
- `viewer.open` requires a recent trusted user gesture.
- Layout state is local, template-digest-scoped, bounded, and non-secret.
- Templates never receive local filesystem paths.
- Unknown methods, malformed envelopes, duplicate request IDs, excessive rate/size, and expired URLs fail closed.
- Calls cancel on room, account, template, or web-view changes.
- Logs retain method/error class and timing only, never identifiers, paths, content, or payloads.

## Component SDK boundary

Create the SDK in Hypha first. Do not make ZenithUI responsible for Matrix, repositories, assets, or bridge state.

Initial framework-neutral components:

- `<hypha-room-header>`;
- `<hypha-repository-status>`;
- `<hypha-asset-gallery>`;
- `<hypha-asset-card>`; and
- `<hypha-viewer-link>`.

The package contains a small ESM client with TypeScript declarations, Web Components and token-driven CSS, a Rust crate exposing equivalent calls through WASM bindings, local fixtures, a static preview host, and generated API reference.

Promote stable visual primitives into ZenithUI only after the default Hypha canvas proves their API, focus behavior, themes, reduced motion, and accessibility. Hypha business logic remains in Hypha.

## Hermes room-designer profile

The profile receives the user's prompt, approved room/repository/Asset metadata, canvas API and SDK documentation, accessibility requirements, template schemas, and local validation commands. It never receives Matrix or GitHub secret bytes.

The profile must:

1. Build in an isolated template workspace.
2. Use only approved local dependencies.
3. Compile Rust to WASM before preview.
4. Declare the smallest capability set.
5. Run schema, path, integrity, CSP, accessibility, and responsive checks.
6. Present a preview and capability summary.
7. Export a deterministic package.
8. Publish only after the user confirms the repository and room-state update.

---

## User experience specification

### Room content modes

The room content header offers:

- **Canvas** — active custom template or standard room canvas;
- **Assets** — native repository-grouped gallery and folders; and
- **Repositories** — attachments, status, local binding, refresh, and rebuild.

These are room content modes, not global sidebar tabs. Contextual chat remains unchanged.

### Repository manager

- Header shows `Repositories N / 42`.
- Each repository card shows name, remote, requested ref, resolved revision, source, asset count, and error/stale state.
- **Attach repository** becomes unavailable at 42.
- Primary selection is explicit.
- Removal previews affected Assets and template references.
- Removing a template dependency requires replacement or standard-room fallback.

### Assets

- Every available Asset is a gallery card in a row-based adaptive grid.
- Folder navigation preserves paths below each `out/` root.
- One repository may suppress redundant grouping; multiple repositories always retain identity.
- Primary appears first without losing its natural tree position.
- Selection uses Asset identity, never temporary file URLs.
- All opens use the centralized renderer registry.
- Loading, loaded, loaded-empty, partial, failed, and stale states are distinct.

### Rebuild

- Existing output opens without building.
- **Rebuild** requires a local binding and command.
- Confirmation shows the exact command, repository identity, and output destination.
- Progress, cancel, success, failure, rollback, and outcome-unknown are explicit.
- Success re-indexes only that attachment and never mutates shared repository membership automatically.

### Canvas

- The native standard room remains default until a template validates.
- **Design room** opens the Hermes handoff with the correct profile/skills.
- Preview labels local/shared source and capabilities.
- **Publish to room** requires room-state authority.
- **Use as personal layout** stays local.
- **Open standard room** bypasses templates immediately.
- Template loading never blocks chat, repository management, or native Assets.

### Accessibility and responsive behavior

- Native and SDK controls have semantic labels, keyboard routes, visible focus, and appropriate touch targets.
- The gallery reflows at phone, tablet Split View, and desktop widths.
- Templates honor exposed contrast, reduced-motion, and text-scale preferences.
- The standard room remains the accessibility fallback.

---

## Implementation tasks

### Task 1: Freeze compatibility in executable fixtures

**Objective:** Capture current singular room state, local binding, `out.json`, renderer, and UI behavior before adding new shapes.

**Files:** `HyphaRepositoryOutputTests.swift`, `HyphaRepositoryUISourceContractTests.swift`, new repository-state fixtures, and `docs/repository-output-contract.md`.

**Steps:**

1. Add exact version-one Matrix envelope and bare-content fixtures.
2. Add current local-binding v1 fixtures.
3. Lock v1/v2 `out.json` behavior, including declared-only v2.
4. Lock viewer mappings and path/symlink rejection.
5. Prove an old one-repository room normalizes without behavior change.

**Stop condition:** Do not write version-two state until every current stored shape is executable.

### Task 2: Add the normalized repository-set model

**Files:** `HyphaRepositoryOutput.swift` or a focused state-model file, `MatrixChatService.swift`, `MatrixRustSDKChatService.swift`, and tests.

**Steps:**

1. Introduce `MatrixRoomRepositorySet` and descriptor types.
2. Add URL normalization, IDs, primary, 42-item, and encoded-size validation.
3. Prefer the new collection event and fall back to the singular event only when the collection is absent.
4. Write the collection before reconciling the derived singular mirror.
5. Add mirror-divergence detection and explicit repair choices.
6. Add empty collection and cleared-mirror tombstones.
7. Keep singular compatibility adapters for existing application call sites during migration.
8. Test the derived mirror with a frozen v1 decoder and prove a legacy write cannot erase the collection.

### Task 3: Migrate local bindings

**Files:** binding-store implementation, repository sheet, and migration/relaunch tests.

**Steps:**

1. Add the v2 nested store and defaults key.
2. Keep v1 reads and migrate only an unambiguous single attachment.
3. Verify bookmarks before settling migration.
4. Add attachment-scoped save/load/remove.
5. Preserve unrelated bindings on failure.

### Task 4: Make GitHub authentication global and durable

**Files:** Settings GitHub surface, a `HyphaCore` provider credential store, security docs, and Keychain/redaction tests.

**Steps:**

1. Separate credential metadata from secret bytes.
2. Store secret bytes in a device-only Keychain item.
3. Prefer an approved GitHub App/device path; retain a fine-grained-token fallback under the same boundary.
4. Validate identity before save and clear UI secrets before awaiting.
5. Add disconnect/revoke without removing room attachments.
6. Prove no credentials enter events, bindings, caches, logs, or errors.

### Task 5: Materialize and cache remote output

**Files:** repository provider protocol, GitHub adapter, immutable cache, provenance/security docs, and hostile-input tests.

**Steps:**

1. Resolve refs to immutable commits.
2. Fetch only bounded output coordinates.
3. Stage, classify, and validate before atomic cache promotion.
4. Reject origin changes, traversal, link escapes, unsupported modes, and budgets.
5. Persist safe digests/provenance.
6. Fall back to same-commit cache, then local output.
7. Never build in this path.

### Task 6: Add opt-in recognized discovery

**Files:** `out.schema.json`, schema fixtures/example/docs, resolver, and Swift tests.

**Steps:**

1. Add `asset_discovery.mode = recognized`.
2. Keep omission declared-only.
3. Overlay declared metadata over discovery deterministically.
4. Define discovered-only IDs.
5. Exclude manifest and bundle-only dependencies.
6. Add byte/container classification for remote/cache.
7. Run schema and semantic suites.

### Task 7: Build the room Asset graph

**Files:** new `HyphaRoomAsset` and index types, coordinator integration, and collision/stale/budget tests.

**Steps:**

1. Define immutable Asset/snapshot values.
2. Index repositories independently.
3. Preserve attachment/path identity.
4. Merge into a grouped room graph.
5. Preserve stale successful snapshots on refresh failure.
6. Cancel superseded work.
7. Prove cross-repository path collisions are impossible.

### Task 8: Replace singular repository UI and add native Assets

**Files:** `HyphaRoomRepositorySheet.swift`, `HyphaRoomContentView.swift`, `HyphaArtifactViewerView.swift`, app-local cards/gallery/tree/state views, and UI tests.

**Steps:**

1. Add `Repositories N / 42` management and primary selection.
2. Preserve compact one-repository behavior.
3. Add removal-impact confirmation.
4. Render every Asset as a row-based adaptive gallery card.
5. Add grouping, folders, filters, source badges, and stale/partial states.
6. Route opens through the renderer registry.
7. Keep viewer/build controls in room content.

### Task 9: Scope explicit rebuild by attachment

**Files:** repository builder, room content, and concurrency/cancellation/rollback tests.

**Steps:**

1. Scope build state by room and attachment.
2. Show command/root/output before confirmation.
3. Prevent duplicate same-attachment builds.
4. Preserve last good output on failure/cancel.
5. Re-index only the affected attachment.
6. Never label local build bytes as remote-commit output.

### Task 10: Add the custom canvas host

**Files:** dedicated canvas host/controller, template validator/models, custom scheme handlers, and CSP/navigation/resource tests.

**Steps:**

1. Keep artifact-web and canvas-web configurations separate.
2. Use non-persistent storage and one package root.
3. Deny navigation, popups, downloads, file URLs, and general network.
4. Validate entry, dependencies, capabilities, SDK, and digest.
5. Serve template and Asset bytes through separate bounded schemes.
6. Add immediate standard-room fallback.
7. Tear down handlers/calls on context changes.

### Task 11: Implement bridge and component SDK

**Files:** canonical bridge schemas/fixtures, native dispatcher, ESM/TypeScript/Web Components SDK, Rust/WASM crate, and static preview.

**Steps:**

1. Define exact request/response/error/capability schemas.
2. Keep TypeScript and Rust bindings aligned with drift tests.
3. Enforce capabilities, bounds, rates, gestures, and cancellation natively.
4. Add opaque short-lived Asset URLs.
5. Build the five initial token-driven components.
6. Run both clients against identical bridge fixtures.
7. Keep Matrix/repository logic outside components.

### Task 12: Add Hermes authoring and publication

**Repositories:** Hypha owns schemas, SDK docs, validation, preview, and handoff; Hermes Agent owns `hypha-room-designer` and class-level skills.

**Steps:**

1. Define allowed profile tools/input packet.
2. Provide versioned SDK/schema context and deterministic scaffold.
3. Add HTML/CSS/JS/WASM validation commands.
4. Generate capability/accessibility reports.
5. Preview through the production host.
6. Export to a selected attached repository.
7. Commit/push only after confirmation, then update room template state.
8. Prove Hermes never receives credentials.

### Task 13: Run compatibility, security, and rollout gates

**Steps:**

1. Ship v1/v2 readers and v1 binding migration before v2 writes.
2. Ship native Repositories/Assets before custom canvases.
3. Run frozen old-reader compatibility.
4. Exercise 0, 1, 2, 41, 42, and rejected 43 attachments.
5. Exercise duplicates, same repo/different refs, size overflow, removal, and primary replacement.
6. Exercise remote, cache, local, offline, stale, corrupt, cancelled, and rebuild states.
7. Exercise every renderer with classified files.
8. Run malicious archive/path/link/HTML/WASM/bridge/CSP/digest tests.
9. Run full Swift, schema, SDK, accessibility, macOS, iPhone, and iPad checks.
10. Enable v2 writes behind a reversible flag after readers are healthy.
11. Enable shared templates after native Assets and fallback are healthy.
12. Roll back by disabling writers and canvas selection while continuing to read v2 and show the standard room.

---

## Verification matrix

- **Producer:** repository-state writer, `out.json` writers/schema/example, Hermes template producer.
- **Consumer:** frozen old decoder reading the singular mirror, new collection-first decoder, asset index, renderer registry, template validator, bridge.
- **Persisted representations:** v1/v2 Matrix events, v1/v2 local bindings, immutable caches, local layout state.
- **Live artifacts:** public/private repository fixtures, real `out/` trees, PowerPoint/PDF/HTML/image/Markdown/text files, and an HTML/WASM template.
- **Risk:** additive and fallback-backed through a separate authoritative collection plus singular mirror; dual-write delivery can temporarily leave a stale mirror but cannot destroy the collection; empty collection and cleared mirror intentionally fail closed; remote archives and templates add hostile-input boundaries.

## Acceptance criteria

- A room persists 42 repositories and rejects the forty-third before mutation.
- A one-repository room's derived singular mirror remains readable by the frozen old decoder and looks current.
- An old client writing singular state cannot erase or replace the authoritative collection.
- Existing room state/bindings migrate without losing local data.
- No event contains credentials, local paths, bookmarks, commands, or raw templates.
- Global GitHub authentication survives relaunch through Keychain and revokes independently.
- Remote output is preferred; cache and local sources are clear fallbacks.
- Opening/attaching never builds.
- Rebuild is explicit, attachment-scoped, cancellable, and rollback-safe.
- Every opted-in recognized file appears as an Asset with its path preserved.
- Identical paths in different repositories never collide.
- Every Asset routes through classification and the renderer registry.
- One unavailable repository does not hide healthy Assets.
- Native Assets remain complete without a template.
- Hermes-authored HTML/WASM runs only after schema, digest, path, capability, CSP, and SDK validation.
- Rust runs only as compiled WASM.
- Canvas APIs expose no secrets, arbitrary files, builds, agent execution, room mutation, or unrestricted network.
- **Open standard room** immediately recovers from template failure.
- TypeScript and Rust/WASM SDKs pass identical bridge fixtures.
- Full schema, Swift, SDK, renderer, security, accessibility, macOS, iPhone, and iPad checks are green.

## Non-goals

- Arbitrary native Rust, dynamic libraries, shell commands, or plugins in the canvas.
- Turning normal repository HTML artifacts into privileged canvases.
- Automatic builds on attach, open, refresh, cache miss, or template load.
- Credentials in room state, templates, caches, or Hermes context.
- Pulling, resetting, cleaning, or modifying a selected local checkout.
- Flattening multiple output trees into a collision-prone filesystem.
- Making templates a prerequisite for Assets or chat.
- Moving Hypha-specific business logic into ZenithUI.
- A third-party template marketplace or unreviewed remote dependencies in v1.
- Removing the legacy primary mirror before all supported readers migrate.

## Migration risk

The repository collection and `asset_discovery` field are additive and fallback-backed. The separate collection event prevents old singular writers from collapsing the set, but collection/mirror dual delivery can leave a repairable stale compatibility mirror. The empty collection plus cleared mirror intentionally makes old clients fail closed. Durable GitHub authentication expands the local secret lifecycle and requires Keychain/redaction evidence. Remote output materialization and WASM canvases introduce hostile-input boundaries; they remain disabled until byte classification, cache integrity, CSP/scheme confinement, capability enforcement, and standard-room fallback are proven.
