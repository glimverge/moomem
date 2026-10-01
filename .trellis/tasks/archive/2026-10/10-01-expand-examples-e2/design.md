# Design: expand-examples-e2

## Layout

```
examples/
  basic-store/{moon.pkg,main.mbt}
  llm-extractor/{moon.pkg,main.mbt}   # from llm_extractor_demo
  conflict-supersede/{moon.pkg,main.mbt}
  cli-smoke/{moon.pkg,main.mbt}
```

Remove top-level `examples/moon.pkg` + `llm_extractor_demo.mbt` after migration.

## Dependencies

- `basic-store` / `cli-smoke`: `heyq02/moomem/src` only
- `llm-extractor` / possibly conflict with LLM mock: `src` + `llm_extractor` + `mizchi/llm` as needed
- Prefer MemoryBackend / temp paths; zero network

## CI

Update `smoke-example` job to run all four `moon run examples/<scene> --target native`.

## Boundaries

Teaching only — assertions stay in L0/L1 tests.
