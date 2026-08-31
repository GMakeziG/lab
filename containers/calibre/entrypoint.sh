#!/bin/sh
set -eu

: "${CALIBRE_USERNAME:?CALIBRE_USERNAME is required}"
: "${CALIBRE_PASSWORD:?CALIBRE_PASSWORD is required}"

userdb=/config/users.sqlite

# calibre-server requires an initialized library. This is idempotent and only
# creates metadata.db when the library PVC is empty.
if [ ! -f /library/metadata.db ]; then
    calibredb list --with-library /library >/dev/null
fi

if calibre-server --userdb "$userdb" --manage-users -- list 2>/dev/null | grep -Fxq "$CALIBRE_USERNAME"; then
    calibre-server --userdb "$userdb" --manage-users -- chpass "$CALIBRE_USERNAME" "$CALIBRE_PASSWORD"
else
    calibre-server --userdb "$userdb" --manage-users -- add "$CALIBRE_USERNAME" "$CALIBRE_PASSWORD"
fi

unset CALIBRE_USERNAME CALIBRE_PASSWORD
exec calibre-server "$@"
