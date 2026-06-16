#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

mapfile -t scripts < <(find "${REPO_ROOT}/scripts" -type f ! -name '*.md' | sort)

if [[ "${#scripts[@]}" -eq 0 ]]; then
  printf 'No scripts found.\n' >&2
  exit 1
fi

printf 'Running bash syntax validation...\n'
for script in "${scripts[@]}"; do
  bash -n "$script"
done

if command -v shellcheck >/dev/null 2>&1; then
  printf 'Running shellcheck...\n'
  shellcheck "${scripts[@]}"
else
  printf 'shellcheck not installed locally; skipping lint.\n'
fi

printf 'Validation complete.\n'
