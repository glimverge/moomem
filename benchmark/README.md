# benchmark

LoCoMo 对话切片上的离线评测。它不是 ACL 2024 那套「让模型作答再给答案打分」的官方协议：这里把对话轮次写进 `MemoryStore`，看检索、近重复覆盖、用户隔离和重启。

```bash
moon run benchmark --target native
```

零网络，缺省 `RawExtractor` + `HashingEmbedder`。推送到 `main`、向 `main` 提 PR，以及发版 Quality Gate，都在 native 测试通过后跑它。必须打出 `LOCOMO_PASS`。

## 方案

- **检索。** 每段对话按 `sample_id` 入库。对非对抗问答 `recall(..., top_k=5)`，前 5 条里出现任一证据轮次算命中，报 Recall@5 和 MRR。类别 5 的对抗题不计入。混合检索和关掉向量的纯 BM25 各算一遍。这一档关掉冲突判定，避免近重复句子互相覆盖。
- **冲突。** `near_duplicate` 20 组：旧事实必须变成 `Superseded`，新事实必须仍可召回，正确率要到 80%。`semantic` 10 组只打印相似度，不记入这 80%。
- **隔离。** 两个用户各自召回，命中的 `user_id` 必须是本人。泄漏必须为 0。
- **重启。** 写入三条固定事实，关掉再打开同一目录，同一查询召回的条目 id 必须一致。
- **提取。** 离线跳过。原文直通，没有可对的提取结果。`extraction_gold.json` 留给宿主注入 `Extractor` 之后使用。

检索分数在缺省 hashing 下只打印。`hybrid ≥ BM25` 要另加 `--embedder api` 才成为门槛。

## 离线结论

最近一次 `moon run benchmark --target native`：`LOCOMO_PASS`。

| 项 | 结果 | 是否卡失败 |
|---|---|---|
| 混合检索 Recall@5 | 100/230（0.435），MRR 0.294 | 否 |
| 纯 BM25 Recall@5 | 100/230（0.435），MRR 0.310 | 否 |
| 近重复覆盖 | 19/20（0.950） | 是，已过 80% |
| 跨用户泄漏 | 0 | 是，已过 |
| 重启 id | 一致 | 是，已过 |
| 提取精度 | 跳过 | 否 |

缺省 hashing 的混合检索和纯 BM25 命中数相同，MRR 略低。多跳 9/42、开放域 2/11、单跳 49/114、时间类 40/63。近重复有一组相似度 0.806，离覆盖阈值 0.82 差 0.014（`MARGIN_WARN`）。10 组语义改写的旧条目都保持 `Active`。

这组数字说明缺省离线实现没有破坏隔离、重启和近重复覆盖。它不能拿去和 LoCoMo 排行榜上的答案质量比。真实嵌入和提取由宿主注入，不在这条流水线里。

## 数据

文件在 `benchmark/data/`。

| 文件 | 来源 | 规模 | 用途 |
|---|---|---|---|
| `locomo_subset.json` | LoCoMo 公开数据集派生切片 | 236 KB / 2 段对话 / 788 轮 / 301 QA | 检索 Recall@5 / MRR |
| `conflict_pairs.json` | 本项目自建 | 30 组 | 近重复覆盖与语义改写记录 |
| `extraction_gold.json` | 本项目自建 | 100 条对话 | 提取 Precision（离线不计分） |

### 许可

`locomo_subset.json` 派生自 **LoCoMo**，采用 **CC BY-NC 4.0**。

- 来源仓库：<https://github.com/snap-research/locomo>
- 源文件：`data/locomo10.json`
- 固定版本：commit `cbfbc1dba6bc53d00625212a0f22d55ffee7c1fc`（2024-08-10）
- 许可原文：<https://creativecommons.org/licenses/by-nc/4.0/>
- 引用：Maharana, A., Lee, D.-H., Tulyakov, S., Bansal, M., Barbieri, F., & Fang, Y. *Evaluating Very Long-Term Conversational Memory of LLM Agents.* ACL 2024. arXiv:2402.17753

仅限非商业用途，且必须保留署名。本仓库代码是 Apache-2.0，这份派生数据不适用 Apache-2.0。仓库不重新分发完整 LoCoMo（原始 2.8 MB / 10 段对话），只提交这两段切片；`img_url`、`blip_caption`、`query` 已去掉。

### `locomo_subset.json`

```jsonc
{
  "meta": { /* 来源、许可、引用、字段语义 */ },
  "conversations": [
    {
      "sample_id": "conv-26",
      "speaker_a": "Caroline",
      "speaker_b": "Melanie",
      "sessions": [
        {
          "session": 1,
          "date_time": "1:56 pm on 8 May, 2023",
          "turns": [ { "dia_id": "D1:1", "speaker": "Caroline", "text": "..." } ]
        }
      ],
      "qa": [
        {
          "question": "When did Caroline go to the LGBTQ support group?",
          "category": 2,
          "evidence": ["D1:3"],
          "answer": "7 May 2023"
        }
      ]
    }
  ]
}
```

- `turns[].dia_id` 是命中判定的标识。每个轮次写成一条记忆，召回后按 `dia_id` 对证据。
- `qa[].evidence` 是含答案的轮次列表。top-k 里任一记忆对上其中的 `dia_id` 即命中。
- `qa[].category`：1 多跳，2 时间，3 开放域，4 单跳，5 对抗（对话中无答案，不计入检索指标）。
- 只保留证据轮次都在本次切片里的问答。证据落在被裁掉会话中的问答已丢弃。

### `conflict_pairs.json`

```jsonc
{
  "meta": { /* 分组语义与期望值定义 */ },
  "near_duplicate": [ { "id": "N01", "old": "...", "new": "...", "expect": "supersede" } ],
  "semantic": [ { "id": "S01", "old": "...", "new": "...",
                  "expect_offline": "ignore", "expect_live": "supersede",
                  "rationale": "..." } ]
}
```

- `near_duplicate`（20 组）改一个词或数字，字面高度重合。缺省 `SimilarityJudge` + `HashingEmbedder` 下期望 `supersede`，进离线门禁。
- `semantic`（10 组）是住址、职业、关系这类字面几乎不重叠的更新。缺省离线期望 `ignore`；语义覆盖要由宿主自己的 `ConflictJudge` 完成。离线只记录不计分。

### `extraction_gold.json`

```jsonc
{
  "meta": { /* 计分规则 */ },
  "cases": [
    {
      "id": "E001",
      "text": "今天天气真不错，哈哈。",
      "must_extract": [],
      "must_not_extract": []
    }
  ]
}
```

- `must_extract`：应该入库的事实要点，按子串关键词匹配。
- `must_not_extract`：出现即算假阳性的关键词。
- `must_extract` 为空表示这条输入不该产生入库事实。
