# Repository output contract (`out/out.json`)

`out/out.json` is the normative, repository-owned description of content Hypha can present in a room. Version 2 declares an ordered multi-artifact result while retaining a single-artifact mirror that older Hypha clients understand. The machine-readable writer contract is [`out.schema.json`](out.schema.json), and [`examples/out.v2.json`](examples/out.v2.json) is the canonical PowerPoint-led example.

## Trust and path boundary

- The manifest lives at `<repository>/<output_directory>/<manifest>`; current room attachments default to `out/out.json`.
- Every path is relative to the output directory. Hypha rejects absolute paths, traversal, symlink escapes, missing files, and bundle roots outside that directory.
- `format`, `media_type`, and `viewer` are declarations, not file-type proof. The current local compatibility reader normalizes declared format and extension hints; it is not a remote trust boundary. HYPHA-ART-001B adds byte/container classification before remote or cached content can be promoted or displayed.
- Git commit, source provenance, fetch time, immutable cache URL, digest, and render revision are runtime facts and do not belong in `out.json`.
- `build` is a local authoring convenience. Hypha may offer it for exact review and confirmation only from a user-selected local checkout. Remote, cached, or Matrix-loaded content must ignore it and must never execute it.
- Slideshow state such as current slide, autoplay, loop, zoom, or fullscreen preference is UI state and must not be written to the repository contract.

## Version 2

Version 2 adds `version`, `primary`, and an authoritative ordered `artifacts` list. Writers should use the canonical example:

```json
{
  "version": 2,
  "primary": "deck",
  "artifacts": [
    {
      "id": "deck",
      "title": "Quarterly deck",
      "path": "slides/deck.pptx",
      "format": "pptx",
      "media_type": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
      "viewer": "slideshow"
    },
    {
      "id": "launch-brief",
      "title": "Launch brief",
      "path": "launch.pdf",
      "format": "pdf",
      "media_type": "application/pdf",
      "viewer": "pdf"
    },
    {
      "id": "product-map",
      "title": "Interactive product map",
      "path": "site/index.html",
      "format": "html",
      "media_type": "text/html",
      "viewer": "web",
      "bundle_root": "site"
    },
    {
      "id": "speaker-notes",
      "title": "Speaker notes",
      "path": "notes.md",
      "format": "md",
      "media_type": "text/markdown",
      "viewer": "markdown"
    }
  ],
  "path": "slides/deck.pptx",
  "format": "pptx",
  "viewer": "quickLook"
}
```

### Top-level fields

| Field | Writer requirement | Meaning |
|---|---:|---|
| `version` | Required | Integer contract version. The declared-artifact contract is version 2. |
| `primary` | Required | Stable `id` that opens first. Readers tolerate omission only when exactly one artifact exists. |
| `artifacts` | Required | Ordered, authoritative artifact list; undeclared files are not added. One to 64 entries. |
| `path` | Required | Old-reader mirror of the primary path; it must resolve to the same file. |
| `format` | Recommended | Old-reader mirror of the primary normalized format. |
| `viewer` | Recommended | Old-reader-safe mirror computed from the primary format. |
| `build` | Optional, local only | Command that may be shown for explicit local confirmation; never a remote instruction. |

The mirror deliberately uses a smaller vocabulary than artifact entries. PPTX/PPSX slideshow and PDF artifacts mirror as `quickLook`; Markdown mirrors as `text`; HTML, image, text, and legacy Quick Look routes retain their safe value. A new reader validates this mirror instead of accepting two competing primary definitions.

### Artifact fields

