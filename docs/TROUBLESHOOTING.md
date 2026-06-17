# Troubleshooting

This document is organized by failure mode, not by command list.

## First Triage

When the system behaves unexpectedly, start here on the client:

```bash
nas-doctor
nas-status
tail -n 50 ~/.local/state/android-nas/rclone.log
tail -n 50 ~/.local/state/android-nas/usb-watch.log
tail -n 50 ~/.local/state/android-nas/usb-watch.err
```

On the Android primary:

```bash
nas-android-doctor
nas-android-usb-sync status
```

## Failure Class: Client Cannot Reach Primary

### Symptom

- `nas-status` reports remote unreachable
- `nas-mount` exits before the mount becomes active
- watcher reports the primary as unavailable

### Checks

On Android:

```bash
sshd
ip a
```

On the client:

```bash
ssh -p 8022 <termux-user>@<phone-ip>
```

### Likely causes

- `sshd` is not running
- the phone changed IP address
- the phone left the LAN
- Android power management suspended the process
- the `rclone` remote points to the wrong host or path

### Corrective action

1. Start `sshd` on the phone.
2. Confirm the current Wi-Fi IP address.
3. Re-test plain SSH before blaming `rclone`.
4. Re-run `rclone config` if the remote definition is stale.

## Failure Class: Mount Exists but Behaves Wrongly

### Symptom

- mountpoint exists but appears empty
- mount exits early
- file operations are unexpectedly fragile on the client

### Checks

```bash
nas-status
tail -n 50 ~/.local/state/android-nas/rclone.log
```

### Likely causes

- remote base path is wrong
- workspace does not exist remotely
- FUSE mount failed after command launch
- `CLIENT_CACHE_MODE=spaceless` is too strict for the workload

### Corrective action

1. Confirm `BASE_PATH` and `WORKSPACE` in `~/.config/android-nas/config.env`.
2. Test a less aggressive cache mode:

```bash
CLIENT_CACHE_MODE=full
```

3. Retry the mount.

## Failure Class: Android Boot Automation Does Not Resume

### Symptom

- rebooted phone does not restart the watcher
- `sshd` is not running after reboot

### Checks

- Termux:Boot is installed
- Termux:Boot has been opened at least once after install
- `~/.termux/boot/start-android-nas` exists and is executable
- Android battery optimization is disabled for Termux and Termux:Boot

### Corrective action

On Android:

```bash
ls -l ~/.termux/boot/
pgrep -x sshd
pgrep -f nas-android-usb-watch
```

If needed, re-run:

```bash
bash scripts/setup-nas-termux.sh
```

## Failure Class: USB Is Not Detected On Android

### Symptom

- `nas-android-usb-watch` never reacts
- `nas-android-usb-sync status` cannot find a USB root

### Important reality

Android removable storage exposure is inconsistent across vendors and Android versions. The current system uses path heuristics. It does not integrate Android Storage Access Framework permissions.

### Checks

```bash
nas-android-usb-sync status
```

### Corrective action

If auto-detection fails, provide the path explicitly:

```bash
export USB_ROOT=/path/to/usb/android-nas
nas-android-usb-sync push
```

If Android never exposes a writable filesystem path to Termux, the current automation model cannot fully work on that device without a different integration approach.

## Failure Class: USB Is Not Detected On The Client

### Symptom

- USB insertion produces no link at `~/mnt/android-nas-usb`
- watcher logs show no USB detection

### Required structure

The client expects:

```text
/Volumes/<USB-NAME>/android-nas
```

### Checks

```bash
ls /Volumes
nas-usb-mount
```

### Corrective action

If the path is nonstandard, set it explicitly in:

```bash
~/.config/android-nas/config.env
```

Example:

```bash
USB_ROOT=/Volumes/<USB-NAME>/android-nas
```

## Failure Class: Client Warns That USB Is Not Trustworthy

### Symptom

- client notification says the primary is unavailable and the USB has no completed primary sync timestamp

### Meaning

The client is refusing to silently trust the secondary source because it cannot prove that the USB was refreshed from the Android primary.

### Checks

Inspect:

```bash
ls -la /Volumes/<USB-NAME>/android-nas/.android-nas
```

### Corrective action

Refresh the USB from the Android primary:

```bash
nas-android-usb-sync push
```

Or reconnect the primary to the client and run:

```bash
nas-mobile-usb-sync push-primary all
```

### Interpretation

This warning is a system feature, not a cosmetic annoyance. It protects the client from over-trusting an unverified secondary.

## Failure Class: USB Needs To Recover Changes Back To The Primary

### Symptom

- the USB contains newer continuity data that must be copied back to the Android primary

### Corrective action

Use explicit recovery instead of relying on automatic sync:

```bash
nas-mobile-usb-sync recover-primary all --yes
```

If the command still refuses to run, that is usually expected:

1. the primary is reachable, so recovery is blocked unless you add `--force`
2. the USB lacks a completed primary sync manifest
3. the USB sync manifest is older than the configured freshness window

This is manual by design. Automatic backflow would weaken the source-of-truth model.

## Failure Class: Notifications Do Not Appear

### Android

Checks:

```bash
pkg install termux-api
```

Also confirm the Termux:API app is installed.

### Client

The client uses `osascript` notifications. If the watcher is running but nothing appears:

1. inspect `usb-watch.log` and `usb-watch.err`
2. confirm the LaunchAgent is loaded
3. confirm the account is allowed to show notifications
4. if only informational events are missing, check whether `MAC_NOTIFY_INFO=0` in `~/.config/android-nas/config.env`

## Failure Class: Repeated Sync Activity Or Resource Churn

### Symptom

- frequent mobile-to-USB sync passes
- battery drain
- high I/O or repeated log noise

### Meaning

The watcher is polling, not event-driven. This is currently a simple operational model, not an optimized one.

### Corrective action

- increase `NAS_WATCH_INTERVAL`
- disable the LaunchAgent temporarily if active automation is not needed
- use manual sync commands during controlled handoff windows

## Failure Class: Low-Space Client Still Fills Storage

### Symptom

- local storage grows more than expected while mounted

### Checks

Confirm config:

```bash
grep CLIENT_CACHE_MODE ~/.config/android-nas/config.env
```

### Corrective action

Use:

```bash
CLIENT_CACHE_MODE=spaceless
```

Then remount.

### Limitation

This lowers cache pressure, but it can also make some workloads less smooth. Low-space mode is a tradeoff, not a free optimization.
