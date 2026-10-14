# benchmark

LoCoMo 抽样评测，协议对齐 [mem0ai/memory-benchmarks](https://github.com/mem0ai/memory-benchmarks) 的 LoCoMo：按轮次写入，检索，让模型只根据命中的记忆作答，再由裁判模型判 `CORRECT` / `WRONG`。类别 5 的对抗题不抽。类别 3 的标准答案只取分号前一段。裁判不看证据原文。

```bash
moon run benchmark --target native
```

密钥放在 `benchmark/.env`（见 `.env.example`），不提交。远端 CI 不跑这条。

固定种子 `20261014` 抽到 LoCoMo 第 9 段对话（Evan / Sam，下标 8），再从可计分题里抽 20 题。509 轮原文写入，Qwen 嵌入。冲突判定全部保留，避免近重复对话互相覆盖。`recall` 上限是 50，作答只用这 50 条，并按会话时间排序。作答和裁判都用 DeepSeek。

`benchmark/data/locomo_20.json` 派生自 LoCoMo，**CC BY-NC 4.0**。来源 commit `cbfbc1dba6bc53d00625212a0f22d55ffee7c1fc`。

最近一次结果：17/20。多跳 4/4，时间 2/3，开放 1/1，单跳 10/12。逐题记录在 `benchmark/results/locomo-20.json`。
