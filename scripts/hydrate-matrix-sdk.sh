#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT="$ROOT/Vendor/MatrixRustSDK/MatrixSDKFFI.xcframework.zip"
EXPECTED_SHA256="9b853f98352f088ae0939e28d4d739349c396f9b57f6af815c0a7957156fe4c8"
SOURCE_COMMIT="d28c164ef37cd67723aa565bf5aec9c0cefc3bb8"
RELEASE_TAG="hypha-26.08.15-zenith.12"
ARTIFACT_URL="https://github.com/bananawalnut/matrix-rust-sdk/releases/download/hypha-26.08.15-zenith.12/MatrixSDKFFI.xcframework.zip"

current_sha256() {
  if [[ -f "$ARTIFACT" ]]; then
    /usr/bin/shasum -a 256 "$ARTIFACT" | /usr/bin/awk '{print $1}'
  fi
}

if [[ "$(current_sha256)" == "$EXPECTED_SHA256" ]]; then
  printf 'Verified MatrixSDKFFI artifact %s from source %s\n' "$EXPECTED_SHA256" "$SOURCE_COMMIT"
  exit 0
fi

TEMPORARY_ARTIFACT="$(/usr/bin/mktemp -t hypha-matrix-sdk)"
cleanup() {
  /bin/rm -f -- "$TEMPORARY_ARTIFACT"
}
trap cleanup EXIT INT TERM

printf 'Hydrating MatrixSDKFFI from the pinned source release %s\n' "$RELEASE_TAG"
/usr/bin/curl \
  --fail \
  --location \
  --proto '=https' \
  --tlsv1.2 \
  --retry 3 \
  --retry-all-errors \
  --connect-timeout 20 \
  --output "$TEMPORARY_ARTIFACT" \
  "$ARTIFACT_URL"

ACTUAL_SHA256="$(/usr/bin/shasum -a 256 "$TEMPORARY_ARTIFACT" | /usr/bin/awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  printf 'MatrixSDKFFI checksum mismatch. Expected %s, received %s.\n' \
    "$EXPECTED_SHA256" "$ACTUAL_SHA256" >&2
  exit 1
fi

/usr/bin/unzip -tq "$TEMPORARY_ARTIFACT" >/dev/null
/bin/mkdir -p "$(/usr/bin/dirname "$ARTIFACT")"
/bin/mv -f "$TEMPORARY_ARTIFACT" "$ARTIFACT"
trap - EXIT INT TERM
printf 'Hydrated and verified MatrixSDKFFI artifact %s\n' "$EXPECTED_SHA256"
