# 找出核心逻辑链路并梳理项目混乱

## Goal

和主理人一起判断：moomem 有没有一条可以当脊柱的逻辑链路；仓库里的文档、代码卫星、流水线是长在这条链上，还是各写各的。诊断必须对照优秀开源项目的公开脊柱，而不是只在仓库内部找矛盾。本任务先产出共同认可的诊断，不改产品代码。

用户原话：项目像 Vibe Coding，没有核心逻辑链路，文档、代码、流水线都是顺着感觉长出来的。2026-10-02 确认本轮交付是深度诊断，参照优秀开源项目，不在本轮列裁剪清单。

## Confirmed facts

以下均由 2026-10-02 对当前仓库的直接阅读得出。

### 运行时脊柱是存在的

产品要解决的事写在 `docs/project/03-prd.md`：MoonBit Agent 跨会话记住用户事实，并且能隔离、能覆盖旧事实、能在崩溃后恢复。

代码里唯一有状态的编排者是 `MemoryStore`（`src/store.mbt`）。公开入口是 `open` / `add` / `recall` / `forget` / `stats` / `close`，外加 `export_jsonl` / `import_jsonl` / `list_entries`。

`add` 的实际顺序（`src/store.mbt` `MemoryStore::add`）：

1. 拒绝已关闭的 store，校验 `user_id`
2. 提取事实（可降级）
3. 无事实则直接成功返回（闲聊过滤）
4. 对每条事实：精确去重 → 嵌入 → 收集冲突候选 → 判定 → 插入 → 应用 supersede
5. 有插入或覆盖则 flush

`recall` 的实际顺序：校验用户 → 嵌入查询（失败则丢掉向量路）→ 该用户的向量检索 + BM25 → `EqualRrf` 或 `AdaptiveLexical` 融合 → 只留下该用户且可召回的条目 → 可选按新近补齐。

持久化是双槽快照加 `head` 指针，不是 PRD 原文里的追加写 JSONL。索引按 `user_id` 分片，检索入口强制带用户。

### 叙述层已经和代码分叉

| 声称 | 出处 | 代码现状 |
|------|------|----------|
| 索引委托 vcdb / MoonRetrieve | `docs/project/03-prd.md` 第 6、14 章 | 向量与 BM25 都是库内实现 |
| 三个注入 trait | `docs/project/architecture.md` §1.2、文末依赖段 | 五个：`Embedder`、`Extractor`、`ConflictJudge`、`PersistenceBackend`、`Clock` |
| 架构文档状态「待评审 → 通过后进入开发」 | `docs/project/03-prd.md` 文首；`architecture.md` 文首「待工程团队评审」 | `moon.mod` 已是 `0.6.0`，库已发布 |
| 模块版本 `0.2.2` | `src/lib.mbt` `MOOMEM_VERSION`；`architecture.md` §2；`.trellis/spec/library/directory-structure.md`；交接文档 | `moon.mod` `version = "0.6.0"` |
| `store.mbt` 865 行、核心 13 个非测试文件 | `.trellis/tasks/archive/2026-10/10-01-architecture-deepening/research/module-map.md`（2026-10-01） | `store.mbt` 已超过 1000 行；融合策略、回填已长进 `recall` |

`docs/README.md` 自己声明仓库里有多套并行文档，**不要合并**。现行叙述至少分在：`README.md`、`site/docs/`、`docs/project/`（编号 03–10 + architecture）、`docs/resources/`、`docs/archive/`、`.trellis/spec/`。CI 实现在 `.github/workflows/test-pipeline.yml`，耐久红线写在 `.trellis/spec/library/quality-guidelines.md`，长文规格在 `docs/archive/process-specs/`。

交接文档 `docs/project/09-handover.md` 仍把下一件要事写成黑客松申报和暂缓的 v0.2.2 发版。

`open` 把快照条目重放进内存索引（`MemoryStore::restore_entries`）。磁盘快照是真相，向量 / BM25 / 去重表是派生结构。

### 对照开源项目后的判断

详细对照见 `research/oss-diagnosis.md`。摘要：

