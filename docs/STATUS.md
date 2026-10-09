# moomem 项目状态（STATUS）

> 单一可信视图：**现在在哪、已知问题、下一步**。详细规划见 [ROADMAP.md](ROADMAP.md)，变更历史见 [CHANGELOG.md](CHANGELOG.md)，决策理由见 [DECISIONS.md](DECISIONS.md)。
> 本文件解决"项目管理乱"的核心痛点：项目有"怎么写代码"（AGENTS）、"是什么"（README/ARCHITECTURE）、"为什么参赛"（申报书），但缺一个"现在在哪 / 要去哪 / 为什么这么定"的单一入口。

## 一句话定位
MoonBit 嵌入式 Agent 记忆层——进程内、零部署、离线确定性、崩溃可恢复、按 `user_id` 隔离。接口契约参考 mem0 的 `add→recall`，落地形态参考嵌入式数据库（快照即真相，索引打开时重建）。

## 版本与成熟度
- 当前版本：**0.7.1**（`moon.mod` == `MOOMEM_VERSION`，已对齐）
- 许可证：MIT，已发布 mooncakes.io（`heyq02/moomem`）
- 成熟度：**可用但非生产 hardened**——核心链路（add/recall/双槽快照/隔离）扎实；规模、并发、鉴权、语义缺省仍是已知短板
- 竞赛上下文：黑客松/竞赛参赛项目（参赛者 Ari，方向"AI 应用 / 嵌入式 Agent 记忆库"）

## 当前状态快照

### 已落地（可信）
- **脊柱**：`MemoryStore` 9 方法 + 5 注入 trait，宿主面契约锁死，内部实现不对外
- **崩溃恢复**：双槽 JSONL + `head`，尾部半行丢弃计 `truncated_recovered`，中部坏行报 `StoreCorrupted`
- **用户隔离**：索引/检索/去重/增删全显式 `user_id`，无全库召回
- **可审计**：`superseded` / `deleted` 旧条目留快照，`recall` 只返 active/unstructured
- **质量门**：`moon test` 四后端（native ≥76 用例）、`src/` 覆盖率 ≥90%、LoCoMo 离线评测、三条零网络示例
- **文档治理（2026-10-09）**：删 trellis archive、修 spec/ARCHITECTURE 版本漂移、修 `.gitignore`、建本管理套件

### 开放问题（带优先级，详见 ROADMAP）
| 优先级 | 问题 | 影响 |
|--------|------|------|
| **P1** | 检索质量：混合检索在 LoCoMo 词法任务上比纯 BM25 低约 12% | 语义弱场景召回不足 |
| **P1** | 规模写放大：每次 `flush` 重写整份条目，未做规模压测、不承诺上限 | 大数据量 native 可用性存疑 |
| **P2** | 缺省语义弱：哈希嵌入下"搬家"类改写不自动覆盖，需宿主注入真模型 | 缺省路径下覆盖改写失效 |
| **P2** | 并发：单写者无内部锁 | 多 Agent 并发直连有风险 |
| **P2** | 鉴权：隔离仅靠调用方传 `user_id`，无账号体系 | 多租户误用会串数据 |
| **P3** | 对外口径：申报书仍写"当前版本 0.7.0"（实际 0.7.1） | 评审/外部认知失真 |

## 下一步（最近一个迭代）
1. **P3** 修对外口径：申报书 0.7.0 → 0.7.1，补"不含并发锁/鉴权"边界说明
2. **P1** 检索融合 W5：train/test 隔离 A/B，收敛 −12%
3. **P1** 规模落地：append-mode `PersistenceBackend` 官方示例 + 规模基准

完整清单见 [ROADMAP.md](ROADMAP.md)。

## 文档导航
- 用户契约 / 使用：`../README.md`
- 设计边界：`../ARCHITECTURE.md`
- 竞赛申报（陈旧，待同步）：`项目申报书.md`
- 开发者操作：`../AGENTS.md`
- 项目管理：**本文件** · 规划 `ROADMAP.md` · 变更 `CHANGELOG.md` · 决策 `DECISIONS.md`
