# Architecture

## Server side

The Android device runs:

- Termux
- `openssh` `sshd` on port `8022`
- a boot script in `~/.termux/boot/`
- shared storage rooted at `/storage/emulated/0/nas`

`sshd` provides both shell access and the SFTP subsystem used by `rclone`.

## Client side

The macOS client uses:

- `rclone` SFTP remote
- a config file at `~/.config/android-nas/config.env`
- runtime state in `~/.local/state/android-nas/`
- mountpoints under `~/mnt/android-nas/`

## Runtime model

`nas-mount`:

1. loads config
2. detects the preferred `rclone` remote
3. validates the remote NAS root
4. ensures the selected workspace exists remotely
5. starts `rclone mount`
6. waits for the mount to become active

`nas-unmount`:

1. unmounts the workspace mountpoint
2. terminates the matching `rclone mount` process if still alive
3. clears stale PID state

`nas-status`:

1. prints effective config
2. verifies remote reachability
3. verifies local mount status
4. reports PID and log file state

## Design choices

- Commands are committed to the repo instead of being generated ad hoc.
- The installer creates symlinks instead of shell aliases so commands are explicit and discoverable.
- Remote workspace creation is automatic to avoid empty-mount confusion caused by missing folders.
- PID tracking is scoped to this project instead of using broad `pkill` patterns.
