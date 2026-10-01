# Implement: LoCoMo release benchmark archive + site page

## Checklist (ordered)

1. **Schema + directory**
   - Create `benchmarks/locomo/{README.md,schema.json,results/.gitkeep}` and document CC BY-NC note for fixture (not redistributing full LoCoMo).
2. **Harness report output**
   - Extend `ci/eval/locomo` to write JSON report (`--report` / env) with metrics + gates for current mode.
   - Keep default CLI behavior for push: offline still fails hard on gates.
3. **Archive wrapper**
   - Add `scripts/ci/run-locomo-benchmark-archive.sh`: map `QWEN_*`→`MOOMEM_EMBED_*`, run offline + api + live with report-only exit for api/live, merge into `benchmarks/locomo/results/<version>.json` + update `latest.json`.
4. **Release wiring**
   - Add `benchmark-archive` job after `release` (skip dry-run); pass version outputs; `contents: write`; commit with `chore(benchmark): archive LoCoMo results for <version>`.
   - Document required GitHub secrets/vars (`DEEPSEEK_*`, `MOOMEM_EMBED_*` or `QWEN_*`).
5. **Site page**
   - Add `site/docs/benchmark/` page + `_nav.json` entry.
   - Ensure build can read data (copy step in site build / deploy if needed).
   - Render summary, breakdown, Δ vs previous (D5). Seed with one fixture result (e.g. from 08 numbers) so the page is not empty before first release run.
6. **Docs touch**
   - Short pointer in README L3 section + `docs/project/10-testing-examples-architecture.md` or 05: “release archive path”.
7. **Validate**
   - Offline: `moon run ci/eval/locomo --target native` → `LOCOMO_PASS`.
   - Local dry archive (if keys in `.env`): run wrapper against a fake version `0.0.0-dev` without pushing.
   - `pnpm` site build (or package script) includes benchmark page.
   - Confirm result JSON has no secret-looking fields.

## Validation commands

```bash
moon run ci/eval/locomo --target native
# with report:
# moon run ci/eval/locomo --target native -- --report /tmp/offline.json
test -f benchmarks/locomo/schema.json
# site (from repo root or site/ per existing deploy):
pnpm install && pnpm run build   # adjust if build lives under site/
```

## Risky files / rollback points

| Area | Files | Rollback |
|------|-------|----------|
| Harness | `ci/eval/locomo/*.mbt` | Revert report flags; push command unchanged |
| CI | `.github/workflows/release-pipeline.yml`, `scripts/ci/run-locomo-benchmark-archive.sh` | Remove job |
| Data | `benchmarks/locomo/results/*` | Keep or delete files; no runtime coupling |
| Site | `site/docs/benchmark/*`, `_nav.json`, optional copy in deploy | Remove nav entry |

## Parent / child note

Single task owns both archive and site (tight coupling on schema). If execution needs parallel agents, split later into `locomo-results-archive` then `site-benchmark-page` with schema freeze between them.

## Before `task.py start`

- [x] PRD converged (D1–D5)
- [x] design.md + implement.md written
- [ ] implement.jsonl / check.jsonl curated (real specs)
- [ ] User reviewed artifacts / approved start
