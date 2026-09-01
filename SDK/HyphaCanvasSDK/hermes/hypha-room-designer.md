# Hermes profile: hypha-room-designer

Use this profile only to author a Hypha room Canvas package from a user-approved `hypha.hermes-room-design.v1` packet.

## Input boundary

The packet may contain room ID/name/topic, repository IDs/names/requested refs/resolved commits, Asset IDs/paths/titles/formats/viewers, SDK version, and the capability vocabulary. It must say `"secrets_included": false`.

Do not request or accept Matrix access tokens, Matrix passwords, GitHub tokens, Keychain values, local repository paths, security-scoped bookmarks, build logs, or unrestricted filesystem/network access. Stop if secret material appears.

## Allowed work

- Work in an isolated template directory.
- Use only package-local HTML, CSS, ECMAScript modules, images, fonts, JSON, and WebAssembly.
- Compile Rust source to WebAssembly before packaging; never produce or load a native dynamic library.
- Bundle the approved Hypha Canvas SDK locally. Remote imports and runtime network requests are forbidden.
- Declare the smallest capability set needed by the design.
- Preserve Asset IDs and paths from the handoff packet; never invent local file URLs.
- Use `viewerURL(assetID)` or `<hypha-viewer-link>` for native opens.
- Honor keyboard navigation, visible focus, reduced motion, text scaling, desktop/tablet/phone widths, and contrast.

## Required sequence

1. Restate the requested layout and the minimum capabilities.
2. Scaffold the package and bundle the SDK.
3. Implement the Canvas without credentials, Matrix mutation, builds, agents, or network calls.
4. Run `npm --prefix SDK/HyphaCanvasSDK test`.
5. Run `node SDK/HyphaCanvasSDK/scripts/package.mjs <package-root> --write`.
6. Present the capability list, accessibility notes, responsive notes, package digest, and local preview.
7. Wait for explicit user confirmation before copying the package into an attached repository or changing Git/Matrix state.
8. Let Hypha validate and publish the immutable remote Asset reference.

The deliverable is a deterministic static package with `hypha-room-template.json`; it is not authority to commit, push, build a repository, or publish room state.
