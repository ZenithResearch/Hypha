#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Hypha.app"
EXECUTABLE="$APP/Contents/MacOS/Hypha"
HYPHA_SIGNING_MODE="${HYPHA_SIGNING_MODE:-development}"
HYPHA_DEVELOPMENT_TEAM="${HYPHA_DEVELOPMENT_TEAM:-KR4YTNKK3Y}"

case "$HYPHA_SIGNING_MODE" in
  development)
    if [[ -n "${HYPHA_CODESIGN_IDENTITY:-}" ]]; then
      SIGNING_IDENTITY="$HYPHA_CODESIGN_IDENTITY"
    else
      SIGNING_IDENTITIES=()
      while IFS= read -r identity; do
        SIGNING_IDENTITIES+=("$identity")
      done < <(
        security find-identity -v -p codesigning 2>/dev/null \
          | awk '$0 ~ /Apple Development:/ { print $2 }'
      )
      if [[ ${#SIGNING_IDENTITIES[@]} -ne 1 ]]; then
        echo "Expected exactly one valid Apple Development identity; found ${#SIGNING_IDENTITIES[@]}." >&2
        echo "Set HYPHA_CODESIGN_IDENTITY explicitly or use HYPHA_SIGNING_MODE=adhoc for non-authoritative packaging." >&2
        exit 1
      fi
      SIGNING_IDENTITY="${SIGNING_IDENTITIES[0]}"
    fi
    ;;
  adhoc)
    SIGNING_IDENTITY="-"
    ;;
  developer-id)
    if [[ -n "${HYPHA_CODESIGN_IDENTITY:-}" ]]; then
      SIGNING_IDENTITY="$HYPHA_CODESIGN_IDENTITY"
    else
      SIGNING_IDENTITIES=()
      while IFS= read -r identity; do
        SIGNING_IDENTITIES+=("$identity")
      done < <(
        security find-identity -v -p codesigning 2>/dev/null \
          | awk '$0 ~ /Developer ID Application:/ { print $2 }'
      )
      if [[ ${#SIGNING_IDENTITIES[@]} -ne 1 ]]; then
        echo "Expected exactly one valid Developer ID Application identity; found ${#SIGNING_IDENTITIES[@]}." >&2
        echo "Set HYPHA_CODESIGN_IDENTITY explicitly." >&2
        exit 1
      fi
      SIGNING_IDENTITY="${SIGNING_IDENTITIES[0]}"
    fi
    ;;
  *)
    echo "Unsupported HYPHA_SIGNING_MODE=$HYPHA_SIGNING_MODE (expected development, adhoc, or developer-id)." >&2
    exit 1
    ;;
esac

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

cd "$ROOT"
export MACOSX_DEPLOYMENT_TARGET=26.4
swift build -c release --product Hypha
python3 - "$APP" <<'PY'
import pathlib, shutil, sys
app = pathlib.Path(sys.argv[1])
if app.exists():
    shutil.rmtree(app)
(app / "Contents" / "MacOS").mkdir(parents=True)
(app / "Contents" / "Resources").mkdir(parents=True)
PY
cp "$ROOT/.build/release/Hypha" "$EXECUTABLE"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/ZenithOSIcon.icns" "$APP/Contents/Resources/ZenithOSIcon.icns"
cp "$ROOT/scripts/update-from-main.sh" "$APP/Contents/Resources/update-from-main.sh"
cp "$ROOT/scripts/launch-update-from-main.command" "$APP/Contents/Resources/launch-update-from-main.command"
chmod 755 \
  "$APP/Contents/Resources/update-from-main.sh" \
  "$APP/Contents/Resources/launch-update-from-main.command"
LICENSE_RESOURCES="$APP/Contents/Resources/Licenses"
mkdir -p "$LICENSE_RESOURCES"
cp "$ROOT/LICENSE" "$LICENSE_RESOURCES/AGPL-3.0-or-later.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$LICENSE_RESOURCES/THIRD_PARTY_NOTICES.md"
cp "$ROOT/THIRD_PARTY_LICENSES.html" "$LICENSE_RESOURCES/THIRD_PARTY_LICENSES.html"
cp -R "$ROOT/LICENSES" "$LICENSE_RESOURCES/LICENSES"
printf 'Source: https://github.com/ZenithResearch/Hypha\nCommit: %s\n' "$(git -C "$ROOT" rev-parse HEAD)" > "$LICENSE_RESOURCES/SOURCE.txt"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
python3 "$ROOT/scripts/verify_app_dependencies.py" "$EXECUTABLE" "$APP"
python3 "$ROOT/scripts/verify_app_licenses.py" "$ROOT" "$APP"
if [[ "$HYPHA_SIGNING_MODE" == "developer-id" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" --entitlements "$ROOT/Resources/Hypha.entitlements" "$APP"
else
  codesign --force --deep --sign "$SIGNING_IDENTITY" --entitlements "$ROOT/Resources/Hypha.entitlements" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ "$HYPHA_SIGNING_MODE" != "adhoc" ]]; then
  ACTUAL_TEAM_ID="$(codesign -dv --verbose=4 "$APP" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')"
  if [[ "$ACTUAL_TEAM_ID" != "$HYPHA_DEVELOPMENT_TEAM" ]]; then
    echo "Signed TeamIdentifier $ACTUAL_TEAM_ID does not match expected $HYPHA_DEVELOPMENT_TEAM." >&2
    exit 1
  fi
fi
if [[ "$HYPHA_SIGNING_MODE" == "developer-id" ]] && ! codesign -dv --verbose=4 "$APP" 2>&1 | grep -Eq '^flags=.*runtime'; then
  echo "Developer ID signature is missing the hardened runtime flag." >&2
  exit 1
fi
printf 'Built %s (signing=%s)\n' "$APP" "$HYPHA_SIGNING_MODE"
