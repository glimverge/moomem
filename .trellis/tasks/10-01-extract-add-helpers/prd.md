# Extract MemoryStore.add private helpers (P6)

**Parent:** `10-01-architecture-deepening-w2`  
**Order:** 2 of 3 — prefer after visibility decision (P1B) so test strategy is settled; not a hard blocker.

## Goal

Improve **locality** inside the `MemoryStore` **implementation** by extracting private helpers from the long `add` orchestration—without changing the host **interface**.

## Requirements

- **R1.** Split `MemoryStore::add` into private helpers (e.g. extract/degrade streak, dedup path, conflict/supersede, embed+index insert, flush trigger)—names flexible.
- **R2.** Host signature and observable behavior unchanged (`AddSummary` fields, error modes, AC tests).
- **R3.** Tests stay at store **seam** (`store_e2e_test`, `qa_*`, `w3_config_test`); do not add a second public aggregate.
- **R4.** `moon test` native green.

## Acceptance Criteria

- [ ] AC1. `add` body is shorter / staged via private helpers; public method still `add(user_id, text)`.
- [ ] AC2. No new `pub` orchestration types required for hosts.
- [ ] AC3. Native `moon test` green (baseline still matches project docs).
- [ ] AC4. Trellis `directory-structure` / quality notes mention private helpers if useful.

## Out of scope

- Changing extract/conflict algorithms; visibility Option B (other child); RRF fusion (P7).
