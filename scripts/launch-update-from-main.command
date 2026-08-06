#!/bin/zsh
set -u

RESOURCE_DIR="$(cd "$(dirname "$0")" && pwd -P)"
INSTALL_APP="$(cd "$RESOURCE_DIR/../.." && pwd -P)"
UPDATER="$RESOURCE_DIR/update-from-main.sh"

print 'Hypha is rebuilding from the canonical GitHub main branch.'
print 'This Terminal window is the authoritative update log.'
print ''

if "$UPDATER" "$INSTALL_APP"; then
  print ''
  print 'Update installed from GitHub main. Reopening Hypha…'
  /usr/bin/open -n "$INSTALL_APP" || true
  exit 0
else
  exit_status=$?
fi

print -u2 ''
print -u2 "Update failed with exit status $exit_status. The installed application was left unchanged."
print -u2 'Review the error above, then retry from Hypha Settings.'
/usr/bin/open -n "$INSTALL_APP" || true
exit "$exit_status"
