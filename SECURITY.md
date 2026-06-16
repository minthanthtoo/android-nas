# Security Policy

## Threat model

This project is designed for a private network where an Android device exposes files over Termux `sshd` and a client mounts them with `rclone`.

It is not hardened for direct Internet exposure.

## Required controls

- Use a strong Termux account password if password login is enabled.
- Prefer SSH public key authentication.
- Keep the device on a trusted LAN or VPN.
- Disable battery optimization for Termux so watchdog-free operation stays predictable.
- Review boot scripts before enabling them on devices with sensitive data.

## Recommended controls

- Restrict router or firewall access to trusted client IPs.
- Use a dedicated Android device profile for NAS duties.
- Rotate SSH keys when a client device is lost or rebuilt.
- Review `~/.local/state/android-nas/rclone.log` on the client when diagnosing repeated reconnects.

## Known limitations

- The default Termux `sshd` setup is operational, not a full enterprise SSH baseline.
- Android power management can still interrupt long-running background services on some vendors unless the OS is configured correctly.

## Reporting

If you use this repository internally, route security findings through your normal engineering or ops process before deploying changes broadly.
