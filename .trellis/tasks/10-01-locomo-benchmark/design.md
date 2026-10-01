# Design: LoCoMo release benchmark archive + site page

## Architecture

```
release-pipeline (existing)
  quality (incl. offline eval-locomo hard gate)
  llm-live (L2 hard gate)
  release (publish + tag) ──success, !dry_run──► benchmark-archive (NEW)
                                                    │
                                                    ├─ run offline / api / live
                                                    ├─ write JSON under benchmarks/locomo/
                                                    └─ commit+push main (chore(benchmark):)
                                                          │
                                                          └─ deploy.yml (existing) → Pages
site/docs/benchmark/index.mdx  ──reads──► benchmarks/locomo/results + latest
```

Two seams:

1. **Eval producer** — extend `ci/eval/locomo` (or thin shell wrapper) to emit one machine-readable report per run mode.
2. **Archive + present** — CI writes versioned JSON into git; Rspress page renders summary / breakdown / Δ.

## Data layout

```
benchmarks/locomo/
  README.md                 # purpose, license note, schema pointer
  schema.json               # JSON Schema for one result file (optional but preferred)
  results/
    0.2.3.json              # one file per released version
  latest.json               # copy or { "version": "0.2.3" } pointer for the site
```

### Result file shape (logical)

```jsonc
{
  "schema_version": 1,
  "module": "heyq02/moomem",
  "version": "0.2.3",
  "git_tag": "v0.2.3",
  "committed_at": "ISO-8601",
  "fixture": { "path": "ci/eval/locomo/data/locomo_subset.json", "note": "CC BY-NC 4.0 subset" },
  "runs": {
    "offline": { "embedder": "hashing", "metrics": {}, "gates": {}, "status": "pass|fail|error" },
    "api": { "embedder": "api", "model": "...", "dim": 1024, "metrics": {}, "gates": {}, "status": "..." },
    "live": { "extractor_model": "...", "metrics": {}, "gates": {}, "status": "..." }
  }
}
```

Metrics to capture (aligned with 08 report / harness stdout):

| Area | Fields |
|------|--------|
| Retrieval | `hybrid_recall_at_5`, `hybrid_mrr_at_5`, `bm25_recall_at_5`, `bm25_mrr_at_5`, `vs_bm25_pct`, `target_15pct` (met/missed/n_a) |
| Conflict | `near_dup_supersede_rate`, `near_dup_ok`, `near_dup_total` |
| Isolation | `cross_user_leaks` |
| Persistence | `reopen_ok` (bool/int) |
| Extraction | `precision`, `hit`, `denom` (live only; offline `skipped`) |

**Never** serialize env values that look like keys. Record model ids and base_url host only if needed (prefer model id + dim).

## Harness changes

- Add `--report <path>` (or env `MOOMEM_LOCOMO_REPORT`) to write the above JSON for the **current** run mode.
- Add `--report-only-exit` (or archive wrapper): for api/live, always exit 0 after writing report when process completed (even if internal gates failed). Offline used by push CI keeps today’s fail-on-gate behavior unless `--report-only-exit`.
- Prefer implementing exit policy in a **shell wrapper** under `scripts/ci/` so push job command stays unchanged:
  - Push: `moon run ci/eval/locomo --target native` (unchanged).
  - Archive: `scripts/ci/run-locomo-benchmark-archive.sh` runs three modes, merges into one versioned file, maps `QWEN_*` → `MOOMEM_EMBED_*`.

## Release workflow

New job `benchmark-archive` on `release-pipeline.yml`:

- `needs: release`
- `if: github.event.inputs.dry_run != 'true'`
- Permissions: `contents: write`
- Env: existing `DEEPSEEK_*`; plus `MOOMEM_EMBED_*` from secrets/vars (or map from `QWEN_*` if those names are what ops configured — verify against repo secrets; document both).
- Steps: checkout main → setup moon → run archive script with `NEW_VERSION` from release outputs → commit only `benchmarks/locomo/**` → push.
- Concurrency: avoid fighting deploy; sequential after release is enough.
- Failure policy: script/network errors **fail the archive job** (visible red X) but do not roll back the published package; gate misses inside api/live do **not** fail the job (D3).

Version source: reuse `steps.ver.outputs.mod_version` from release job via `needs.release.outputs` (add job outputs if missing).

## Site page

- Path: `site/docs/benchmark/index.mdx` (or `.md` + small React component if MDX needed for tables).
- Nav: add entry in `site/docs/_nav.json` → “Benchmark”.
- Data loading: build-time import of `../../benchmarks/locomo/latest.json` + glob/list `results/*.json` (Rspress/Node). If bundler cannot reach outside `site/`, add a tiny prebuild step in `pnpm run build` / `deploy.yml` that copies `benchmarks/locomo` → `site/docs/public/benchmark-data/` — prefer copy step for isolation.
- UI (D5):
  1. Hero line: latest version + overall strip (offline/api/live status chips).
  2. Summary table: version rows × key metrics.
  3. Breakdown for latest: retrieval / conflict / isolation / persistence / extraction.
  4. Diff vs previous version file (numeric Δ + gate status change).
- No cards-heavy dashboard; one page, one job. Keep Rspress theme constraints; do not rebuild whole site brand in this task.

## Compatibility / risks

| Risk | Mitigation |
|------|------------|
| api gate fail kills moon process | `--report-only-exit` or wrapper captures metrics then exit 0 |
| Bot commit loops workflows | Push with `GITHUB_TOKEN`; ensure archive commit does not re-trigger release; deploy-only on main is OK |
| Secret leakage into JSON | Schema allowlist; code review grep for `api_key` |
| QWEN vs MOOMEM_EMBED naming | Archive script exports mapping; README + AC6 |
| Long api run (~8 min) | Job timeout ≥ 30–40 min; document |
| Site cannot import outside root | Copy-to-public prebuild |

## Rollback

- Revert workflow job + harness flags; leave historical `benchmarks/locomo/results/*.json` (harmless).
- Site page can be removed from `_nav.json` independently.

## Out of design

Fusion tuning, full LoCoMo dump, per-QA pages, dry-run archival.
