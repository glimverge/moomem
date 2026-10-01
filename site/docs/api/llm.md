# LLM 注入

核心库默认不走 LLM；可选能力在 **`src/llm_extractor`**（基于 mizchi/llm，对接 OpenAI 兼容端点）。

## 库内注入

```moonbit
let provider = @openai.OpenAIProvider::new(
  "sk-...",
  endpoint=OpenAIEndpoint::OpenAI,   // 或 Custom(base_url="https://...")
  model="gpt-4o-mini",
)
let extractor = @llm_extractor.LlmExtractor::new(provider)
let judge = @llm_extractor.LlmConflictJudge::new(provider)

let cfg : Config = Config::{
  ..Config::default(),
  extractor : Some(extractor as &Extractor),
  judge : Some(judge as &ConflictJudge),
}
let store = MemoryStore::open("./memory", config=cfg).unwrap()
```

## 行为契约

- 提取保留可复用事实（`fact` / `preference` / `event` + 原文 `span`），丢弃寒暄
- 失败时降级可见：`AddSummary.degraded` / `notes` / 条目 `metadata.extraction_degraded`，不会静默吞掉
- `DegradePolicy`：`ReturnRaw`（原文 unstructured 入库）或 `PropagateError`

:::tip
请在宿主包内自行 mock `Provider`。零网络范例见仓库 `examples/llm-extractor` 与 `src/llm_extractor/*_test.mbt`。
:::

CLI 侧启用方式见 [CLI](/api/commands)。注入点总表见 [公开 API](/api/)。
