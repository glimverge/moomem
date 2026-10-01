# CLI Development Guidelines

> Conventions for the native moomem CLI (`src/cli/`).

The CLI is a thin `is-main` package that drives `MemoryStore` for no-code demos (PRD FR-07). It is not a web UI.

---

## Guidelines Index

| Guide | Description | Status |
|-------|-------------|--------|
| [Commands and Env](./commands-and-env.md) | Subcommands, flags, exit behavior, env vars | Filled |
| [LLM Wiring](./llm-wiring.md) | `--llm` / `--llm-judge`, native vs stub, keys | Filled |

---

## Pre-Development Checklist

- [ ] Parse flags in `main.mbt`; keep core logic on `@src.MemoryStore`
- [ ] LLM config construction stays in `llm_wiring.mbt` (native) / stub (non-native)
- [ ] Do not move `mizchi/llm` imports into the core package
- [ ] Secrets only via env (`MOOMEM_LLM_API_KEY`); never hard-code keys
- [ ] Preserve dual-target split in `src/cli/moon.pkg` `targets`

---

## Quality Check

- [ ] `moon test` covers `cli_wbtest.mbt` on native
- [ ] Missing key / localhost exception behavior still matches tests
- [ ] Usage text stays consistent with implemented flags

---

**Language**: English.