| Field | Required | Meaning |
|---|---:|---|
| `id` | Yes | A stable identifier of 1–64 ASCII letters, digits, `.`, `_`, or `-`, starting with a letter or digit. |
| `title` | No | Human-readable title of at most 120 characters; defaults to the filename without its extension. |
| `path` | Yes | Strict relative entry-point path inside the output directory, at most 1,024 characters. |
| `format` | No | Normalized extension without a leading dot, at most 32 characters; defaults to the path extension. |
| `media_type` | No | IANA-style media type without parameters. It remains an untrusted hint until byte preflight succeeds. |
| `viewer` | No | Constrained renderer preference; omission lets the validated type choose its default route. |
| `bundle_root` | HTML only | Relative directory containing the HTML entry point and local CSS/image/font dependencies. The effective format (an explicit `format` or the `path` extension) must be `html`/`htm`; if `viewer` is present it must be `web`. |

Artifact order is stable. Hypha returns the primary first, followed by all remaining declarations in their original relative order, and keys user selection by artifact `id` rather than a device-local file URL.

## Three viewer vocabularies

Viewer placement is intentional and is enforced by both the schema and semantic reader:

| Position | Accepted values |
|---|---|
| Tolerant version-1 input | `quickLook`, `pdf`, `web`, `image`, `markdown`, `text` |
| Version-2 top-level old-client mirror | `quickLook`, `web`, `image`, `text` |
| Version-2 artifact | `quickLook`, `pdf`, `web`, `image`, `markdown`, `text`, `slideshow` |

`slideshow` is valid only for version-2 PPTX/PPSX artifact entries. It is never valid in version 1 or at the version-2 top level. Legacy PowerPoint `quickLook` remains readable, but current readers normalize PPTX/PPSX to the slideshow route. Legacy binary `.ppt` remains Quick Look-only. Until the native scene importer and player ship, the slideshow route uses an explicitly labeled compatibility preview.

## Format and renderer map

| Formats | Current normalized route | Old-client-safe mirror |
|---|---|---|
| `pptx`, `ppsx` | `slideshow` | `quickLook` |
| `ppt` | `quickLook` | `quickLook` |
| `pdf` | `pdf` (legacy `quickLook` accepted) | `quickLook` |
| `html`, `htm` | `web` | `web` |
| `png`, `jpg`, `jpeg`, `gif`, `heic` | `image` | `image` |
| `md`, `markdown` | `markdown` | `text` |
| `txt`, `json`, `log` | `text` | `text` |

The manifest cannot enable scripting, network access, or executable content. The current local reader rejects renderer preferences incompatible with the declared format, but declarations are not file-type proof. HYPHA-ART-001B adds byte/container classification before remote promotion; the HTML content blocker, bundle read boundary, and later renderer hardening add stronger process boundaries.

## Version 1 compatibility

Unversioned manifests and explicit `"version": 1` remain readable:

```json
{
  "build": "npm run export",
  "viewer": "quickLook",
  "path": "deck.pptx",
  "format": "pptx"
}
```

With no manifest, Hypha discovers supported files. With version 1, the selected file opens first and discovered supported files remain available. With version 2, only declared artifacts appear. Unknown future versions fail closed instead of being guessed.

## Semantic resolution order

1. Decode the JSON and reject an unsupported version or a viewer used in the wrong vocabulary.
2. For version 2, validate the artifact count, IDs, duplicate IDs, primary, titles, paths, formats, renderer compatibility, media types, file existence, symlink containment, and bundle containment.
3. Validate that the top-level path and any top-level format/viewer mirror the declared primary, including PPTX/PPSX/PDF → `quickLook` and Markdown → `text`.
4. Return the primary first, then the remaining declarations in manifest order. Do not discover undeclared version-2 files.
5. Never execute `build` while opening remote, cached, or Matrix-provided room content.

## Validate the writer contract

Run `npm --prefix docs ci --ignore-scripts --no-audit --no-fund` once, then `npm --prefix docs test`. The pinned Draft 2020-12 conformance suite validates the canonical example plus compatible v1/v2 fixtures and expected failures for viewer placement, strict paths, and HTML bundle rules. Hypha's Swift tests separately verify semantic resolution against real files and directories.
