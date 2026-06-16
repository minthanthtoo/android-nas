# Troubleshooting

## `No rclone remote found`

Run:

```bash
rclone config
```

Create an SFTP remote named `NAS` or `android`.

## `Remote NAS root is not reachable`

Check on the phone:

```bash
sshd
ip a
```

Then confirm the client can connect:

```bash
ssh -p 8022 <termux-user>@<phone-ip>
```

## Mount command exits but the directory is empty

Common causes:

- the configured workspace does not exist remotely
- the remote points to the wrong base path
- `rclone mount` failed before the FUSE mount became active

Run:

```bash
nas-status
tail -n 50 ~/.local/state/android-nas/rclone.log
```

## Termux does not start after reboot

Validate all of the following:

- Termux:Boot is installed
- the Termux:Boot app was opened once after install
- `~/.termux/boot/` contains the boot script
- battery optimization is disabled for both Termux and Termux:Boot on vendors that expose separate policies

Official Termux:Boot guidance also recommends `termux-wake-lock` in boot scripts.

## Frequent disconnects

- Disable battery optimization for Termux.
- Disable aggressive Wi-Fi power saving.
- Keep the device on a charger for long-running mounts.
- Prefer a dedicated NAS device or profile if the phone is also used interactively.
