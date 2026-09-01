# Hypha User Manual

This manual describes the user-visible Hypha experience on the current source branch. Release notes remain authoritative for packaged builds.

## Connect to a homeserver

Hypha connects to a Matrix homeserver selected by the user or supplied as the deployment default. A previously saved homeserver always wins over a newer packaged default.

Private Tailscale homeservers appear with **Connect through Tailscale** and **Open Tailscale** actions. Hypha does not join a tailnet or receive a Tailscale credential on the user's behalf. The device must already be authorized in the relevant tailnet.

Manual HTTPS homeserver entry remains available for other Matrix deployments.

## Sign in and restore a device

Sign in with a Matrix account and password or resume a saved Hypha account. Saved passwords live in the platform-protected credential store. Matrix access tokens, encryption databases, recovery material, and account passwords are never stored in room state.

Each Mac, iPhone, or iPad is its own Matrix device. Device verification and Secure Backup recovery establish trust and restore encrypted history; copying another device's local database is not supported.

## Rooms and chat

The selected room keeps its content surface in the main window. Chat opens contextually without replacing the room dashboard. Room names, membership, and encrypted messages are synchronized through Matrix.

## Repository content

A joined non-Space room supports an authoritative set of zero to 42 repositories. Existing one-repository rooms migrate into the collection while retaining a derived singular compatibility mirror for older Hypha clients.

- Remote repository identity, requested ref, resolved immutable commit, and output coordinates are shared through Matrix room state.
- Each device may add its own attachment-scoped local checkout.
- Local paths, security-scoped bookmarks, build commands, build logs, caches, and the global GitHub credential remain device-local.
- Existing verified output opens from the room without running a build.
- **Rebuild** is separate, local, explicitly confirmed, cancellable, and rollback-safe.
- `out/out.json` can declare ordered artifacts or opt into additive recognized-file discovery.

See [the repository output contract](repository-output-contract.md) for the writer format.

## Attach up to 42 repositories

A room supports a repository set containing from zero to 42 attachments. A room with one repository keeps the familiar compact presentation and legacy compatibility.

### Attach a repository

1. Open the room's **Repositories** control.
2. Choose **Attach repository**.
3. Select a repository available through the global GitHub connection or enter its supported remote URL.
4. Confirm the repository name, requested branch or ref, and output contract.
5. Attach an optional local checkout only when local fallback or rebuilding is needed.

The repository counter shows the current capacity, such as **3 / 42 repositories**. Hypha prevents a forty-third attachment before sending room state.

The global GitHub connection is configured once in Settings. After GitHub verifies a fine-grained token, Hypha stores it in the device-only Keychain so every room can reuse it after relaunch; Disconnect removes it. Hypha never writes that credential, a local path, or a build command into Matrix.

### How repository content is resolved

Hypha prefers a verified remote output for the repository revision recorded by the room. If that output is temporarily unavailable, Hypha may use a verified cached copy and then a user-selected local `out/` directory as a lower-priority fallback.

Hypha does not automatically run a build when attaching or opening a room. Existing output is displayed immediately. **Rebuild** is a separate, explicit action and is available only for a user-selected local checkout after the exact command is reviewed and confirmed.

Every repository card shows where its current content came from:

- **Remote** — resolved from the recorded repository revision;
- **Cached** — previously verified bytes for that same revision;
- **Local fallback** — read from the selected local checkout; or
- **Rebuilt locally** — produced by the last explicitly confirmed rebuild.

### Assets

Every renderer-recognized output allowed by the repository’s output contract appears in the room’s **Assets** view. Assets are gallery cards arranged in one horizontal row per repository; every card displays its preserved path so nested outputs remain understandable without flattening identity.

The path below each repository's `out/` directory is preserved exactly:

~~~text
InvestorDeck/
  slides/deck.pptx
  notes/speaker-notes.md

Research/
  reports/market.pdf
  data/results.json
~~~

The physical `out/` directory is treated as that repository's asset root and is not shown as another folder level. Hypha keeps the repository identity internally, so two repositories may both contain `reports/summary.pdf` without colliding.

Opening a card uses Hypha's validated file-type-to-renderer registry. Examples include:

