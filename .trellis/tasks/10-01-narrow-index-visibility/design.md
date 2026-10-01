# Design: narrow index visibility (P1 Option B)

## Decision framework

1. Inventory `pub` symbols on indexes/dedup/helpers and their callers outside `MemoryStore`.
2. MoonBit rule (expected): unmarked = package-private; `pub` = visible to other packages. Same-package `*_test.mbt` can use non-`pub` types.
3. Must stay `pub` if used from `ci/`, `src/cli/`, `src/llm_extractor/`, or examples: likely `tokenize`, `cosine_similarity`, `keyword_jaccard`, maybe `rrf`.
4. Candidates to de-`pub`: `VectorIndex`, `KeywordIndex`, `DedupIndex` (+ methods), maybe `content_fingerprint`, BM25 consts — if only `src/` + same-package tests use them.

## Outcomes

- **Narrow:** remove `pub` from index/dedup types; keep diagnostic helpers `pub`; update Trellis spec.
- **Blocked:** if tests are treated as external or language lacks package-private — document and stop.

## Do not

- Host IndexStore API; break user sharding; change MemoryStore signatures.
