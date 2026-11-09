#!/usr/bin/env bash
# Removes the ocs launcher, build context, shell blocks and (by default) the image.
set -euo pipefail

PREFIX="${OCS_PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
CONFIG_DIR="${OCS_CONFIG_DIR:-$HOME/.config/ocs}"
IMAGE="${OCS_IMAGE:-opencode-sandbox:latest}"
KEEP_IMAGE=0

BEGIN_MARK='# >>> ocs >>>'
END_MARK='# <<< ocs <<<'

usage() {
  cat <<'EOF'
Usage: ocs uninstall [options]

Removes the ocs launcher, build context, shell blocks and image.

Options:
  --keep-image          Leave the Docker image in place
  --prefix <dir>        Launcher location (default: ~/.local)
  --config-dir <dir>    Build context (default: ~/.config/ocs)
  --image <name>        Docker image tag (default: opencode-sandbox:latest)
  -h, --help            Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --keep-image) KEEP_IMAGE=1 ;;
    --prefix) PREFIX="${2:?}"; BIN_DIR="$PREFIX/bin"; shift ;;
    --config-dir) CONFIG_DIR="${2:?}"; shift ;;
    --image) IMAGE="${2:?}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ocs uninstall: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

strip_block() {
  file=$1
  [ -f "$file" ] || return 0
  tmp=$(mktemp)
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0 == b { skip = 1; next }
    skip && $0 == e { skip = 0; next }
    !skip { print }
  ' "$file" > "$tmp"
  if ! cmp -s "$file" "$tmp"; then
    cat "$tmp" > "$file"
    printf '  cleaned  %s\n' "$file"
  fi
  rm -f "$tmp"
  # Remove rc files the installer created and left empty.
  if [ -f "$file" ] && [ ! -s "$file" ]; then
    rm -f "$file"
    printf '  removed  %s (was empty)\n' "$file"
  fi
}

printf 'Removing launcher\n'
rm -f "$BIN_DIR/ocs" "$BIN_DIR/ocs-uninstall"
printf '  removed  %s/ocs\n' "$BIN_DIR"

printf 'Cleaning shell configuration\n'
strip_block "${ZDOTDIR:-$HOME}/.zshrc"
strip_block "$HOME/.bashrc"
strip_block "$HOME/.bash_profile"
strip_block "$HOME/.profile"
strip_block "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"

if [ "$KEEP_IMAGE" = 0 ]; then
  printf 'Removing image %s\n' "$IMAGE"
  docker image rm "$IMAGE" >/dev/null 2>&1 || printf '  image not present\n'
fi

# Last: this script lives in CONFIG_DIR, and Unix keeps the open inode readable.
printf 'Removing build context\n'
rm -rf "$CONFIG_DIR"
printf '  removed  %s\n' "$CONFIG_DIR"

printf '\nDone. Open a new terminal to drop the ocs entries from PATH.\n'
