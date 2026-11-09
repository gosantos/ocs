---
name: ocs
description: Installs and configures `ocs`, a throwaway Docker sandbox for running opencode with no host directories mounted and credentials imported for the session only. Use when the user wants to run opencode (or another coding agent) in an isolated, containerized or sandboxed environment, asks to install `ocs`, or wants a safer setup that keeps their home directory and project files off the agent's filesystem. Handles macOS and Linux and writes PATH and alias setup for zsh, bash, fish and POSIX shells.
---

# ocs — sandboxed opencode

`ocs` runs opencode in a disposable container. Nothing from the host is mounted:
the container starts empty, the user's credentials are exported with
`opencode auth export`, copied in, imported, and the temporary file is deleted.
When the session ends the container is removed.

This skill installs the launcher, builds the image, and wires the command into
the user's shells.

## Requirements

- Docker Desktop or Docker Engine, running.
- macOS or Linux with bash.
- Host opencode is optional; without it the sandbox has no logins.

## Install

Run the installer from this skill directory:

```bash
bash scripts/install.sh
```

It does four things:

1. Copies the launcher to `~/.local/bin/ocs`.
2. Copies the Docker build context to `~/.config/ocs`.
3. Builds `opencode-sandbox:latest` (~465 MB; most of it is the opencode binary).
4. Adds an idempotent block to each shell config it finds (see below).

Use `--no-build` when Docker is slow or the image already exists, and
`--prefix <dir>` or `OCS_PREFIX` to install somewhere other than `~/.local`.
The first build downloads the base image and the opencode binary, so give it a
few minutes and do not interrupt it.

## Verify

```bash
~/.local/bin/ocs --version
```

This starts a container, prints the opencode version, then removes the
container. If it prints a version, the install works. In a fresh terminal the
plain `ocs --version` should work too; if it does not, the shell config was not
picked up (see Troubleshooting).

## Shell integration

The installer writes this block to every shell it detects:

```sh
# >>> ocs >>>
export PATH="$HOME/.local/bin:$PATH"
alias ocs="$HOME/.local/bin/ocs"
# <<< ocs <<<
```

fish gets `fish_add_path --global --move` and an `alias` instead. Running the
installer again replaces the block rather than duplicating it. If a shell has no
config file yet, the file is only created for the user's login shell, so the
installer does not litter home directories with configs for tools the user never
opens.

Tell the user to open a new terminal or source the file they already use, for
example `source ~/.zshrc`.

## Uninstall

```bash
ocs uninstall              # launcher, build context, shell blocks and image
ocs uninstall --keep-image # keep the ~465 MB image for later
```

## Troubleshooting

**`docker: command not found`** — install Docker Desktop on macOS or Docker
Engine on Linux, then rerun the installer.

**`Cannot connect to the Docker daemon`** — Docker is installed but not running.
Start Docker Desktop, or `sudo systemctl start docker`, then rerun.

**`permission denied` on the Docker socket** — add the user to the `docker`
group (`sudo usermod -aG docker "$USER"`), log out and back in. Do not run the
installer with `sudo`: it would write root-owned files into the user's home.

**`ocs` works as `~/.local/bin/ocs` but not as `ocs`** — the shell has not
reloaded its config. Run `source ~/.zshrc` (or the file listed by the
installer), or open a new terminal.

**opencode starts without logins** — the host had no exported credentials.
Run `opencode auth login` on the host, then start `ocs` again.

**A newer opencode or base image is wanted** — rebuild:

```bash
ocs rebuild
```

`ocs rebuild` runs `docker build --pull`, which refreshes the base image and
installs the latest opencode release. Pin a version by editing
`~/.config/ocs/docker/Dockerfile` to pass `--build-arg OPENCODE_VERSION=x.y.z`.

**The image feels large** — that is the opencode binary (~243 MB) plus Debian.
Switching the first line to `FROM alpine:3.22` and the installer URL to the musl
build saves roughly 100 MB, at the cost of musl quirks in other tooling.
