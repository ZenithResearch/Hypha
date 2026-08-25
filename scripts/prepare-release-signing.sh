#!/bin/bash
# Prepare ephemeral Developer ID and notarization material for release CI.
set -euo pipefail

: "${MACOS_CERTIFICATE_P12:?release secret MACOS_CERTIFICATE_P12 is required}"
: "${MACOS_CERTIFICATE_PASSWORD:?release secret MACOS_CERTIFICATE_PASSWORD is required}"
: "${RELEASE_KEYCHAIN_PASSWORD:?release secret RELEASE_KEYCHAIN_PASSWORD is required}"
: "${APPLE_API_KEY_P8:?release secret APPLE_API_KEY_P8 is required}"
: "${APPLE_API_KEY_ID:?release secret APPLE_API_KEY_ID is required}"
: "${APPLE_API_ISSUER_ID:?release secret APPLE_API_ISSUER_ID is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_ENV:?GITHUB_ENV is required}"

umask 077
credential_dir="$(mktemp -d "$RUNNER_TEMP/hypha-release.XXXXXX")"
certificate_path="$credential_dir/developer-id.p12"
keychain_path="$credential_dir/signing.keychain-db"
notary_key_path="$credential_dir/AuthKey_${APPLE_API_KEY_ID}.p8"

cleanup_on_error() {
  status=$?
  if [[ $status -ne 0 ]]; then
    security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
    rm -f -- "$certificate_path" "$notary_key_path"
    rmdir "$credential_dir" >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup_on_error EXIT

printf '%s' "$MACOS_CERTIFICATE_P12" | /usr/bin/base64 -D > "$certificate_path"
printf '%s' "$APPLE_API_KEY_P8" | /usr/bin/base64 -D > "$notary_key_path"
chmod 600 "$certificate_path" "$notary_key_path"

security create-keychain -p "$RELEASE_KEYCHAIN_PASSWORD" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$RELEASE_KEYCHAIN_PASSWORD" "$keychain_path"
security import "$certificate_path" \
  -P "$MACOS_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign \
  -t cert \
  -f pkcs12 \
  -k "$keychain_path"
security set-key-partition-list \
  -S apple-tool:,apple: \
  -s \
  -k "$RELEASE_KEYCHAIN_PASSWORD" \
  "$keychain_path"
security list-keychains -d user -s "$keychain_path"

identity_count="$(
  security find-identity -v -p codesigning "$keychain_path" \
    | awk '/Developer ID Application:/ { count += 1 } END { print count + 0 }'
)"
if [[ "$identity_count" != 1 ]]; then
  echo "Expected exactly one valid Developer ID Application identity; found $identity_count." >&2
  exit 1
fi

{
  printf 'HYPHA_RELEASE_CREDENTIAL_DIR=%s\n' "$credential_dir"
  printf 'HYPHA_RELEASE_KEYCHAIN_PATH=%s\n' "$keychain_path"
  printf 'HYPHA_RELEASE_CERTIFICATE_PATH=%s\n' "$certificate_path"
  printf 'HYPHA_NOTARY_KEY_PATH=%s\n' "$notary_key_path"
} >> "$GITHUB_ENV"

trap - EXIT
