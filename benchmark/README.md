# benchmark

本地 LoCoMo 抽样。

```bash
moon run benchmark --target native
```

密钥在 `benchmark/.env`（见 `.env.example`），不提交。只在 native 上真跑；wasm、wasm-gc、js 只编译空的 `main`。远端 CI 不执行。

分数在仓库根 [README.md](../README.md)。逐题记录在 `results/locomo-20.json`。

`data/locomo_20.json` 派生自 LoCoMo，commit `cbfbc1dba6bc53d00625212a0f22d55ffee7c1fc`，**CC BY-NC 4.0**。不适用仓库的 MIT。
