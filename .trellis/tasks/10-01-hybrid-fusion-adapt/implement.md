# Implement — 查询自适应融合

## Checklist

1. [x] `types.mbt`：`FusionPolicy` + Config 字段 + `Config::default()` 校验常量
2. [x] `ranker.mbt`：`rrf_weighted` / `lexical_strong` / `protect_bm25_topk`；wbtests
3. [x] `store.mbt` `recall`：保留 `(id,score)`；按 policy 选权重再融合；`open` 校验新字段
4. [x] 扩展 `ci/tools/retrieval-tuning`：词法/释义 case + equal vs adaptive 对比 + 小网格扫参；**不**读 LoCoMo
5. [x] 根据 tuning 输出写入正式缺省常量
6. [x] Holdout：`moon run ci/eval/locomo --target native -- --embedder api` → hybrid ≥ bm25
7. [x] 离线：`moon run ci/eval/locomo --target native` → `LOCOMO_PASS`
8. [x] `moon test --target native`（121 passed）
9. [x] 文档：`docs/project/08-w4-eval-report.md` §七 + `09-handover.md` P7

## Validation

```bash
moon test --target native
moon run ci/tools/retrieval-tuning --target native
moon run ci/eval/locomo --target native
set -a && source .env && set +a
moon run ci/eval/locomo --target native -- --embedder api
```

## Defaults chosen

| Constant | Value |
|----------|------:|
| `DEFAULT_LEXICAL_FLOOR` | 0.8 |
| `DEFAULT_LEXICAL_GAP` | 1.1 |
| `DEFAULT_VEC_WEIGHT_LEXICAL` | 0.05 |
| `DEFAULT_VEC_WEIGHT_SEMANTIC` | 0.45 |
| `fusion_policy` default | `AdaptiveLexical` |

## Holdout results

- Offline hashing：hybrid 0.435 = BM25 0.435 → `LOCOMO_PASS`
- API QWEN：hybrid 0.435 = BM25 0.435 → hard gate pass；`TARGET_15PCT` missed (stretch)

## Risky files

- `src/store.mbt` recall
- `src/types.mbt` Config 兼容（结构体加字段）
- 所有手写 `Config::{...}` 的测试/examples 已改 `..default()`

## Rollback

`Config.fusion_policy = EqualRrf` 或还原本任务 diff。
