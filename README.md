# Android NAS

Turn an Android phone running Termux into a stable SFTP-backed NAS node for `rclone`, with a hardened Termux setup and macOS client helpers.

## What this repository includes

- `scripts/setup-nas-termux.sh`: one-shot Android/Termux server setup
- `scripts/setup-nas-mac.sh`: macOS installer for local NAS helper commands
- `scripts/nas-mount`: mount a workspace from the phone with `rclone`
- `scripts/nas-unmount`: unmount cleanly
- `scripts/nas-switch`: switch active workspace
- `scripts/nas-status`: show health and connection state
- `docs/ARCHITECTURE.md`: system design
- `docs/TROUBLESHOOTING.md`: operational fixes

## Topology

Android exports:

```text
/storage/emulated/0/nas/
├── projects
├── experiments
├── claude
├── backups
└── shared
```

macOS mounts one workspace at a time to:

```text
~/mnt/android-nas/<workspace>
```

## Prerequisites

### Android / Termux

- Termux installed
- Termux:Boot installed and opened once
- Network access on the same LAN as the client

### macOS

- `rclone` installed and configured with an SFTP remote to the phone
- A FUSE backend available for `rclone mount` on macOS
- `bash`

## Quick start

### 1. Configure the phone

Copy this repo to the phone or fetch the script, then run:

```bash
bash scripts/setup-nas-termux.sh
```

The script:

- updates packages
- installs `openssh`, `rsync`, and `termux-services`
- initializes shared storage access
- creates the NAS directory tree
- enables `sshd`
- installs a boot script in `~/.termux/boot/`
- prints the effective connection details

### 2. Configure the Mac

Run:

```bash
bash scripts/setup-nas-mac.sh
```

The installer creates:

- config at `~/.config/android-nas/config.env`
- logs in `~/.local/state/android-nas/`
- symlinked commands in `~/.local/bin/`

### 3. Mount a workspace

```bash
nas-mount
nas-status
```

Switch workspaces:

```bash
nas-switch experiments
```

Unmount:

```bash
nas-unmount
```

## Default configuration

The generated client config contains:

```bash
REMOTE=NAS
REMOTE_FALLBACK=android
BASE_PATH=/storage/emulated/0/nas
WORKSPACE=projects
MOUNT_ROOT=$HOME/mnt/android-nas
```

If `NAS` does not exist, the client automatically falls back to `android`.

## Security notes

- Prefer SSH key authentication over password authentication.
- Keep the phone on a trusted LAN.
- Disable aggressive battery optimization for Termux.
- Review [SECURITY.md](SECURITY.md) before exposing the service to anything beyond a private network.

## Validation

Run locally:

```bash
make test
```

## Repository status

This repository is productionized for operations, CI, and repeatable installs. A software license file is intentionally not included because that choice should be explicit.
