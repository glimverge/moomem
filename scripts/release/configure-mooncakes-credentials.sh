#!/usr/bin/env bash
# Write MOONCAKES_TOKEN into ~/.moon/credentials.json for moon publish.
set -euo pipefail

if [[ -z "${MOONCAKES_TOKEN:-}" ]]; then
  echo "MOONCAKES_TOKEN secret is not set." >&2
  echo "1) Locally: moon login" >&2
  echo "2) Copy full contents of ~/.moon/credentials.json" >&2
  echo "3) GitHub → Settings → Secrets → Actions → MOONCAKES_TOKEN" >&2
  exit 1
fi

mkdir -p "${HOME}/.moon"
printf '%s' "${MOONCAKES_TOKEN}" > "${HOME}/.moon/credentials.json"
chmod 600 "${HOME}/.moon/credentials.json"
