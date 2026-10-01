# Implement: migrate-ci-role-tree

1. Create `ci/gates` `ci/eval` `ci/tools`; `git mv` three packages to target names.
2. Fix hardcoded paths/comments inside moved packages (esp. locomo util + data README).
3. Update `scripts/ci/run-llm-live-gate.sh`, `.github/workflows/test-pipeline.yml`, `README.md` commands.
4. Validate locomo + retrieval-tuning offline; verify old dirs gone; smoke-compile live-llm if possible without secrets.
5. Do not touch examples/ or doc 10 migration banner (child 3).

## Validation commands

```bash
test -d ci/gates/live-llm && test -d ci/eval/locomo && test -d ci/tools/retrieval-tuning
test ! -d ci/llm_live && test ! -d ci/locomo && test ! -d ci/tuning
moon run ci/eval/locomo --target native
moon run ci/tools/retrieval-tuning --target native
```
