#!/usr/bin/env bash
# Fail if DEEPSEEK_* secret/vars required for the live LLM gate are missing.
set -euo pipefail

missing=0
if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
  echo "Missing secret DEEPSEEK_API_KEY" >&2
  missing=1
fi
if [[ -z "${DEEPSEEK_BASE_URL:-}" ]]; then
  echo "Missing variable DEEPSEEK_BASE_URL" >&2
  missing=1
fi
if [[ -z "${DEEPSEEK_MODEL:-}" ]]; then
  echo "Missing variable DEEPSEEK_MODEL" >&2
  missing=1
fi
if [[ "${missing}" -ne 0 ]]; then
  echo "Configure repo Secrets/Variables before release." >&2
  exit 1
fi

# Do not print key; show non-secret config only
echo "DEEPSEEK_BASE_URL=${DEEPSEEK_BASE_URL}"
echo "DEEPSEEK_MODEL=${DEEPSEEK_MODEL}"