- 形态对齐 SQLite：进程内库，快照是真相，索引在 `open` 时重建。
- 契约对齐 mem0：宿主在对话后 `add`，在下次模型调用前 `recall`。差异是 moomem 在 `add` 内 supersede；mem0 当前 OSS 的自动路径只追加，改正走显式 update/delete。
- 不对齐 Letta：没有永远留在提示词里的 core memory，库也不驱动 agent 循环。
- 混乱不在「没有链路」，而在四条：没有一份 how-it-works 等于代码；`pub` 把内部实现变成了事实上的 API；包版本裂成 `0.6.0` 与 `0.2.2`；CLI / 评测 / 文档站 / 周报被写成并列真相。

### 卫星是怎么挂上去的

围绕上面那条 `add` / `recall` 链，另外长出了：

- `src/llm_extractor/`、`src/cli/`：可选适配，核心包不依赖 LLM
- `examples/`：四个零网络演示
- `ci/eval/locomo`、`ci/tools/retrieval-tuning`、`ci/gates/`：评测与调参
- `site/`：对外文档站
- 一周一个编号的验证报告（W3、W3.1、W4）和已归档 feature/process spec

这些卫星各自有局部真相，没有一份文档同时等于当前 `moon.mod` 和当前 `MemoryStore::add` / `recall`。

## Requirements

- R1. 诊断必须区分「运行时脊柱」和「围着它长出来的叙述 / 门禁 / 评测」。不得把文档漂移说成库没有 `add`→`recall` 链路。
- R2. 每条结论要能指回文件。版本、trait 数量、委托关系、API 入口以代码和 `moon.mod` 为准，不以旧报告为准。
- R3. 本任务在主理人确认交付范围之前，不改 `src/`、不删文档、不改流水线。
- R4. 探究结论写回本任务的规划产物，不另起一套与 `docs/project/` 平行的项目真相。

## Decisions

- D1（2026-10-02，主理人采纳推荐）。仓库按 SQLite 要求：一个公开面，一份与快照字节一致的格式说明；CLI、评测、文档站是扩展，不改写核心句子。语义保持 mem0 式 `add` / `recall`：宿主决定何时写入、何时召回、命中是否进入提示词。保留 `add` 内 supersede，不改成 mem0 当前 OSS 的只追加。不增加 Letta 式 core memory，库不驱动 agent 循环。
- D2. 磁盘快照是真相。向量索引、BM25、去重表在 `open` 时由 `restore_entries` 重建，是派生结构。
- D3. 本轮不改产品代码，不统一版本号。文档删除以 D5 为准，执行前先确认文件清单（Q5）。
- D5（2026-10-02，主理人）。一份资料相对现行代码已经偏移，并且不再维护，就直接删除。不迁入 `docs/archive/`，不留作并列史料。仍在维护的入口（即便其中有过时句子）改到与代码一致，不删除。
- D4（2026-10-02，主理人采纳推荐）。公开契约只有：`MemoryStore` 的九个方法（open / add / recall / forget / stats / close / export_jsonl / import_jsonl / list_entries）；调用它们所需的 `Config`、`MemoryEntry`、`AddSummary`、`StoreStats`、`ForgetTarget`、`MoomemError` 及条目状态/种类；五个注入 trait 与缺省适配器类型；`MOOMEM_VERSION` 与 `SNAPSHOT_VERSION`。`tokenize`、`cosine_similarity`、`keyword_jaccard`、RRF、`VectorIndex`、`KeywordIndex`、去重索引、快照行解析、`MemoryBackend` 的崩溃注入方法不是契约。它们今天的 `pub` 是实现泄漏。

## 资产分类

依据 D1 与 D5。`服务脊柱` = 实现或守护 add/recall/快照。`扩展` = 可以拿掉而不改变库的契约句。`已漂移，删除` = 相对现行代码偏移且不再维护。`已漂移，改` = 仍是现行入口，过时句子要改掉。

