# Error Handling

> How fallible operations fail in the core library.

## Rule

Every fallible library operation returns `Result[T, MoomemError]`.
**Panic / abort is forbidden** in library code (`src/errors.mbt`, `src/lib.mbt` header comments).

`MoomemError` is a `pub(all) suberror` so internals may use `raise`, but the **public** API surface stays `Result`.

## Variants (`src/errors.mbt`)

| Variant | When used |
|---------|-----------|
| `InvalidUserId(String)` | `validate_user_id` failures |
| `StoreCorrupted(String)` | Bad/missing header, incompatible snapshot version, both slots unusable |
| `IoFailure(String)` | Wrapped FS / save failures (`persist.mbt` `io_error_message`; `MemoryBackend` simulated failures) |
| `ExtractionFailure(String)` | Extractor consecutive failures hit `MAX_EXTRACTION_FAILURES` (3) |
| `EmbeddingFailure(String)` | Embedder construction/runtime failures (e.g. non-positive dim) |
| `BackendUnsupported(String)` | Operation unsupported on current backend |
| `InvalidOperation(String)` | Closed store, illegal config, illegal state-machine ops |

Helpers:

- `MoomemError::message` — human-readable string for CLI/hosts
- `MoomemError::kind` — short snake_case category for metadata/logging
- Hand-written `Show` — format `Variant(payload)`

## Patterns in real code

1. **Validate early, return `Err`** — e.g. `MemoryStore::open` checks `config.dim`, `rrf_k`, thresholds before touching persistence.
2. **Validate `user_id` at each entrance** — `match validate_user_id(user_id)` then return the same error.
3. **Degrade instead of hard-fail when documented** — embedding failure on recall can fall back to BM25-only; extractor failures may degrade to unstructured / count toward the failure fuse (`store.mbt`, `AddSummary.degraded`).
4. **Wrap foreign errors** — FS `@fs.IOError` → `MoomemError::IoFailure(...)` inside `persist.mbt`.
5. **Tests assert with `inspect` / Result matching**, not panics — see `store_e2e_test.mbt`, `persist_test.mbt`.

## What this project does *not* do

- No structured logging framework or log levels in the core library.
- No exception types besides `MoomemError` for library failures.
- CLI prints errors to stderr with a readable prefix and non-zero exit — that is CLI concern (`src/cli/main.mbt`), not a library logger.

## Anti-patterns

- Calling `panic` / `abort` on bad `user_id`, missing files, or parse errors.
- Swallowing errors into empty success without setting `degraded` / notes / metadata when the PRD requires observability.
- Inventing ad-hoc `String` error returns from core public APIs (CLI helpers may use `Result[T, String]` for flag parsing only).
- Forgetting to extend `Show` / `message` / `kind` when adding a variant.
