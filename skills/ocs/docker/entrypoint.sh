#!/bin/sh
set -e
# Import the credentials copied from the host, then delete the file so they
# exist only in opencode's own credential store inside this container.
if [ -f /home/dev/creds.json ]; then
  opencode auth import /home/dev/creds.json >/dev/null
  rm -f /home/dev/creds.json
fi
exec opencode "$@"
