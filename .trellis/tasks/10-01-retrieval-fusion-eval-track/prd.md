# Track retrieval fusion as product/eval work (P7)

**Parent:** `10-01-architecture-deepening-w2`  
**Order:** 3 of 3 (docs/tracking only)

## Goal

Record LoCoMo hybrid-vs-BM25 underperformance as a **product/eval** follow-up (W5-class), explicitly **not** as a reason to split or deepen the `MemoryStore` **module** **interface**.

## Requirements

- **R1.** Add a short pointer in `docs/project/04-progress-and-roadmap.md` and/or handover “open items” linking to W4 report (−12% hybrid vs BM25) and stating: no architecture module split for this.
- **R2.** Optionally one line in `.trellis/spec/library/quality-guidelines.md` or guides: do not “fix” retrieval by exploding store API.
- **R3.** No algorithm changes; no `src/` retrieval logic edits in this task.

## Acceptance Criteria

- [ ] AC1. Roadmap/handover (or equivalent) names P7/W5 retrieval fusion as eval follow-up with link to evidence.
- [ ] AC2. Explicit “do not split MemoryStore for fusion” note exists.
- [ ] AC3. No product code diffs under `src/` for this task.

## Out of scope

- Implementing new fusion; tuning on LoCoMo scored subset (overfit risk per handover).
