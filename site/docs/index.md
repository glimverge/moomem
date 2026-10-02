---
pageType: home

hero:
  name: moomem
  text: MoonBit 嵌入式 Agent 记忆层
  tagline: 零部署 · 崩溃可恢复 · 按用户结构隔离
  actions:
    - theme: brand
      text: 快速上手
      link: /guide/start/getting-started
    - theme: alt
      text: GitHub
      link: https://github.com/glimverge/moomem
  image:
    src: /rspress-icon.png
    alt: moomem
features:
  - title: 两行接入
    details: MemoryStore::open + add / recall。公开方法共 9 个，默认零 API Key。
    link: /guide/start/getting-started
  - title: 混合检索与隔离
    details: 向量 + BM25，缺省自适应融合（可回退等权 RRF）；索引按 user_id 物理分片，无全库召回接口。
    link: /guide/start/introduction
  - title: 崩溃安全持久化
    details: 双槽 JSONL 快照 + head 指针；进程被杀后 open 同一目录即可恢复。
    link: /guide/start/persistence
  - title: 可选 LLM 路径
    details: 核心包零 LLM 依赖；注入 LlmExtractor / LlmConflictJudge 即可结构化提取与冲突判定。
    link: /api/llm
---
