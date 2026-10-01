# 介绍

**moomem** 是 MoonBit 生态的嵌入式 Agent 记忆层：给 LLM Agent 配一本跨会话笔记本——`add` 提取事实并落盘，`recall` 用混合检索召回，按 `user_id` 结构隔离，进程重启后仍可恢复。

## 解决什么问题

LLM 是状态函数：每次推理只依赖本轮上下文，窗口关闭或进程结束后一切归零。MoonBit 生态已有向量库、BM25、LLM 调用与 RAG 框架，但缺少可持久化的记忆实现——例如 moon-agent 的 `BufferMemory` 仅存在于进程内。

moomem 的定位是：**嵌入式零部署库**，不是服务端记忆平台。

## 典型场景

- **偏好记忆**：用户说「我对花生过敏」→ 次日推荐午餐前 `recall` 注入相关事实。
- **事实变更**：用户说「我搬到深圳了」→ 冲突判定将旧住址置为 `Superseded`，检索不再返回。
- **多用户隔离**：同一记忆库内不同 `user_id` 的事实物理分片；无「全库检索」接口，跨用户命中在结构上不可能。

## 核心能力

- 两行接入：`MemoryStore::open` + `add` / `recall`（公开方法面 ≤ 6）
- 默认零 API Key：嵌入 / 提取 / 冲突均为可注入 trait
- 混合检索：向量 + BM25 + RRF
- 双槽快照持久化，崩溃可恢复
- 可选 `src/llm_extractor` 对接 OpenAI 兼容端点

## 相对竞品（短对照）

| | moomem | PowerMem | moon-agent 内存记忆 |
|--|--------|----------|---------------------|
| 形态 | 嵌入式库 | 需部署服务 | 进程内 |
| 持久化 | 磁盘双槽 | 服务侧 | 不持久 |
| 隔离 | `user_id` 结构分片 | 服务多租户 | 进程内 |

更深调研见仓库 [`docs/resources/`](https://github.com/glimverge/moomem/tree/main/docs/resources)。

## 下一步

- [快速上手](/guide/start/getting-started) — 安装与最短代码
- [持久化](/guide/start/persistence) — 双槽布局与状态机
- [安全与限制](/guide/start/security) — 信任边界与已知限制
- [API](/api/) — MemoryStore 与注入点
- [Benchmark](/benchmark/) — LoCoMo 归档分数
