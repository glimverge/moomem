# Implement: architecture deepening review

Review-only. Do not edit `src/`, `ci/`, or `examples/` unless the user expands scope.

## Checklist

1. [x] Seed `research/module-map.md` from codebase inspection.
2. [x] Seed `research/deepening-backlog.md` with ranked candidates + keep-as-is.
3. [x] On `task.py start`: re-read map/backlog against `src/` once more; fix any stale paths/line claims.
4. [x] Mark PRD acceptance checkboxes when AC1–AC5 verified.
5. [x] Optional (user ask only): add a short “host vs internal surface” note to `.trellis/spec/library/public-api-and-types.md` (P1 Option A). — **skipped** (default; no blocking hole; leave for follow-up).
6. [x] Self-verify: no product code diffs under `src/`, `ci/`, `examples/` (`git status --porcelain`); research files present. (trellis-check deferred to parent session — implement agent must not spawn trellis-check.)
7. [x] Present backlog summary to user; ask whether to spawn follow-up tasks for P2/P5 and/or P1 Option A.

## Validation

```bash
# No product changes expected:
git status --porcelain
# Research present:
test -f .trellis/tasks/10-01-architecture-deepening/research/module-map.md
test -f .trellis/tasks/10-01-architecture-deepening/research/deepening-backlog.md
```

## Risky files

- None for default scope.
- If optional spec note: `.trellis/spec/library/public-api-and-types.md` only.

## Rollback

Revert task markdown / optional spec note; no data migration.
