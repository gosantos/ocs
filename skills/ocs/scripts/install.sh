#!/usr/bin/env bash
# ocs installer — puts the `ocs` launcher on PATH and sets up the Docker image.
# Idempotent: safe to run again, rewrites the shell block instead of duplicating it.
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
SKILL_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)

PREFIX="${OCS_PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
CONFIG_DIR="${OCS_CONFIG_DIR:-$HOME/.config/ocs}"
IMAGE="${OCS_IMAGE:-opencode-sandbox:latest}"
DO_BUILD=1

BEGIN_MARK='# >>> ocs >>>'
END_MARK='# <<< ocs <<<'

usage() {
  cat <<EOF
Usage: install.sh [options]

Installs the ocs launcher and builds its Docker image.

Options:
  --no-build            Skip building the image (useful in CI or on slow links)
  --prefix <dir>        Install the launcher under <dir>/bin (default: ~/.local)
  --config-dir <dir>    Where the Docker build context lives (default: ~/.config/ocs)
  --image <name>        Docker image tag to build (default: opencode-sandbox:latest)
  -h, --help            Show this help

Environment: OCS_PREFIX, OCS_CONFIG_DIR, OCS_IMAGE
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) DO_BUILD=0 ;;
    --prefix) PREFIX="${2:?--prefix needs a directory}"; BIN_DIR="$PREFIX/bin"; shift ;;
    --config-dir) CONFIG_DIR="${2:?--config-dir needs a directory}"; shift ;;
    --image) IMAGE="${2:?--image needs a tag}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
fail() { printf 'ocs: %s\n' "$*" >&2; exit 1; }

# --- platform checks ---------------------------------------------------------
# Everything here runs before the first write, so an unsupported machine is left
# untouched. macOS and Linux share the same code paths; only the hints differ.
OS=$(uname -s 2>/dev/null || true)
ARCH=$(uname -m 2>/dev/null || true)

case "$OS" in
  Darwin|Linux) ;;
  *) fail "unsupported operating system: ${OS:-unknown}
  ocs supports macOS and Linux only. On Windows, use WSL2 (which reports Linux)." ;;
esac

case "$ARCH" in
  x86_64|amd64|arm64|aarch64) ;;
  *) fail "unsupported CPU architecture: ${ARCH:-unknown}
  opencode publishes linux/amd64 and linux/arm64 images only." ;;
esac

# The launcher uses bash arrays, available since bash 3.1. macOS ships 3.2,
# which works; this only rejects something genuinely older or non-bash.
if [ -z "${BASH_VERSION:-}" ]; then
  fail "run the installer with bash, not sh: bash scripts/install.sh"
fi
BASH_MAJOR=${BASH_VERSION%%.*}
BASH_REST=${BASH_VERSION#*.}
BASH_MINOR=${BASH_REST%%.*}
if [ "$BASH_MAJOR" -lt 3 ] || { [ "$BASH_MAJOR" -eq 3 ] && [ "$BASH_MINOR" -lt 1 ]; }; then
  fail "bash 3.1 or newer is required (found $BASH_VERSION)"
fi

if ! command -v docker >/dev/null 2>&1; then
  case "$OS" in
    Darwin) fail "docker is not installed.
  Install Docker Desktop: https://docs.docker.com/desktop/install/mac-install/" ;;
    *) fail "docker is not installed.
  Install Docker Engine: https://docs.docker.com/engine/install/" ;;
  esac
fi

if ! docker info >/dev/null 2>&1; then
  case "$OS" in
    Darwin) fail "the Docker daemon is not running. Open Docker Desktop and rerun." ;;
    *) fail "the Docker daemon is not running or not accessible.
  Start it: sudo systemctl start docker
  Permission denied on the socket? Add your user to the docker group:
    sudo usermod -aG docker \$USER   (then log out and back in)" ;;
  esac
fi

if [ "$(docker info --format '{{.OSType}}' 2>/dev/null || true)" = "windows" ]; then
  fail "Docker is set to Windows containers. Switch Docker Desktop to Linux containers and rerun."
fi

say "Platform: $OS/$ARCH, bash $BASH_VERSION, Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || printf '?')"

