# Implement: expand-examples-e2

1. Create four example packages; migrate llm demo into `llm-extractor`.
2. Implement basic-store, conflict-supersede, cli-smoke demos (short, readable).
3. Remove old top-level examples package files.
4. Update test-pipeline smoke-example.
5. Run all four `moon run` locally.

## Validation

```bash
moon run examples/basic-store --target native
moon run examples/llm-extractor --target native
moon run examples/conflict-supersede --target native
moon run examples/cli-smoke --target native
```
