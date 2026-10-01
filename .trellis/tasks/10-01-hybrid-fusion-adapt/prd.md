# 混合检索自适应融合与扫参

## Goal

落地**查询自适应融合**（默认开启、Config 可回退等权 RRF），不拆 `MemoryStore`、不在 LoCoMo 计分子集调参；LoCoMo `--embedder api` 上 hybrid Recall@5 **≥ BM25**（+15% 为 stretch）。

## Decisions

| ID | 决策 | 选择 |
|----|------|------|
| D1 | 主路径 | 查询自适应融合；独立集定参；LoCoMo api holdout |
| D2 | 成功门槛 | 硬：api hybrid ≥ BM25；stretch：+15% |
| D3 | 缺省 | **默认开启**；可配回退等权 RRF |

## Requirements

- **R1** 融合策略经 `Config`；公开方法集不变
- **R2** 阈值/权重只在独立开发集（扩展 `ci/tools/retrieval-tuning`）上选定
- **R3** `moon test` + 离线 LoCoMo `LOCOMO_PASS` 不退化
- **R4** 文档（08 补记或站点 Benchmark 注）写明算法、缺省、holdout 数字

## Acceptance Criteria

- [x] AC1：独立集可对比「等权 RRF vs 自适应」
- [x] AC2：`moon run ci/eval/locomo -- --embedder api` → hybrid Recall@5 ≥ BM25
- [x] AC3：不拆公开 API；不计分子集拟合
- [x] AC4：自适应分支单测 + native `moon test` 绿
- [ ] AC5（stretch）：≥ BM25 +15% — 达成写入报告，未达不阻塞

## Out of scope

- 「抽取后建库」评测口径；换嵌入；重写 BM25；拆 store 接口
