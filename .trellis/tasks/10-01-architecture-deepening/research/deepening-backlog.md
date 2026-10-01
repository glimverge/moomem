# Deepening backlog (ranked)

Rank = **leverage for callers/tests** × **clarity gain**, discounted by **risk to MemoryStore / AC / ci**.

Status for this Trellis task: **document only**. Each item is a candidate for a future implementation task.

Verified against live tree on 2026-10-01.

## Keep as-is (do not deepen / do not split)

| Item | Why |
|------|-----|
| `MemoryStore` host **interface** (six methods + list/export/import) | Already **deep**; deletion test fails badly for callers |
| Trait **seams**: Embedder / Extractor / ConflictJudge / PersistenceBackend / Clock | Each has ≥2 **adapters**; real seams |
| `src/llm_extractor/` as separate package | Protects “core has no mizchi/llm” invariant; improves **locality** |
| Dual-slot snapshot + head semantics | Intentional vs append-JSONL; changing it is product work, not deepening |
| CLI as thin **adapter** over store | Shallowness is correct here |

## Ranked opportunities

### P1 — Tighten internal index/dedup visibility (or document them as supported test/CI surface)

| Field | Content |
|-------|---------|
| Problem | `VectorIndex`, `KeywordIndex`, `DedupIndex`, `tokenize`, `rrf`, `cosine_similarity`, `keyword_jaccard` are `pub` and used as a second **interface** by tests and (for tokenize/cosine/jaccard) by `ci/locomo/conflict_eval.mbt`. Looks like architecture sprawl; new code may treat them as host API. |
| Candidate module | Internal retrieval/dedup cluster behind `MemoryStore` |
| Current interface | Full CRUD + helpers exported from core package |
| Proposed interface (future) | **Option A:** keep `pub` but document in `.trellis/spec` as “supported internal test surface / CI diagnostics, not host API”. **Option B:** narrow visibility if MoonBit allows package-private; move isolation tests to store-level where possible; leave `tokenize`/`cosine_similarity`/`keyword_jaccard` exported only if `ci/locomo` still needs them (or give ci a thin diagnostic facade). |
| Dependency category | In-process |
| Test-surface impact | High for Option B (`index_test.mbt`, parts of `extractor_test`, `qa_*`, `persist_test` tokenize helpers); low for Option A; Option B also touches `ci/locomo/conflict_eval.mbt` |
| Leverage | High clarity; Option A is low risk; Option B improves **locality** but costs migration |
| Do not | Expose a parallel host “IndexStore” API; do not break per-user shard invariants while chasing privacy |

### P2 — Sync architecture / handover docs to 0.2.2 tree

| Field | Content |
|-------|---------|
| Problem | `architecture.md` §2 still lists `moon.pkg.json` (live: `moon.pkg`); omits `llm_extractor/`, `ci/`, and several `*_test.mbt` files. §2 `embedder.mbt` line names Clock + LogicalClock only (FixedClock is elsewhere in prose, not a separate file). Handover still says ~11 files / four traits (live: 13 non-test core files / five traits including Clock). |
| Candidate module | Documentation **interface** of the repo (what maintainers learn first) |
| Current interface | Stale file tree + incomplete trait list in handover |
| Proposed | Refresh §2 file list and trait diagram to match `src/` + packages; point “how to edit code” at `.trellis/spec/library/` |
| Dependency category | N/A (docs) |
| Test-surface impact | None |
| Leverage | High for humans/AI navigating the repo; zero runtime risk |
| Do not | Rewrite algorithm chapters while syncing the tree |

### P3 — Split `Clock` out of `embedder.mbt`

| Field | Content |
|-------|---------|
| Problem | Two **modules** in one file (`Embedder` + `Clock`/`LogicalClock`/`FixedClock` from line ~103); readers assume Clock is part of Embedder. |
| Candidate module | `Clock` + `LogicalClock` / `FixedClock` |
| Current interface | Unchanged traits; wrong file **locality** |
| Proposed | `clock.mbt` (or `time.mbt`); leave Embedder alone |
| Dependency category | In-process |
| Test-surface impact | None if symbols stay `pub` with same names |
| Leverage | Medium (navigation); low behavioral risk |
| Do not | Merge Clock into Config or invent a third time API |

### P4 — Clarify FS package vs call-site seam

| Field | Content |
|-------|---------|
| Problem | Core `moon.pkg` imports `x/fs` while coding rule says “FS only in persist.mbt”. Easy for agents to call `@fs` elsewhere. Verified: non-test core sources confine `@fs` to `persist.mbt`; `persist_test.mbt` and `src/cli/` also use `@fs` (expected). |
| Candidate module | Persistence **locality** |
| Current interface | Convention + Trellis spec |
| Proposed | **Docs/spec:** state explicitly that package import is unavoidable today and grep/`moon` review must enforce call-site isolation in non-test core sources. **Future:** if MoonBit gains finer isolation, consider a tiny `persist` subpackage — only with two real consumers. |
| Dependency category | Local-substitutable (MemoryBackend already) |
| Test-surface impact | None for docs; high if subpackage split |
| Leverage | Medium prevention of FS bleed |
| Do not | Introduce a hypothetical Persistence facade with a single adapter |

### P5 — Deduplicate guideline trees (routing only)

| Field | Content |
|-------|---------|
| Problem | `docs/project/` (narrative) + `spec/` (feature contracts) + `.trellis/spec/` (AI edit rules) overlap mentally. |
| Candidate module | Repo documentation routing |
| Proposed | One-page “where to look” in `docs/README.md` / Trellis guides: product narrative → `docs/project`; feature AC → `spec/`; coding conventions → `.trellis/spec`. Do not merge trees blindly. |
| Test-surface impact | None |
| Leverage | Medium for onboarding |
| Do not | Delete `spec/` feature docs; they are CI/process contracts |

### P6 — `MemoryStore.add` internal extraction (optional later)

| Field | Content |
|-------|---------|
| Problem | `add` is a long orchestration function (extract failure streaks, dedup, conflict, embed, index, flush). Hard to read; still one **interface**. |
| Candidate module | Private helpers / internal seam inside store **implementation** |
| Proposed | Extract private functions or an internal pipeline type **without** changing host interface; tests remain at store seam (`store_e2e_test`, qa). |
| Dependency category | In-process |
| Test-surface impact | Should be zero if behavior-preserving |
| Leverage | Locality for maintainers; modest |
| Do not | Split into multiple public services; do not add a second aggregate |

### P7 — Retrieval fusion strategy (product, not structure)

| Field | Content |
|-------|---------|
| Problem | Handover: hybrid RRF underperforms BM25 on LoCoMo lexical tasks (−12%). |
| Why low on *this* backlog | Algorithm/product tuning, not module-depth confusion. Track under eval/W5, not architecture deepening. |
| Do not | Treat as a reason to explode `MemoryStore` interface |

## Suggested follow-up task order (after this review)

1. Doc sync (P2) + guideline routing (P5) — safest.
2. Spec note on internal vs host surface (P1 Option A) — locks AI behavior.
3. Clock file split (P3) — mechanical.
4. Only then consider visibility tightening (P1 Option B) or `add` extraction (P6).