- `.pptx` and `.ppsx` → slideshow;
- `.pdf` → PDF;
- `.html` → bounded web preview;
- supported images → image viewer;
- `.md` → rendered Markdown; and
- `.txt`, `.json`, and `.log` → text.

Filename extensions and `out.json` declarations are hints. Remote and cached files must pass byte or container classification before Hypha presents them.

### Repository states

Each repository is independent. One unavailable repository does not remove healthy assets from the room.

Expected states include:

- available;
- refreshing remote revision;
- cached and offline;
- local fallback;
- local checkout required;
- rebuild available;
- rebuilding;
- invalid output contract; and
- unavailable.

The last successful asset snapshot remains visible and is marked stale when a refresh fails.

## Design the room Canvas with Hermes

The standard native room remains available for every room. Hypha includes the sandboxed Canvas host, capability bridge, framework-neutral SDK, local preview, credential-free Hermes handoff, and shared content-addressed reference. Hermes remains the authoring agent rather than receiving app authority.

The authoring workflow is:

1. In **Canvas actions**, choose **Copy Hermes design brief**.
2. Give that sanitized room/repository/Asset packet plus the `hypha-room-designer` profile and Canvas SDK to Hermes, then describe the desired layout and interaction.
3. Hermes builds in an isolated workspace using local HTML, CSS, ECMAScript modules, and optional Rust compiled to WebAssembly.
4. Choose **Preview local template…** and select the package directory. Hypha validates its manifest, digest, entry point, paths, file types, capabilities, and offline policy before loading it.
5. Review the source label, SDK version, capability count, and preview. Keeping this preview is a device-local personal layout.
6. To share it, publish the package inside an attached repository’s `out/` tree and enable recognized-file discovery so `hypha-room-template.json` is a verified remote Asset.
7. Select that manifest card in **Assets**, return to Canvas, then choose **Publish selected Canvas Asset**. Hypha writes only the immutable repository ID, path, commit, and package digest to Matrix.
8. Choose **Open standard room** at any time to bypass the custom Canvas immediately.

Templates may contain local HTML, CSS, ECMAScript modules, and WebAssembly. Rust is an authoring language and must be compiled to WebAssembly before Hypha loads it. A template cannot load arbitrary native Rust into Hypha.

### Canvas permissions

The first canvas API is read-oriented. A validated template may request only declared capabilities such as:

- read room metadata;
- list repositories;
- list and read validated assets;
- ask Hypha to open an asset in its native viewer; and
- save local layout state for that room.

Templates do not receive Matrix tokens, GitHub credentials, arbitrary filesystem access, build execution, unrestricted network access, or direct room mutation. A custom canvas failure never prevents access to the native Assets view or chat.

## Privacy and security

- Repository URLs and non-secret output coordinates may be shared in Matrix room state.
- GitHub credentials are global, device-local secrets.
- Local repository paths, bookmarks, build commands, and build logs remain device-local.
- Remote output never supplies an executable build command.
- A local build requires an explicit user gesture and confirmation.
- HTML artifacts and custom room canvases use separate security boundaries.
- The ordinary HTML artifact viewer remains non-scriptable.
- A room canvas receives only its declared, versioned Hypha capabilities.
- Hypha rejects path traversal, absolute paths, symlink escapes, unsupported file types, and template bundles whose digest or entry point does not match their manifest.

## Troubleshooting

### A repository has no Assets

Confirm that the repository revision contains an `out/` directory, the output contract permits recognized-file discovery, and at least one file maps to a supported viewer. A local checkout can be attached as fallback without running a build.

### Hypha says a local checkout is required

The remote output and verified cache are unavailable. Choose the corresponding local repository checkout. Hypha saves only a security-scoped local bookmark.

### Rebuild is unavailable

Rebuild requires a selected local checkout and a local command entered by the user or read from that local checkout's `out/out.json`. Matrix room state and remotely loaded manifests cannot enable it.

### A custom canvas does not open

Use **Open standard room**. Check the template's integrity result, SDK version, requested capabilities, and entry point. Repository assets and chat remain available independently of the custom layout.

### An asset opens in the wrong viewer

Report the file, detected media/container type, and selected renderer without sharing private content. Hypha's byte classifier and renderer registry—not the filename alone—own the final route.
