# moomem

Embedded agent memory library for [MoonBit](https://www.moonbitlang.com/). Module `heyq02/moomem`. Host API is `MemoryStore`: `open` / `add` / `recall` / `forget` / `stats` / `close`, plus list / export / import. Search is hybrid vector + BM25, sharded by `user_id`. Native persistence is a dual-slot JSONL snapshot plus `head`. Defaults are offline and deterministic; hosts inject `Embedder`, `Extractor`, and `ConflictJudge` for real models.

Host behavior and on-disk layout: `README.md`. File map: `src/README.md`. `playground/` is a separate module.

## Toolchain

`moon` builds and tests the library. Node is repo hygiene only: [`@heyq02/rstack-config`](https://github.com/heyq02/rstack-config) (`rs fmt`, hooks, commitlint), [`automd`](https://automd.unjs.io) for parts of `README.md`, and [`bumpp`](https://github.com/antfu-collective/bumpp). `package.json` pins `pnpm@12.10.1`.

`moon.mod` `version`, `package.json` `version`, and `src/lib.mbt` `MOOMEM_VERSION` stay the same string. `pnpm release` updates all three, commits, tags `v{version}`, and pushes. `pnpm release --no-push` stops after the local commit and tag. `SNAPSHOT_VERSION` is the snapshot header `v` and does not follow the package version.

Documented `moon` baseline is in `README.md`. CI installs latest (`dated CDN pins return 403`).

## Layout

| Path | Role |
|------|------|
| `src/` | Core package. `*_test.mbt` and `*_wbtest.mbt` stay beside sources. |
| `examples/` | Three offline `moon run` scenes. Smoke only. |
| `benchmark/` | Offline LoCoMo eval. |
| `playground/` | Host sample (Qwen embed + DeepSeek extract). Depends on published `heyq02/moomem`, not this working tree. |
| `.github/workflows/` | `check.yml`, `unit-test.yml`, `coverage.yml`, `smoke.yml`, `benchmark.yml` on push/PR to `main`. `commitlint.yml` on PR commits. `autofix.yml` runs `rs fmt`, `moon fmt`, and `moon check --deny-warn`. `release.yaml` on tag `v*`. |
| `bump.config.ts` | Files bumpp rewrites: `package.json`, `moon.mod`, `src/lib.mbt`. |

Targets: `native`, `wasm`, `wasm-gc`, `js`. Native uses `FsBackend` under `<path>/moomem/`. Other targets default to in-memory `MemoryBackend`. `#cfg(target="native")` belongs in `persist.mbt` (tests may use it in `persist_test.mbt`).

## Commands

```bash
moon check --target native
moon fmt
moon info
moon test --target native
moon test --target wasm
moon test --target wasm-gc
moon test --target js
moon test --enable-coverage --target native
moon coverage report --ignore-missing-files -f summary -p heyq02/moomem/src
pnpm run cov:bisect
moon run examples/default-reopen --target native
moon run benchmark --target native
```

`pnpm test` is `moon test` with no `--target`. `src/` coverage must stay ≥ 90% of points. Native CI fails if the suite shrinks below `NATIVE_TEST_BASELINE` in `unit-test.yml`; that floor only rises. `cov:json`, `cov:xml`, and `cov:html` need a coverage-enabled `moon test` first.

Black-box tests see `pub` only. Assert with `inspect`. Inject traits by hand. Crash and partial-write cases use `MemoryBackend`.

## Code style

MoonBit block style (`///|`). Types `PascalCase`, functions and fields `snake_case`, traits `pub(open) trait`. Unmarked top-level defs are package-private. Format with `moon fmt`.

- Fallible library paths return `Result[T, MoomemError]`. Do not `panic` or `abort`. New variants go in `errors.mbt` and must update `Show`, `message`, and `kind`.
- Non-test `@fs` call sites stay in `persist.mbt`. `persist_test.mbt` is the test allowlist.
- Snapshot and entry JSON encode/decode stay in `json_codec.mbt`.
- Every index, search, dedup, `add`, `recall`, and `forget` path takes an explicit `user_id`. No cross-user scan.
- Do not promote indexes, `rrf`, `tokenize`, `cosine_similarity`, or `keyword_jaccard` to a second host API.
- Core must not import an LLM SDK. Defaults stay offline when injection points are `None`.
- Persistence is a full dual-slot snapshot plus `head`, not an append-only log.
- No logging facade. Observability is `AddSummary`, entry `metadata`, `StoreStats`, and `MoomemError::message` / `kind`.

Before adding a helper, search for `validate_user_id`, `content_fingerprint`, `tokenize`, `rrf`, and the codec functions.

## Release

`release.yaml` runs on a `v*` tag: changelogithub, `moon package`, then [`cogna-dev/moonbit-actions/publish`](https://github.com/cogna-dev/moonbit-actions). The tag must match `moon.mod` `version`. `MOONCAKES_TOKEN` is the base64 of `~/.moon/credentials.json` and belongs only on that job. Do not cache `~/.moon`. Push/PR jobs stay offline: no `MOONCAKES_TOKEN`, no model endpoints. `COVERALLS_REPO_TOKEN` is only for `coverage.yml`.

Before pushing library changes, run `moon check`, `moon test`, and `moon fmt` on native, and the other three targets when the change is not native-only. If behavior, defaults, or snapshot shape change, update `README.md` and extend a black-box test.

## Security and pitfalls

- Tests, examples, and the offline benchmark never contain API keys. Do not commit `playground/.env`. `playground/memory/` is gitignored runtime state.
- `open` returns `StoreCorrupted` when snapshot `v` mismatches, a non-final line is truncated, or both slots are unusable. Only a torn last line is dropped (`stats().truncated_recovered`).
- wasm/js `recall` after process restart is empty unless the host injected a `PersistenceBackend`.
- Playground behavior that disagrees with `src/` follows the published pin in `playground/moon.mod`.
- Native file tests that touch a real directory need `--target native`. They are `#cfg`'d out of wasm/js.
