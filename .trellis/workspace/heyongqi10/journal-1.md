# Journal - heyongqi10 (Part 1)

> AI development session journal
> Started: 2026-10-01

---



## Session 1: Bootstrap Trellis specs for moomem

**Date**: 2026-10-01
**Task**: Bootstrap Trellis specs for moomem
**Branch**: `main`

### Summary

Replaced fullstack frontend/backend templates with library and CLI specs from the MoonBit codebase; archived 00-bootstrap-guidelines.

### Main Changes

- Detailed change bullets were not supplied; see the summary above.

### Git Commits

| Hash | Message |
|------|---------|
| `74ed4b2` | (see git log) |
| `8af072d` | (see git log) |
| `afda32f` | (see git log) |
| `3395917` | (see git log) |
| `2bafa35` | (see git log) |
| `49773fa` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 2: Architecture deepening wave 1 (docs + Clock split)

**Date**: 2026-10-01
**Task**: Architecture deepening wave 1 (docs + Clock split)
**Branch**: `main`

### Summary

Executed deepening children: synced architecture/docs routing (P2+P5), Trellis host-vs-internal and FS call-site rules (P1A+P4), moved Clock to src/clock.mbt (P3). Parent and three children archived.

### Main Changes

- Detailed change bullets were not supplied; see the summary above.

### Git Commits

| Hash | Message |
|------|---------|
| `753e679` | (see git log) |
| `ab5a356` | (see git log) |
| `c824472` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 3: Architecture deepening wave 2

**Date**: 2026-10-01
**Task**: Architecture deepening wave 2
**Branch**: `main`

### Summary

P1 Option B: package-private indexes/dedup; P6: private helpers for MemoryStore.add; P7: docs track retrieval fusion as W5/eval without splitting MemoryStore.

### Main Changes

- Detailed change bullets were not supplied; see the summary above.

### Git Commits

| Hash | Message |
|------|---------|
| `d36cdc2` | (see git log) |
| `5a90c93` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 4: 混合检索自适应融合（P7）

**Date**: 2026-10-01
**Task**: 混合检索自适应融合（P7）
**Branch**: `main`

### Summary

默认 AdaptiveLexical + protect_bm25_topk；LoCoMo api hybrid=BM25 0.435 硬门槛过；stretch +15% 未达。任务已归档。

### Main Changes

## Done
- Config: FusionPolicy AdaptiveLexical (default) / EqualRrf rollback
- ranker: rrf_weighted, lexical_strong, protect_bm25_topk
- retrieval-tuning: equal vs adaptive + grid (no LoCoMo tuning)
- Holdout: offline+api hybrid Recall@5 = BM25 0.435, LOCOMO_PASS
- Spec/README/site notes updated; archived to archive/2026-10/

## Stretch
- TARGET_15PCT still missed (non-blocking)


### Git Commits

| Hash | Message |
|------|---------|
| `cfaefc0` | (see git log) |
| `4177aec` | (see git log) |
| `1317a6c` | (see git log) |
| `deb239a` | (see git log) |
| `af30ff7` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 5: README 分流与 LoCoMo 基准归档收口

**Date**: 2026-10-01
**Task**: README 分流与 LoCoMo 基准归档收口
**Branch**: `main`

### Summary

归档 readme-value-narrative 与 locomo-benchmark；push main。

### Main Changes

Archived remaining in-progress tasks after AC verification; pushing main.


### Git Commits

| Hash | Message |
|------|---------|
| `cfdf2e7` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete
