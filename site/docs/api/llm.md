# 宿主注入模型

库不带模型客户端。缺省 `HashingEmbedder`、`RawExtractor`、`SimilarityJudge` 全程离线。

结构化提取、语义冲突、真实向量由宿主实现对应 trait，再放进 `Config`：

```moonbit
let cfg : Config = Config::{
  ..Config::default(),
  embedder : Some(my_embedder as &Embedder),
  extractor : Some(my_extractor as &Extractor),
  judge : Some(my_judge as &ConflictJudge),
}
let store = MemoryStore::open("./memory", config=cfg).unwrap()
```

- `Extractor::extract` 返回空数组表示纯闲聊，不入库
- 提取失败可返回 `Err`，连续失败会熔断；也可以返回 `degraded: true` 的原文事实
- `ConflictJudge` 的 `Replace` 会把旧条目标成 `Superseded`

注入点总表见 [公开 API](/api/)。
