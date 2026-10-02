#!/usr/bin/env bash
# Local LoCoMo benchmark archive: offline hashing → benchmarks/locomo/results/<version>.json.
# API embedder and live extraction are host-side; this script records them as skipped.
# Not invoked by the release pipeline (publish ends after GitHub Release).
#
# Env:
#   NEW_VERSION   required (e.g. 0.4.0) — module version / file basename
#   GIT_TAG       optional (default v${NEW_VERSION})
#   SKIP_COMMIT   if "1", write files but do not git commit/push
#   SKIP_PUSH     if "1", commit locally but do not push (ignored when SKIP_COMMIT=1)
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
    return 1
  fi
  if [[ "${mode}" == "offline" ]]; then
    if ! grep -q '^LOCOMO_PASS$' "${log}"; then
      echo "ERROR: offline LoCoMo did not print LOCOMO_PASS" >&2
      return 1
    fi
  fi
  return 0
}

run_mode offline
echo '{"mode":"api","run":{"embedder":"api","model":null,"dim":null,"extractor_model":null,"metrics":{},"gates":{"overall":"skipped"},"status":"skipped"}}' \
  > "${TMP_DIR}/api.json"
echo '{"mode":"live","run":{"embedder":"hashing","model":null,"dim":null,"extractor_model":null,"metrics":{"extraction_status":"skipped"},"gates":{"overall":"skipped"},"status":"skipped"}}' \
  > "${TMP_DIR}/live.json"

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
    blob = json.dumps(data)
    for bad in ("api_key", "API_KEY", "Bearer "):
        if bad in blob:
            raise SystemExit(f"refusing to archive: report contains suspicious token {bad!r}")
    if "sk-" in blob:
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

printf '%s\n' "{\"version\": \"${NEW_VERSION}\"}" > "${OUT_DIR}/latest.json"

if grep -Eiq 'api[_-]?key|sk-[a-zA-Z0-9]|Bearer[[:space:]]' "${RESULT_FILE}"; then
  echo "ERROR: result file appears to contain secrets" >&2
  exit 1
fi

if [[ "${SKIP_COMMIT:-0}" == "1" ]]; then
  echo "SKIP_COMMIT=1 — left results on disk only"
  exit 0
fi

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

if [[ "${SKIP_PUSH:-0}" == "1" ]]; then
  echo "SKIP_PUSH=1 — committed locally only"
  exit 0
fi

git push origin HEAD
echo "benchmark archive committed and pushed for ${NEW_VERSION}"
