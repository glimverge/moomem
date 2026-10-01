#!/usr/bin/env bash
# Run live LLM gate and require LIVE_LLM_PASS in output.
set -euo pipefail

log="${1:-/tmp/llm-live.log}"
moon run ci/gates/live-llm --target native | tee "${log}"
grep -q '^LIVE_LLM_PASS$' "${log}"
