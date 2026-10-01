# CLI LLM Wiring

> Native-only wiring of `llm_extractor` into CLI `Config`.

## Package split (`src/cli/moon.pkg`)

```text
targets: {
  "llm_wiring.mbt": ["native"],
  "llm_wiring_stub.mbt": ["not", "native"],
}
```

Both files export `build_llm_config(opts) -> Result[@src.Config, String]`:

| File | Behavior |
|------|----------|
| `llm_wiring.mbt` | Builds OpenAI-compatible provider + `LlmExtractor` / optional `LlmConflictJudge` |
| `llm_wiring_stub.mbt` | Returns `Err("llm wiring requires native target")`; keeps imports referenced to silence unused warnings |

Do not merge these into one file without preserving the target gate — wasm/js must stay stubbed.

## `build_llm_config` behavior (native)

Implemented in `src/cli/llm_wiring.mbt`:

1. Resolve `base_url` from CLI → `MOOMEM_LLM_BASE_URL` → default official endpoint.
2. Normalize URL (trim trailing `/` and optional `/v1` suffix via `normalize_base_url`).
3. Require `MOOMEM_LLM_API_KEY` unless `is_localhost_endpoint(base_url)` — host must be exactly `localhost`, `127.0.0.1`, or `::1` (substring traps like `localhost.evil.com` rejected).
4. Resolve model: CLI → `MOOMEM_LLM_MODEL` → `gpt-4o-mini`.
5. Construct `@openai.OpenAIProvider` and wrap with `@llm_extractor.LlmExtractor::new`.
6. If `opts.llm_judge`, also inject `LlmConflictJudge`.
7. Return `Config::{ ..Config::default(), extractor: Some(...), judge: Some(... optional) }`.

## Tests

`src/cli/cli_wbtest.mbt` sets/unsets `MOOMEM_LLM_*` and asserts:

- Missing key errors mention `MOOMEM_LLM_API_KEY`
- Localhost base URL can proceed without key (per wiring rules)

## Dependency boundary

CLI may import:

- `heyq02/moomem/src`
- `heyq02/moomem/src/llm_extractor`
- `mizchi/llm`, `mizchi/llm/openai`
- `moonbitlang/core/env`, `moonbitlang/x/fs`

Core library must remain free of `mizchi/llm`. When adding LLM features, extend `llm_extractor` + CLI wiring — not `store.mbt`.

## Anti-patterns

- Compiling real OpenAI FFI wiring on wasm/js
- Logging or printing the API key
- Treating “URL contains localhost” as safe (use exact host match)
- Pulling LLM types into core so CLI “doesn’t need” the adapter package
