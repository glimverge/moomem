#!/usr/bin/env bash
# Run LoCoMo --live locally and merge the run into benchmarks/locomo/results/<version>.json.
#
# Release CI archives offline+api only (SKIP_LIVE=1). Operators fill live locally, then commit.
#
# Env:
#   NEW_VERSION   optional — defaults to benchmarks/locomo/latest.json "version"
#   LIVE_EXTRACT_LIMIT  optional — 0 = full 100 gold cases (default); set e.g. 20 for a smoke subset
#   SKIP_COMMIT   if "1", write files but do not git commit (still no push)
#   SKIP_PUSH     if "1", commit locally but do not push (default: push when committing)
#
# Secrets (never written to JSON):
#   DEEPSEEK_API_KEY / DEEPSEEK_BASE_URL / DEEPSEEK_MODEL
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

OUT_DIR="${ROOT}/benchmarks/locomo"
RESULTS_DIR="${OUT_DIR}/results"
LATEST_FILE="${OUT_DIR}/latest.json"

if [[ -z "${NEW_VERSION:-}" ]]; then
  if [[ ! -f "${LATEST_FILE}" ]]; then
    echo "ERROR: NEW_VERSION unset and ${LATEST_FILE} missing" >&2
    exit 1
  fi
  NEW_VERSION="$(python3 -c "import json; print(json.load(open('${LATEST_FILE}'))['version'])")"
fi

RESULT_FILE="${RESULTS_DIR}/${NEW_VERSION}.json"
if [[ ! -f "${RESULT_FILE}" ]]; then
  echo "ERROR: missing ${RESULT_FILE} — run release archive (offline+api) first" >&2
  exit 1
fi

for v in DEEPSEEK_API_KEY DEEPSEEK_BASE_URL DEEPSEEK_MODEL; do
  if [[ -z "${!v:-}" ]]; then
    echo "ERROR: missing env ${v}" >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
REPORT="${TMP_DIR}/live.json"
LOG="${TMP_DIR}/live.log"

LIVE_EXTRACT_LIMIT="${LIVE_EXTRACT_LIMIT:-0}"
EXTRA_ARGS=(--live --report "${REPORT}" --report-only-exit)
if [[ "${LIVE_EXTRACT_LIMIT}" != "0" ]]; then
  EXTRA_ARGS+=(--extract-limit "${LIVE_EXTRACT_LIMIT}")
  export MOOMEM_LOCOMO_EXTRACT_LIMIT="${LIVE_EXTRACT_LIMIT}"
fi

echo "==> LoCoMo live (local) → ${RESULT_FILE}"
echo "    extract_limit=${LIVE_EXTRACT_LIMIT} (0 = all 100)"
set +e
moon run ci/eval/locomo --target native -- "${EXTRA_ARGS[@]}" 2>&1 | tee "${LOG}"
rc=${PIPESTATUS[0]}
set -e

if [[ ! -f "${REPORT}" ]]; then
  echo "ERROR: live report missing (exit ${rc})" >&2
  exit 1
fi

python3 - "${REPORT}" "${RESULT_FILE}" <<'PY'
import json, sys
from pathlib import Path

report_path, result_path = map(Path, sys.argv[1:3])
mode = json.loads(report_path.read_text())
if "run" not in mode:
    raise SystemExit(f"bad live report (missing run): {report_path}")

blob = json.dumps(mode)
for bad in ("api_key", "API_KEY", "Bearer "):
    if bad in blob:
        raise SystemExit(f"refusing to archive: report contains suspicious token {bad!r}")
if "sk-" in blob:
    raise SystemExit("refusing to archive: report looks like it contains an API key")

doc = json.loads(result_path.read_text())
doc.setdefault("runs", {})["live"] = mode["run"]
result_path.write_text(json.dumps(doc, indent=2) + "\n")
print(f"merged live into {result_path}")
scored = mode["run"].get("metrics", {}).get("extraction_cases_scored")
total = mode["run"].get("metrics", {}).get("extraction_cases_total")
status = mode["run"].get("status")
print(f"live status={status} extraction_cases={scored}/{total}")
PY

if grep -Eiq 'api[_-]?key|sk-[a-zA-Z0-9]|Bearer[[:space:]]' "${RESULT_FILE}"; then
  echo "ERROR: result file appears to contain secrets" >&2
  exit 1
fi

if [[ "${SKIP_COMMIT:-0}" == "1" ]]; then
  echo "SKIP_COMMIT=1 — left live merge on disk only"
  exit 0
fi

git add "${RESULT_FILE}"
if git diff --cached --quiet; then
  echo "No benchmark file changes to commit"
  exit 0
fi

git commit -m "chore(benchmark): fill LoCoMo live results for ${NEW_VERSION}"

if [[ "${SKIP_PUSH:-0}" == "1" ]]; then
  echo "SKIP_PUSH=1 — committed locally only"
  exit 0
fi

git push origin HEAD
echo "live benchmark committed and pushed for ${NEW_VERSION}"
