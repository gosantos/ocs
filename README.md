# ocs

Run [opencode](https://opencode.ai) in a disposable Docker sandbox: no host directories mounted, credentials imported for the session only, container deleted on exit.

```bash
npx skills add gosantos/ocs
```

Works with OpenCode, Claude Code, Codex, Cursor and any agent that supports [Agent Skills](https://agentskills.io).

## Why

A coding agent with access to your home directory can read `~/.ssh`, every project and every token on the machine. `ocs` trades that reach for a container: opencode starts with an empty `/work`, and only the files you create inside the sandbox exist there. When the session ends, the container is removed and that filesystem is gone.

Credentials still work: the launcher exports them with `opencode auth export`, copies them into the container, imports them, and deletes the temporary file.

## Install

With an agent:

```bash
npx skills add gosantos/ocs
```

Then ask the agent to *"install ocs"*. It runs the installer from the skill directory.

Manually:

```bash
git clone https://github.com/gosantos/ocs
cd ocs
./install.sh
```

The installer puts `ocs` in `~/.local/bin`, builds the image, and adds a PATH + alias block to the shell configs it finds (zsh, bash, fish, POSIX). Open a new terminal afterwards.

## Usage

```bash
ocs                     # start opencode in a sandbox
ocs --continue          # arguments pass through to opencode
ocs --rebuild           # rebuild the image (newer base + latest opencode)
ocs-uninstall           # remove everything, keep the image
ocs-uninstall --remove-image
```

Each launch creates a fresh container with `--cap-drop ALL`, `no-new-privileges`, 4 GB RAM, 2 CPUs and 512 PIDs. Nothing is mounted from the host.

## Requirements

Docker Desktop or Docker Engine, running. macOS or Linux. The host does not need opencode installed, but without it the sandbox starts with no logins.

## How it works

```
skills/ocs/
├── SKILL.md
├── scripts/
│   ├── install.sh       # launcher, image, shell config
│   ├── uninstall.sh
│   └── ocs              # the launcher
└── docker/
    ├── Dockerfile       # debian:trixie-slim + official opencode v2 installer
    └── entrypoint.sh    # imports credentials, execs opencode
```

The image is built from `debian:trixie-slim` and installs opencode with the official v2 installer, so it tracks the current release and needs no Node runtime. Roughly 465 MB, of which ~243 MB is the opencode binary itself.

Overrides: `OCS_IMAGE`, `OCS_PREFIX`, `OCS_CONFIG_DIR`, `OCS_CONTEXT`.

## Uninstall

```bash
ocs-uninstall --remove-image
```

Or, without the launcher, run `skills/ocs/scripts/uninstall.sh` from a clone. It removes the launcher, `~/.config/ocs`, and the blocks in `~/.zshrc`, `~/.bashrc`, `~/.bash_profile`, `~/.profile` and the fish config.

## License

MIT
