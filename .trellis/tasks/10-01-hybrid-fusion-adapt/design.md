# Design — 查询自适应融合

## Constraints

- Keep `MemoryStore` host surface；融合改动限 `ranker.mbt` + `store.mbt` recall 路径 + `Config`
- Do **not** tune thresholds on LoCoMo scored QA；only verify
- Defaults stay offline-deterministic (adaptive uses BM25/vector **scores already computed locally**)

## Algorithm (MVP)

今日：两路 `search` → 丢弃 score → 等权 `rrf(k)`.

改为：

1. 取 `kw_hits: Array[(id, bm25)]`、`vec_hits: Array[(id, cos)]`（长度 `candidates_n`）。
2. **词法置信**（只用 BM25 分数尺度，避免与 cosine 硬比）：
   - `b1` = 首条 BM25 score（无命中则 0）
   - `b2` = 第二条 BM25 score（不足则 0）
   - `lexical_strong` ⇔ `b1 >= lexical_floor` 且（仅 1 命中 **或** `b1 >= b2 * lexical_gap`）
3. **加权 RRF**：
   - `score(id) = w_v/(rrf_k+rank_v) + w_b/(rrf_k+rank_b)`（缺席通道该路贡献 0）
   - `lexical_strong` → `(w_v, w_b) = (vec_weight_when_lexical, 1 - vec_weight_when_lexical)`，其中 `vec_weight_when_lexical` 缺省偏小（如 0.15）
   - 否则 → `(w_v, w_b) = (vec_weight_when_semantic, 1 - …)`，缺省近均衡或略抬向量（如 0.45 / 0.55）
4. `FusionPolicy::Equal_rrf` → 强制 `w_v=w_b=1`（今日行为，回退用）

嵌入失败（空 qvec）时保持现逻辑：实质 BM25 单路。

## Config surface

```
FusionPolicy::Equal_rrf | adaptive_lexical   // default: adaptive_lexical

// 仅 adaptive 使用；缺省值由独立集校准后写入常量
lexical_floor : Double      // BM25 top1 下限
lexical_gap : Double        // top1/top2 倍差，缺省例如 1.2
vec_weight_when_lexical : Double   // (0,1)，缺省 ~0.15
vec_weight_when_semantic : Double  // (0,1)，缺省 ~0.45
```

校验：权重 ∈ (0,1]；gap ≥ 1；floor ≥ 0。非法 → `open` 时 `Err`（与现有 config 校验一致）。

**不**新增公开 recall 方法；不新增 trait。

## Independent tuning set

扩展 `ci/tools/retrieval-tuning`：

- 保留现有合成事实 + 冲突网格
- 新增检索对照：同一语料上跑 `equal_rrf` vs `adaptive_lexical`，打印 Recall@5 / MRR
- 增加**词法向**查询（关键词命中）与**释义向**查询（同义改写、无共享表面词）两类 case，用于定 `floor/gap/weights`
- 网格只扫自适应超参；**禁止**读 LoCoMo fixture 调参

选定缺省后写入 `src/types.mbt` 常量；tuning 工具打印「建议组合」供人工确认是否与常量一致。

## Holdout

```bash
moon run ci/eval/locomo --target native -- --embedder api
```

AC2：无 `gate fail: hybrid ... < bm25`。Stretch 看 `TARGET_15PCT`。

离线 hashing：允许仍低于 BM25（报告-only）；但自适应应**缩小**与 BM25 的差距或至少不显著恶化 `LOCOMO_PASS` 其它门。

## Tests

- `index_wbtest` / 新 wbtest：加权 RRF 数学；`lexical_strong` 边界（单命中、倍差、floor）
- store 级：注入可控 embedder + 固定语料，断言强词法 query 结果贴近 BM25 序、弱词法 query 仍融合向量

## Tradeoffs

| 选择 | 利 | 弊 |
|------|----|----|
| 只用 BM25 分数判词法强 | 尺度自洽 | floor 依赖语料长度，需用 tuning 集校准 |
| 软加权而非硬切 BM25-only | 保留少量语义 | 强词法题可能仍略逊纯 BM25；可用更低 `vec_weight_when_lexical` 逼近 |
| 默认开启 | 产品缺省变好 | 行为变化；用 `equal_rrf` 回退 |

## Rollback

`Config.fusion_policy = equal_rrf` 或发版回退常量缺省。
