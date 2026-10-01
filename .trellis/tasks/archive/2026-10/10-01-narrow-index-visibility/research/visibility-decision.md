# Visibility decision: Option B narrowed

**Task:** `10-01-narrow-index-visibility`  
**Decision:** **Narrowed** (Option B applied). Not blocked.

## MoonBit evidence

From [Managing Projects with Packages](https://docs.moonbitlang.com/en/latest/language/packages.html) and [Writing Tests](https://docs.moonbitlang.com/en/latest/language/tests.html):

- Unmarked top-level `fn` / `const` / `struct` methods are **package-private** (invisible to other packages).
- Types without `pub` / `priv` are **abstract**: name may be visible; representation and unmarked methods are not callable across packages.
- `*_test.mbt` = black-box (only `pub`); `*_wbtest.mbt` = white-box (all package members).

Compile probe: after de-`pub`, `moon test --target native` green; `moon check --target native ci/locomo` green with helpers still `pub`.

## Inventory summary

| Symbol | Callers outside core package | Action |
|--------|------------------------------|--------|
| `VectorIndex` + methods | none (was `index_test` via `@src`) | de-`pub`; tests → `index_wbtest.mbt` |
| `KeywordIndex` + methods | none | same |
| `DedupIndex` + methods | none (was `extractor_test`) | de-`pub`; tests → `index_wbtest.mbt` |
| `content_fingerprint` | none | de-`pub` |
| `BM25_K1` / `BM25_B` | none | de-`pub` |
| `rrf` | none (was `index_test`) | de-`pub`; tests → wbtest |
| `tokenize` | `ci/locomo/conflict_eval.mbt`, black-box tests | **keep `pub`** |
| `cosine_similarity` | same | **keep `pub`** |
| `keyword_jaccard` | same | **keep `pub`** |

## Extra seam

`MemoryStore` fields `vec_index` / `kw_index` / `dedup` marked `priv` so the host `pub struct` does not expose index handles.

## Host API

`MemoryStore` method names/signatures unchanged. No IndexStore facade.
