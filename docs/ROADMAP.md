# moomem 路线图（ROADMAP）

> 当前状态见 [STATUS.md](STATUS.md)；决策理由见 [DECISIONS.md](DECISIONS.md)。按优先级与阶段组织；`[ ]` 未启动 / `[~]` 进行中 / `[x]` 完成。

## 优先级约定
- **P1**：影响可用性或竞赛评审可信度，应优先
- **P2**：产品取舍型短板，按需推进
- **P3**：卫生项（文档 / 口径同步）

## 近期（下一个迭代）
- [ ] **P3 修对外口径** — 申报书"当前版本 0.7.0" → 0.7.1；补"不含并发锁/鉴权"边界说明。产出：`项目申报书.md` 改动。
- [ ] **P1 检索融合 W5** — LoCoMo 打分子集上做 train/test 隔离 A/B；调 `vector_weight_when_lexical` / `protect_bm25_topk` / `coexist_band`；目标收敛 −12%；记录过拟合风险。
- [ ] **P1 规模落地** — 补 append-mode `PersistenceBackend` 官方示例 + 1k/10k/100k 条 `flush` 耗时基准脚本，把"逃生舱"变可落地路径。
- [ ] **P2 缺省语义边界** — README 明示"缺省路径不覆盖改写类事实"；评估可选轻量近义判定（仍离线），需评测佐证。
- [ ] **P2 并发约束** — 提供带内部锁的 `StoreGuard` 包装示例；或把"单写者"在 README 上升为醒目约束。
- [ ] **P3 发版纪律** — `bump-version.sh` 校验 `moon.mod == MOOMEM_VERSION`；CI 加断言，杜绝版本分裂。

## 中期（产品 hardened）
- [ ] 规模压测 + 明确条数上限 / 建议配置
- [ ] 真实模型注入的官方文档与最小示例（不止 `demo/`）
- [ ] 并发多写者方案评估（内部锁 vs 明确不支持）
- [ ] 鉴权 / 多租户边界说明与可选方案

## 长期（生态）
- [ ] mooncakes 文档站点持续维护
- [ ] 更多检索 / 融合策略的可插拔接口
- [ ] 与主流 Agent 框架的集成示例

## 验证手段（贯穿各阶段）
- `moon test` 四后端 + 覆盖率 ≥90%（CI 强制）
- `moon run benchmark --target native`（检索 / 覆盖 / 隔离 / 重启）
- 三条零网络示例冒烟（default-reopen / host-inject-supersede / isolation-forget-import）
- 补漏项专项验证见 STATUS「开放问题」与各 PR 描述
