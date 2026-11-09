#!/usr/bin/env bash
# Convenience wrapper so ./install.sh works from the repo root.
set -euo pipefail
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec bash "$DIR/skills/ocs/scripts/install.sh" "$@"
