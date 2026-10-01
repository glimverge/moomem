# Design: migrate-ci-role-tree

## Moves

| From | To |
|------|-----|
| `ci/llm_live/` | `ci/gates/live-llm/` |
| `ci/locomo/` | `ci/eval/locomo/` |
| `ci/tuning/` | `ci/tools/retrieval-tuning/` |

Create parent dirs `ci/gates`, `ci/eval`, `ci/tools` as needed. Prefer `git mv` to preserve history.

## Code path fixes

- `ci/eval/locomo/util.mbt` (and any siblings): default fixture / usage strings `ci/locomo/...` → `ci/eval/locomo/...`
- File header comments in mains: update `moon run` paths
- `ci/eval/locomo/data/README.md`: path mentions

## CI / scripts / README

- `test-pipeline.yml`: `moon run ci/eval/locomo --target native`
- `scripts/ci/run-llm-live-gate.sh`: `moon run ci/gates/live-llm`
- `README.md`: tuning / locomo / live command lines

Leave doc 05/09/architecture bulk path rewrites to `align-docs-after-migrate`; only touch what would break operators today (README + workflows + scripts).

## Validation

```bash
moon run ci/eval/locomo --target native
moon run ci/tools/retrieval-tuning --target native
moon check --target native   # or check the live-llm package builds
test ! -d ci/llm_live && test ! -d ci/locomo && test ! -d ci/tuning
```

## Risks

- Hyphenated dirs (`live-llm`, `retrieval-tuning`): if `moon run` rejects, fall back is not allowed without updating parent blueprint—verify early with a probe after move.
- Relative fixture paths from cwd assume repo root (same as today).
