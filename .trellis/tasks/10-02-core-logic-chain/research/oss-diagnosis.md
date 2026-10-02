# 对照优秀开源项目的诊断

日期：2026-10-02。参照的是各项目公开文档，不是本机克隆后的源码审计。

| 参照 | 用它看什么 | 信源 |
|------|------------|------|
| SQLite | 嵌入式库怎样只有一条实现栈、一个公开面、一份与字节一致的格式说明 | [How SQLite Works](https://sqlite.org/howitworks.html)；[sqlite.h.in](https://github.com/sqlite/sqlite/blob/master/src/sqlite.h.in) 文首（不在此文件即非公开 API）；[AGENTS.md](https://github.com/sqlite/sqlite/blob/master/AGENTS.md) 的 tokenizer→VFS 栈 |
| mem0 | 记忆产品怎样把「写完再搜」写成一页契约 | [How Mem0 Works](https://docs.mem0.ai/core-concepts/how-it-works)（2026-10-02 抓取）；[OSS v2→v3](https://github.com/mem0ai/mem0/blob/main/docs/migration/oss-v2-to-v3.mdx)（提取改为只 ADD） |
| Letta | 另一种记忆产品：记忆是 agent 循环的一部分，而不是宿主调用的库 | [Memory blocks](https://docs.letta.com/guides/core-concepts/memory/memory-blocks/)；[Agent Memory Atlas](https://neoneye.github.io/agent-memory-atlas/systems/letta/) |

仓库内竞品长文 `docs/resources/02-competitive-analysis.md` 解决的是「MoonBit 生态选题是否已被占坑」，不描述 mem0 / Letta / SQLite 的脊柱，不能当作本次诊断的参照。

## 三条参照各自的脊柱

**SQLite。** 进程内库，没有独立服务。调用方提交 SQL，同一线程里走完：分词 → 解析 → 代码生成 → 虚拟机 → B-tree → pager → VFS。数据库通常是一个格式稳定的文件。公开 API 只有 `sqlite3.h`；注释即文档。`ext/` 是扩展，不改写核心句子。

**mem0。** 坐在应用和模型之间。有用的对话之后 `add`，下次请求模型之前 `search`，放进提示词由应用决定。`add` 的顺序是：对照已有记忆 → LLM 抽出可复用事实 → 去重并嵌入 → 抽出实体。当前 OSS 的自动路径只追加；「从 Austin 搬到 Seattle」不会悄悄改写旧事实，改正要显式 `update` / `delete`。事实在 SQL（真相），向量库只负责相似度，实体库是第三条检索信号。

**Letta。** 记忆是 agent 状态。Core memory 是永远编进系统提示的分块，agent 用工具改写，下一轮直接看见，不经过检索。Archival 才是可搜索的长期段落。Recall 是对话历史搜索。循环本身就是设计：写 core memory 会改变下一次提示词。

## moomem 实际对齐的是哪一条

运行时更像 **SQLite 的库形态 + mem0 的 add/search 契约**，不是 Letta。

- 进程内、一个目录、宿主调用后返回。`open` 读快照，`restore_entries` 重建条目表、按用户分片的索引和去重表（`src/store.mbt`）。快照是真相，索引是派生的。这和 mem0「SQL 是真相、向量是查找结构」同一类，也和 SQLite「文件是库」同一类。
- 宿主负责何时 `add`、何时 `recall`、把命中放进哪一次模型调用。README 的过敏场景是这个契约。库不会自己改写下一轮提示词。
- 和 mem0 当前 OSS 的分叉是产品差异，不是文档错误：moomem 的 `add` 在插入后执行 supersede（`MemoryStore::add`）。mem0 v3 明确拒绝这条静默改写。

Letta 的 core / archival / recall 三层，moomem 只有一层可召回事实。不要用 Letta 的循环来要求这条库。

## 对照之后，混乱落在四条

1. **没有一份「how it works」等于当前代码。** mem0 用一页写死 add 然后 search，并写明 add 不改写旧事实。SQLite 用头文件注释当 API 真相。moomem 的 README 接近这页，但 `docs/project/03-prd.md` 仍写委托 vcdb / MoonRetrieve，`architecture.md` 仍写三个 trait、状态「待评审」。三份叙述不能同时为真。

2. **公开面没有边界。** SQLite：不在 `sqlite3.h` 里就不是 API。moomem 把索引、分词、余弦、快照编解码、崩溃注入用的 `MemoryBackend` 都标成 `pub`（见 `src/index_keyword.mbt` 的 `tokenize`、`src/embedder.mbt` 的 `cosine_similarity`、`src/json_codec.mbt`、`src/persist.mbt`）。评测包直接调用这些内部函数。扩展在改核心的形状。

3. **版本不是一个数。** SQLite 的 `VERSION` 写进生成的头文件。moomem 同时有 `moon.mod` `0.6.0`、`MOOMEM_VERSION = "0.2.2"`（`src/lib.mbt`）、`SNAPSHOT_VERSION = 1`。快照格式版本和包版本本可以分开，但包版本自己已经裂成两个。

4. **扩展被写成了并列真相。** SQLite 把 FTS 放在 `ext/`，应用文档和内部文档分库。moomem 的 CLI、LLM 适配、LoCoMo、文档站、W3/W4 周报、Trellis 规范、归档 process spec 都在回答「项目是什么」。`docs/README.md` 还规定这些树不要合并。结果是卫星继续生长，脊柱没有单一入口。

`MemoryStore::recall` 里的融合策略、词法权重、回填，是脊柱变厚，不是第二条产品。它们仍在同一次召回里。问题是这些旋钮没有一份和代码同步的契约，却已经散进 Config 校验、评测报告和 README。
