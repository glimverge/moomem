#!/usr/bin/env bash
# Commit moon.mod bump, create v* tag, push branch + tag.
# Requires: NEW_VERSION, BASE_VERSION, BUMP, GITHUB_REF_NAME
set -euo pipefail

NEW_VERSION="${NEW_VERSION:?NEW_VERSION is required}"
BASE_VERSION="${BASE_VERSION:?BASE_VERSION is required}"
BUMP="${BUMP:?BUMP is required}"
GITHUB_REF_NAME="${GITHUB_REF_NAME:?GITHUB_REF_NAME is required}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

tag="v${NEW_VERSION}"
if git rev-parse "${tag}" >/dev/null 2>&1; then
  echo "Tag ${tag} already exists" >&2
  exit 1
fi

git add moon.mod
git commit -m "chore: release ${tag} (${BUMP} from ${BASE_VERSION})"
git tag "${tag}"

git push origin "HEAD:${GITHUB_REF_NAME}"
git push origin "${tag}"
