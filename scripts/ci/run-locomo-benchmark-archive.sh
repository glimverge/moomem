#!/usr/bin/env bash
# Run LoCoMo offline + api + live, merge into benchmarks/locomo/results/<version>.json.
#
# Env:
#   NEW_VERSION   required (e.g. 0.2.3) — module version / file basename
#   GIT_TAG       optional (default v${NEW_VERSION})
#   SKIP_COMMIT   if "1", write files but do not git commit/push
#   SKIP_API      if "1", skip --embedder api (record error/skipped)
#   SKIP_LIVE     if "1", skip --live
#   LIVE_EXTRACT_LIMIT  extraction gold cases for --live (default 20; 0 = all 100)
#
# Secrets (never written to JSON):
#   DEEPSEEK_* for --live
#   MOOMEM_EMBED_* for --embedder api (or QWEN_* mapped below)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

NEW_VERSION="${NEW_VERSION:?NEW_VERSION is required}"
GIT_TAG="${GIT_TAG:-v${NEW_VERSION}}"
OUT_DIR="${ROOT}/benchmarks/locomo"
RESULTS_DIR="${OUT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# Map QWEN_* → MOOMEM_EMBED_* when the latter are unset (local .env / ops alias).
if [[ -z "${MOOMEM_EMBED_API_KEY:-}" && -n "${QWEN_API_KEY:-}" ]]; then
  export MOOMEM_EMBED_API_KEY="${QWEN_API_KEY}"
fi
if [[ -z "${MOOMEM_EMBED_BASE_URL:-}" && -n "${QWEN_BASE_URL:-}" ]]; then
  export MOOMEM_EMBED_BASE_URL="${QWEN_BASE_URL}"
fi
if [[ -z "${MOOMEM_EMBED_MODEL:-}" && -n "${QWEN_MODEL:-}" ]]; then
  export MOOMEM_EMBED_MODEL="${QWEN_MODEL}"
fi

run_mode() {
  local mode="$1"
  shift
  local report="${TMP_DIR}/${mode}.json"
  local log="${TMP_DIR}/${mode}.log"
  echo "==> LoCoMo ${mode}"
  set +e
  moon run ci/eval/locomo --target native -- "$@" --report "${report}" --report-only-exit \
    2>&1 | tee "${log}"
  local rc=${PIPESTATUS[0]}
  set -e
  if [[ ! -f "${report}" ]]; then
    echo "ERROR: missing report for ${mode} (exit ${rc})" >&2
    # Network / harness crash: fail the archive job (D3: process errors fail job).
    return 1
  fi
  # Gate misses are OK for api/live under --report-only-exit; offline should still pass.
  if [[ "${mode}" == "offline" ]]; then
    if ! grep -q '^LOCOMO_PASS$' "${log}"; then
      echo "ERROR: offline LoCoMo did not print LOCOMO_PASS" >&2
      return 1
    fi
  fi
  return 0
}

run_mode offline
if [[ "${SKIP_API:-0}" != "1" ]]; then
  run_mode api --embedder api
else
  echo '{"mode":"api","run":{"embedder":"api","model":null,"dim":null,"extractor_model":null,"metrics":{},"gates":{"overall":"skipped"},"status":"skipped"}}' \
    > "${TMP_DIR}/api.json"
fi
if [[ "${SKIP_LIVE:-0}" != "1" ]]; then
  # Archive smoke subset (full 100-case live remains a manual command; see docs/project/08).
  LIVE_EXTRACT_LIMIT="${LIVE_EXTRACT_LIMIT:-20}"
  export MOOMEM_LOCOMO_EXTRACT_LIMIT="${LIVE_EXTRACT_LIMIT}"
  run_mode live --live --extract-limit "${LIVE_EXTRACT_LIMIT}"
else
  echo '{"mode":"live","run":{"embedder":"hashing","model":null,"dim":null,"extractor_model":null,"metrics":{},"gates":{"overall":"skipped"},"status":"skipped"}}' \
    > "${TMP_DIR}/live.json"
fi

COMMITTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
RESULT_FILE="${RESULTS_DIR}/${NEW_VERSION}.json"

python3 - "${TMP_DIR}" "${RESULT_FILE}" "${NEW_VERSION}" "${GIT_TAG}" "${COMMITTED_AT}" <<'PY'
import json, sys
from pathlib import Path

tmp, out_path, version, git_tag, committed_at = sys.argv[1:6]

def load_run(path: Path):
    data = json.loads(path.read_text())
    if "run" not in data:
        raise SystemExit(f"bad mode report (missing run): {path}")
    # Reject accidental secret leakage
    blob = json.dumps(data)
    for bad in ("api_key", "API_KEY", "sk-", "Bearer "):
        if bad in blob and bad != "sk-" :
            raise SystemExit(f"refusing to archive: report contains suspicious token {bad!r}")
        if bad == "sk-" and "sk-" in blob:
            raise SystemExit("refusing to archive: report looks like it contains an API key")
    return data["run"]

runs = {
    "offline": load_run(Path(tmp) / "offline.json"),
    "api": load_run(Path(tmp) / "api.json"),
    "live": load_run(Path(tmp) / "live.json"),
}

doc = {
    "schema_version": 1,
    "module": "heyq02/moomem",
    "version": version,
    "git_tag": git_tag,
    "committed_at": committed_at,
    "fixture": {
        "path": "ci/eval/locomo/data/locomo_subset.json",
        "note": "CC BY-NC 4.0 subset",
    },
    "runs": runs,
}

Path(out_path).write_text(json.dumps(doc, indent=2) + "\n")
print(f"wrote {out_path}")
PY

# latest.json pointer
printf '%s\n' "{\"version\": \"${NEW_VERSION}\"}" > "${OUT_DIR}/latest.json"

# Secret scan on final artifact
if grep -Eiq 'api[_-]?key|sk-[a-zA-Z0-9]|Bearer[[:space:]]' "${RESULT_FILE}"; then
  echo "ERROR: result file appears to contain secrets" >&2
  exit 1
fi

if [[ "${SKIP_COMMIT:-0}" == "1" ]]; then
  echo "SKIP_COMMIT=1 — left results on disk only"
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git add \
  "${OUT_DIR}/latest.json" \
  "${RESULT_FILE}" \
  "${OUT_DIR}/schema.json" \
  "${OUT_DIR}/README.md"

if git diff --cached --quiet; then
  echo "No benchmark file changes to commit"
  exit 0
fi

git commit -m "chore(benchmark): archive LoCoMo results for ${NEW_VERSION}"
git push origin HEAD:main

echo "benchmark archive committed for ${NEW_VERSION}"
