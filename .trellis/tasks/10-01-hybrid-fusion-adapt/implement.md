# Implement — 查询自适应融合

## Checklist

1. [ ] `types.mbt`：`FusionPolicy` + Config 字段 + `Config::default()` 校验常量占位
2. [ ] `ranker.mbt`：`rrf_weighted`（或扩展 `rrf`）；`lexical_strong` 辅助；单测
3. [ ] `store.mbt` `recall`：保留 `(id,score)`；按 policy 选权重再融合；`open` 校验新字段
4. [ ] 扩展 `ci/tools/retrieval-tuning`：词法/释义 case + equal vs adaptive 对比 + 小网格扫参；**不**读 LoCoMo
5. [ ] 根据 tuning 输出写入正式缺省常量（若与占位不同）
6. [ ] Holdout：`moon run ci/eval/locomo --target native -- --embedder api`（需 `.env` 映射）
7. [ ] 离线：`moon run ci/eval/locomo --target native` → `LOCOMO_PASS`
8. [ ] `moon test --target native`；必要时 wasm 冒烟
9. [ ] 文档：`docs/project/08-w4-eval-report.md` 追加一节或站点 Benchmark 注 + handover P7 状态

## Validation

```bash
moon test --target native
moon run ci/tools/retrieval-tuning --target native
moon run ci/eval/locomo --target native
set -a && source .env && set +a
moon run ci/eval/locomo --target native -- --embedder api
```

## Risky files

- `src/store.mbt` recall
- `src/types.mbt` Config 兼容（结构体加字段）
- 所有手写 `Config::{...}` 的测试/examples 需补新字段或依赖 `..default()`

## Rollback

缺省改回 `equal_rrf` 或还原本任务 diff。
