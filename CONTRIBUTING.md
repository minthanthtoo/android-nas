# Contributing

## Standards

- Keep scripts idempotent.
- Preserve `set -euo pipefail` in executable shell scripts.
- Prefer explicit health checks over optimistic success messages.
- Do not add silent shell profile mutations unless there is a flag for them.

## Local checks

```bash
make test
```

If `shellcheck` is installed locally, `make test` will run it automatically.

## Compatibility target

- Termux on Android for the server
- macOS for the client helper scripts

Linux support can be added later, but changes should not regress macOS behavior.
