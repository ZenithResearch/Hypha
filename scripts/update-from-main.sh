#!/bin/bash
set -euo pipefail

REMOTE_URL="https://github.com/ZenithResearch/Hypha.git"
INSTALL_APP="${1:-}"

if [[ -z "$INSTALL_APP" || "$INSTALL_APP" != /* || "$INSTALL_APP" != *.app ]]; then
  echo "A valid absolute .app installation path is required." >&2
  exit 2
fi
if [[ ! -d "$INSTALL_APP/Contents/MacOS" ]]; then
  echo "The active Hypha application bundle was not found." >&2
  exit 2
fi

CACHE_ROOT="$HOME/Library/Caches/Hypha/updater"
SOURCE_DIR="$CACHE_ROOT/source"
mkdir -p "$CACHE_ROOT"
if [[ -L "$CACHE_ROOT" || -L "$SOURCE_DIR" ]]; then
  echo "The updater cache must not be a symbolic link." >&2
  exit 3
fi

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  rm -rf "$SOURCE_DIR"
  git -c core.hooksPath=/dev/null clone --no-checkout "$REMOTE_URL" "$SOURCE_DIR"
fi

git -C "$SOURCE_DIR" remote set-url origin "$REMOTE_URL"
git -C "$SOURCE_DIR" -c core.hooksPath=/dev/null fetch --force --prune origin main
git -C "$SOURCE_DIR" checkout --detach --force FETCH_HEAD
git -C "$SOURCE_DIR" clean -ffdqx
if ! git lfs version >/dev/null 2>&1; then
  echo "Git LFS is required to download Hypha's pinned SDK artifact." >&2
  exit 5
fi
git -C "$SOURCE_DIR" lfs pull origin main
git -C "$SOURCE_DIR" -c core.hooksPath=/dev/null submodule sync --recursive
git -C "$SOURCE_DIR" -c core.hooksPath=/dev/null submodule update --init --recursive --force

cd "$SOURCE_DIR"
HYPHA_SIGNING_MODE=adhoc ./build-app.sh
BUILT_APP="$SOURCE_DIR/Hypha.app"
codesign --verify --deep --strict "$BUILT_APP"
if [[ ! -x "$BUILT_APP/Contents/Resources/update-from-main.sh" ]]; then
  echo "GitHub main does not yet contain the self-update contract; the current app was left unchanged." >&2
  exit 4
fi

INSTALL_PARENT="$(cd "$(dirname "$INSTALL_APP")" && pwd -P)"
INSTALL_NAME="$(basename "$INSTALL_APP")"
INSTALL_APP="$INSTALL_PARENT/$INSTALL_NAME"
STAGED_APP="$INSTALL_PARENT/.Hypha-update-$PPID.app"
BACKUP_APP="$INSTALL_PARENT/.Hypha-previous-$PPID.app"
rm -rf "$STAGED_APP" "$BACKUP_APP"
ditto "$BUILT_APP" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

rollback() {
  local exit_code=$?
  rm -rf "$STAGED_APP"
  if [[ ! -d "$INSTALL_APP" && -d "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$INSTALL_APP"
  fi
  exit "$exit_code"
}
trap rollback ERR INT TERM

mv "$INSTALL_APP" "$BACKUP_APP"
mv "$STAGED_APP" "$INSTALL_APP"
codesign --verify --deep --strict "$INSTALL_APP"
rm -rf "$BACKUP_APP"
trap - ERR INT TERM

printf 'Installed Hypha from GitHub main at %s\n' "$(git -C "$SOURCE_DIR" rev-parse --short=12 HEAD)"