# --- files -------------------------------------------------------------------
say "Installing launcher to $BIN_DIR/ocs"
mkdir -p "$BIN_DIR" "$CONFIG_DIR/docker"
install -m 755 "$SCRIPT_DIR/ocs" "$BIN_DIR/ocs"
rm -f "$BIN_DIR/ocs-uninstall"
install -m 755 "$SCRIPT_DIR/uninstall.sh" "$CONFIG_DIR/uninstall.sh"
install -m 644 "$SKILL_DIR/docker/Dockerfile" "$CONFIG_DIR/docker/Dockerfile"
install -m 755 "$SKILL_DIR/docker/entrypoint.sh" "$CONFIG_DIR/docker/entrypoint.sh"

if [ "$DO_BUILD" = 1 ]; then
  say "Building image $IMAGE (first build takes a few minutes)"
  docker build -t "$IMAGE" "$CONFIG_DIR/docker"
else
  say "Skipping image build (--no-build)"
fi

# --- shell integration -------------------------------------------------------
# Shells read different files, so write the block into every shell this machine
# actually has. Running twice is harmless: the block is replaced, not appended.
LOGIN_SHELL=$(basename "${SHELL:-sh}")

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
  fi
  rm -f "$tmp"
}

write_block() {
  file=$1
  body=$2
  strip_block "$file"
  if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then
    printf '\n' >> "$file"
  fi
  {
    printf '%s\n' "$BEGIN_MARK"
    printf '%s\n' "$body"
    printf '%s\n' "$END_MARK"
  } >> "$file"
}

posix_body() {
  cat <<EOF
# Added by the ocs installer. Remove with: ocs uninstall
export PATH="$BIN_DIR:\$PATH"
alias ocs="$BIN_DIR/ocs"
EOF
}

fish_body() {
  cat <<EOF
# Added by the ocs installer. Remove with: ocs uninstall
fish_add_path --global --move "$BIN_DIR"
alias ocs "$BIN_DIR/ocs"
EOF
}

ensure_rc() {
  file=$1
  shell_name=$2
  if [ ! -f "$file" ]; then
    # Only create a missing rc file for the shell the user actually logs in with.
    [ "$shell_name" = "$LOGIN_SHELL" ] || return 1
    mkdir -p "$(dirname "$file")"
    : > "$file"
  fi
  return 0
}

say "Configuring shells"
CONFIGURED=0

configure_posix() {
  shell_name=$1
  rc=$2
  command -v "$shell_name" >/dev/null 2>&1 || return 0
  ensure_rc "$rc" "$shell_name" || return 0
  write_block "$rc" "$(posix_body)"
  say "  $shell_name  $rc"
  CONFIGURED=$((CONFIGURED + 1))
}

configure_posix zsh "${ZDOTDIR:-$HOME}/.zshrc"
configure_posix bash "$HOME/.bashrc"
if [ -z "${ZDOTDIR:-}" ]; then
  configure_posix dash "$HOME/.profile"
  configure_posix ksh "$HOME/.profile"
  configure_posix sh "$HOME/.profile"
fi

if command -v fish >/dev/null 2>&1; then
  FISH_RC="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
  if [ ! -f "$FISH_RC" ]; then
    mkdir -p "$(dirname "$FISH_RC")"
    : > "$FISH_RC"
  fi
  write_block "$FISH_RC" "$(fish_body)"
  say "  fish  $FISH_RC"
  CONFIGURED=$((CONFIGURED + 1))
fi

# macOS bash login shells read .bash_profile, not .bashrc.
if [ "$(uname -s)" = "Darwin" ] && command -v bash >/dev/null 2>&1; then
  ensure_rc "$HOME/.bash_profile" bash || true
  if [ -f "$HOME/.bash_profile" ]; then
    write_block "$HOME/.bash_profile" "$(posix_body)"
    say "  bash  $HOME/.bash_profile (login)"
    CONFIGURED=$((CONFIGURED + 1))
  fi
fi

if [ "$CONFIGURED" = 0 ]; then
  say "  no shell config files found; add this line yourself:"
  say "    export PATH=\"$BIN_DIR:\$PATH\""
fi

# --- summary -----------------------------------------------------------------
say ""
say "Installed:"
say "  launcher  $BIN_DIR/ocs"
say "  context   $CONFIG_DIR"
if [ "$DO_BUILD" = 1 ]; then
  SIZE=$(docker image inspect "$IMAGE" --format '{{.Size}}' 2>/dev/null || echo 0)
  say "  image     $IMAGE ($(awk -v s="$SIZE" 'BEGIN { printf "%.0fMB", s / 1048576 }'))"
fi
say ""
say "Open a new terminal (or \`source\` one of the files above), then run:"
say "  ocs --version"
say "  ocs"