| 资产 | 分类 | 依据 |
|------|------|------|
| `MemoryStore` 的 open/add/recall/forget/stats/close/export/import/list | 服务脊柱 | 宿主契约 |
| 五个 trait 与缺省适配器（Hashing / Raw / Similarity / Fs / LogicalClock） | 服务脊柱 | 注入缝，对应 SQLite 的 VFS：宿主要实现就得看见 |
| `src/index_*.mbt`、`ranker.mbt`、`dedup.mbt`、`tokenize`、`cosine_similarity`、`json_codec.mbt` | 服务脊柱的实现；公开导出已漂移 | 派生索引与编解码。SQLite 不把 B-tree 放进公开头文件。评测包直接调用其中一部分 |
| `src/llm_extractor/`、`src/cli/`、`examples/` | 扩展 | 核心包不依赖 LLM；CLI 是另一入口 |
| `ci/eval/locomo`、`ci/tools/retrieval-tuning`、`ci/gates/` | 扩展 | 测量或调参，不是契约 |
| `.github/workflows/test-pipeline.yml` | 服务脊柱 | 守住多后端测试与离线评测门槛 |
| `README.md` | 服务脊柱；已漂移，改 | 唯一还在维护的宿主契约页。Q4 的落点 |
| `site/docs/` | 扩展；已漂移则改 | 对外文档站，复述契约 |
| `docs/project/10-testing-examples-architecture.md` | 已漂移，删除 | 2026-10-02 主理人确认：这也算停更资料。测试落点改由 `.github/workflows/` 与 `.trellis/spec/library/quality-guidelines.md` 承担 |
| `docs/project/03-prd.md`、`04-progress-and-roadmap.md`、`05-test-suite.md`、`06`–`09`、`architecture.md`、三份 mermaid、`docs/project/README.md` | 已漂移，删除 | 停在黑客松 / 0.2.2：vcdb、三个 trait、待评审、旧测试计数。`05` 的用例编目挂在即将删除的 PRD 上 |
| `docs/resources/`、`docs/archive/`、`docs/README.md` | 已漂移，删除 | 资源与归档自述为史料或赛季结束后迁入；`docs/README.md` 只给这些树做路由 |
| `.trellis/spec/library/directory-structure.md` | 已漂移，改 | 仍是编码规范入口，版本行写成 0.2.2 |
| `src/lib.mbt` `MOOMEM_VERSION` | 已漂移，改 | 常量 `"0.2.2"`，模块文件是 `0.6.0`。这是代码，不是可删资料 |

## Acceptance Criteria

- [x] 有一张主理人认可的脊柱描述：输入事实如何变成可召回记忆，查询如何变回条目。步骤与 `MemoryStore::add` / `recall` 一致，并写明它相对 SQLite / mem0 / Letta 各对齐哪一段、故意不对齐哪一段。见 D1 与上文「运行时脊柱」。
- [x] 主要资产被标成服务脊柱 / 扩展 / 已漂移。见「资产分类」。
- [x] 公开面边界经主理人确认。见 D4。
- [x] 契约叙述的唯一现行落点是 `README.md`（D5：停更长文删除，不另写第三篇，也不把 `architecture.md` 留作史料）。快照字节说明仍要补进这一页，本轮还没写。
- [x] 删除清单经主理人确认（Q5），含 `docs/project/10-testing-examples-architecture.md`。

## Out of scope

- 本轮不实现功能、不重构 `MemoryStore`、不统一版本号。删除只覆盖 Q5 确认的资料，不顺手改代码。
- 不把 FlowUs 工作区当作事实源（`docs/README.md` 已写明数字以仓库为准）。

## Open questions

- Q1. 已关闭。本轮只做对照开源项目的深度诊断，不列裁剪清单。
- Q2. 已关闭。采纳 D1：SQLite 式库形态，mem0 式 add/recall，保留 add 内 supersede，不做 Letta 多层记忆。
- Q3. 已关闭。采纳 D4。
- Q4. 已关闭。现行契约页是 `README.md`。偏移且停更的长文按 D5 删除。
- Q5. 已关闭，并已执行。删除了整个 `docs/`（含 `10-testing-examples-architecture.md`）。README、文档站、Trellis 规范、流水线注释和评测数据说明里指向这些路径的链接已去掉。`.trellis/tasks/archive/` 里的旧任务记录保留，它们是当时的任务档案，不是现行产品资料。
- Q6. 现行入口里还剩的漂移，下一刀改哪一处？`MOOMEM_VERSION` 仍是 `"0.2.2"`，README 仍没有与快照字节一致的布局说明。把 `tokenize` 等内部 `pub` 收成非公开会牵动评测包。
