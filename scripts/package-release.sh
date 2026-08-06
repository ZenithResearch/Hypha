#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-}"
OUTPUT_DIR="${2:-$ROOT/dist}"
MODE="${HYPHA_RELEASE_MODE:-distributable}"

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 vMAJOR.MINOR.PATCH [output-directory]" >&2
  exit 1
fi

VERSION="${TAG#v}"
HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD)"
TAG_SHA="$(git -C "$ROOT" rev-list -n 1 "$TAG" 2>/dev/null || true)"
if [[ -n "$TAG_SHA" ]]; then
  if [[ "$TAG_SHA" != "$HEAD_SHA" ]]; then
    echo "Tag $TAG does not resolve to HEAD $HEAD_SHA." >&2
    exit 1
  fi
elif [[ "${HYPHA_RELEASE_ALLOW_UNTAGGED:-0}" != "1" ]]; then
  echo "Tag $TAG does not exist. Refusing to create release assets." >&2
  exit 1
fi

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
if [[ "$PLIST_VERSION" != "$VERSION" ]]; then
  echo "Tag version $VERSION does not match CFBundleShortVersionString $PLIST_VERSION." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
if find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  echo "Output directory must be empty: $OUTPUT_DIR" >&2
  exit 1
fi

case "$MODE" in
  distributable)
    if [[ "${HYPHA_ALLOW_NON_DISTRIBUTABLE_RELEASE:-0}" != "0" || "${HYPHA_RELEASE_ALLOW_UNTAGGED:-0}" != "0" ]]; then
      echo "Distributable packaging rejects non-distributable and untagged escape hatches." >&2
      exit 1
    fi
    : "${HYPHA_NOTARY_KEY_PATH:?HYPHA_NOTARY_KEY_PATH is required}"
    : "${HYPHA_NOTARY_KEY_ID:?HYPHA_NOTARY_KEY_ID is required}"
    : "${HYPHA_NOTARY_ISSUER_ID:?HYPHA_NOTARY_ISSUER_ID is required}"
    GATE_SHA="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit_sha"])' "$ROOT/release/encryption-gate.json")"
    git -C "$ROOT" merge-base --is-ancestor "$GATE_SHA" "$HEAD_SHA"
    git -C "$ROOT" diff --quiet "$GATE_SHA" "$HEAD_SHA" -- Package.swift Package.resolved Sources Vendor Resources scripts/update-from-main.sh scripts/launch-update-from-main.command build-app.sh
    HYPHA_SIGNING_MODE=developer-id "$ROOT/build-app.sh"
    if ! codesign -dv --verbose=4 "$ROOT/Hypha.app" 2>&1 | grep -q 'Authority=Developer ID Application'; then
      echo "Hypha.app is not signed with a Developer ID Application identity." >&2
      exit 1
    fi
    NOTARY_ARCHIVE="$(mktemp -t hypha-notarization).zip"
    trap 'rm -f "$NOTARY_ARCHIVE"' EXIT
    ditto -c -k --sequesterRsrc --keepParent "$ROOT/Hypha.app" "$NOTARY_ARCHIVE"
    xcrun notarytool submit "$NOTARY_ARCHIVE" \
      --key "$HYPHA_NOTARY_KEY_PATH" \
      --key-id "$HYPHA_NOTARY_KEY_ID" \
      --issuer "$HYPHA_NOTARY_ISSUER_ID" \
      --wait
    xcrun stapler staple "$ROOT/Hypha.app"
    xcrun stapler validate "$ROOT/Hypha.app"
    spctl --assess --type execute --verbose=4 "$ROOT/Hypha.app"
    SIGNING_MODE="developer-id"
    NOTARIZED="true"
    ;;
  adhoc)
    if [[ "${HYPHA_ALLOW_NON_DISTRIBUTABLE_RELEASE:-0}" != "1" ]]; then
      echo "Ad-hoc release packaging is non-distributable and requires explicit opt-in." >&2
      exit 1
    fi
    HYPHA_SIGNING_MODE=adhoc "$ROOT/build-app.sh"
    SIGNING_MODE="adhoc"
    NOTARIZED="false"
    ;;
  *)
    echo "Unsupported HYPHA_RELEASE_MODE=$MODE" >&2
    exit 1
    ;;
esac

if [[ "$(lipo -archs "$ROOT/Hypha.app/Contents/MacOS/Hypha")" != "arm64" ]]; then
  echo "Release executable must contain exactly the arm64 architecture." >&2
  exit 1
fi

ARCHIVE_NAME="Hypha-${TAG}-macos-arm64.zip"
ARCHIVE="$OUTPUT_DIR/$ARCHIVE_NAME"
METADATA="$OUTPUT_DIR/Hypha-${TAG}-release.json"
CHECKSUMS="$OUTPUT_DIR/SHA256SUMS"

ditto -c -k --sequesterRsrc --keepParent "$ROOT/Hypha.app" "$ARCHIVE"
python3 "$ROOT/scripts/write_release_metadata.py" \
  --tag "$TAG" \
  --commit "$HEAD_SHA" \
  --app "$ROOT/Hypha.app" \
  --archive "$ARCHIVE" \
  --gate "$ROOT/release/encryption-gate.json" \
  --signing-mode "$SIGNING_MODE" \
  --notarized "$NOTARIZED" \
  --output "$METADATA"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$ARCHIVE_NAME" "$(basename "$METADATA")" > "$(basename "$CHECKSUMS")"
  shasum -a 256 -c "$(basename "$CHECKSUMS")"
)

printf 'Release assets created in %s\n' "$OUTPUT_DIR"
