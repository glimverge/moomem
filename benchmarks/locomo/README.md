# LoCoMo release benchmarks

Versioned L3 eval archives produced after a successful (non dry-run) release.
Harness entry remains `moon run ci/eval/locomo --target native`; this tree is the
**machine-readable archive** consumed by the docs site.

## Layout

| Path | Role |
|------|------|
| `schema.json` | JSON Schema for one result file |
| `results/<version>.json` | One file per released module version |
| `latest.json` | Pointer `{ "version": "<semver>" }` for the site |

## How results are written

1. Release pipeline job `benchmark-archive` (after publish/tag) runs
   `scripts/ci/run-locomo-benchmark-archive.sh`.
2. Script runs offline + api + live, merges reports into `results/<version>.json`,
   updates `latest.json`, and commits with `chore(benchmark):`.
3. Push to `main` triggers Pages deploy; the site copies this tree at build time.

Local dry run (writes files, does not commit/push):

```bash
# optional: load .env then map QWEN_* → MOOMEM_EMBED_*
set -a && source .env && set +a
NEW_VERSION=0.0.0-dev SKIP_COMMIT=1 bash scripts/ci/run-locomo-benchmark-archive.sh
```

## License note

Scores are derived from the LoCoMo **subset** under `ci/eval/locomo/data/`
(CC BY-NC 4.0). This directory stores **metrics only** — not the full LoCoMo
dataset. See `ci/eval/locomo/data/README.md` for attribution and redistribution
limits.

## Secrets

Result JSON must never contain API keys. Only model ids, dims, metrics, and
gate statuses are allowed.
