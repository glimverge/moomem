# Design: architecture deepening review (review-only)

## Purpose

This task produces an architecture review using codebase-design vocabulary. Research artifacts were re-verified against the live tree on 2026-10-01. It does **not** change `src/` product code. Follow-up Trellis tasks may implement backlog items.

## Method

1. Map **modules** from package layout + `pub` surfaces (`research/module-map.md`).
2. Classify each **seam**: real (≥2 **adapters**), hypothetical (1), or internal-only.
3. Apply deletion test and dependency categories from `.cursor/skills/codebase-design/DEEPENING.md`.
4. Rank by **leverage** / clarity vs risk to host **interface** and AC tests (`research/deepening-backlog.md`).

## Keep as-is (locked for this review)

- `MemoryStore` external **interface**
- Trait **seams** with dual **adapters** (including `llm_extractor`)
- Dual-slot persistence semantics
- CLI as thin **adapter**

## Deliverable contracts

| Artifact | Contract |
|----------|----------|
| `research/module-map.md` | Uses glossary terms; covers host, ports, internals, docs, packages |
| `research/deepening-backlog.md` | Ranked P1–P7 + keep-as-is + do-not |
| This `design.md` | Scope = review-only; points to research as source of truth |
| `implement.md` | Checklist to finish/verify docs and optional Trellis spec note |

## Compatibility

- No migration. No API break.
- Optional later: one paragraph in `.trellis/spec/library/directory-structure.md` or `public-api-and-types.md` stating index/dedup are not host API (backlog P1 Option A). Only if user asks during execute.

## Trade-offs

| Choice | Benefit | Cost |
|--------|---------|------|
| Review-only | Low risk, clear backlog | No immediate code clarity |
| Defer Option B visibility | Avoids MoonBit privacy / test rewrite unknown | Internals stay `pub` until a dedicated task |

## Rollback

Delete or archive task research if abandoned; no product rollback needed.
