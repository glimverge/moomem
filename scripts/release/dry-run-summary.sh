#!/usr/bin/env bash
# Print dry-run summary for a release dispatch.
# Requires: MODULE_NAME, BASE_VERSION, MOD_VERSION, BUMP
set -euo pipefail

MODULE_NAME="${MODULE_NAME:?MODULE_NAME is required}"
BASE_VERSION="${BASE_VERSION:?BASE_VERSION is required}"
MOD_VERSION="${MOD_VERSION:?MOD_VERSION is required}"
BUMP="${BUMP:?BUMP is required}"

echo "Dry-run complete for ${MODULE_NAME}@${MOD_VERSION}"
echo "Would bump: ${BASE_VERSION} → ${MOD_VERSION} (${BUMP})"
echo "Skipped: moon publish, git commit/tag, GitHub Release"
echo "Completed gates: quality + live LLM"
