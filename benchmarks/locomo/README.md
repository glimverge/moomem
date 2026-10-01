# LoCoMo release benchmarks

Versioned L3 eval archives produced **locally** after a mooncakes publish (not by
GitHub Actions). Harness: `moon run ci/eval/locomo --target native`. This tree is
the machine-readable archive consumed by the docs site.

## Layout

| Path | Role |
|------|------|
| `schema.json` | JSON Schema for one result file |
| `results/<version>.json` | One file per released module version |
| `latest.json` | Pointer `{ "version": "<semver>" }` for the site |

## How results are written

Release pipeline stops after Publish / tag / GitHub Release. Operators archive
benchmarks on a machine with `.env` (QWEN→embed + DeepSeek):

```bash
set -a && source .env && set +a
# NEW_VERSION must match the published moon.mod / tag (e.g. 0.4.0)
NEW_VERSION=0.4.0 bash scripts/ci/run-locomo-benchmark-archive.sh
# runs offline + api + live (full 100 extract cases by default), then commit + push
#
# SKIP_COMMIT=1          write JSON only
# SKIP_PUSH=1            commit, no push
# SKIP_API=1 / SKIP_LIVE=1
# LIVE_EXTRACT_LIMIT=20  smoke subset for live extraction
```

If offline+api already exist and only live is missing:

```bash
set -a && source .env && set +a
bash scripts/ci/run-locomo-live-local.sh   # defaults to latest.json version
```

Push to `main` triggers Pages deploy; the site copies this tree at build time.

## License note

Scores are derived from the LoCoMo **subset** under `ci/eval/locomo/data/`
(CC BY-NC 4.0). This directory stores **metrics only** — not the full LoCoMo
dataset. See `ci/eval/locomo/data/README.md` for attribution and redistribution
limits.

## Secrets

Result JSON must never contain API keys. Only model ids, dims, metrics, and
gate statuses are archived.
