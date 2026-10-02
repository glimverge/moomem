# tests/locomo/data — 评测数据说明

本目录存放 LoCoMo 语料评测的数据文件。入口在 `tests/locomo/`，两者分开：
数据是内容资产，harness 是工程实现。

## 1. 文件清单

| 文件 | 来源 | 规模 | 用途 |
|---|---|---|---|
| `locomo_subset.json` | LoCoMo 公开数据集派生切片 | 236 KB / 2 段对话 / 788 轮 / 301 QA | 检索质量评测（Recall@5 / MRR） |
| `conflict_pairs.json` | 本项目自建 | 30 组 | 冲突处理评测（supersede 正确率） |
| `extraction_gold.json` | 本项目自建 | 100 条对话 | 提取质量评测（Precision） |

## 2. 第三方数据许可（重要）

`locomo_subset.json` 派生自 **LoCoMo** 数据集，采用
**Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)** 许可。

- 来源仓库：<https://github.com/snap-research/locomo>
- 源文件：`data/locomo10.json`
- 固定版本：commit `cbfbc1dba6bc53d00625212a0f22d55ffee7c1fc`（2024-08-10）
- 许可原文：<https://creativecommons.org/licenses/by-nc/4.0/>
- 引用要求：

  > Maharana, A., Lee, D.-H., Tulyakov, S., Bansal, M., Barbieri, F., & Fang, Y.
  > *Evaluating Very Long-Term Conversational Memory of LLM Agents.* ACL 2024.
  > arXiv:2402.17753

**使用限制**：仅限**非商业**用途，且必须保留署名。本仓库整体采用 Apache-2.0
许可，但**本目录下的派生数据不适用 Apache-2.0**，仍受 CC BY-NC 4.0 约束——
Apache-2.0 仅覆盖代码。请勿将本数据用于任何商业目的。

**再分发范围**：本仓库不重新分发 LoCoMo 完整数据集（原始 2.8 MB / 10 段对话），
仅包含用于可复现评测的最小派生切片；图片相关字段（`img_url` / `blip_caption` /
`query`）已移除。

**重新生成**（需要网络）：

```bash
python3 scripts/locomo/make_subset.py
# 或使用本地已下载的原始文件：
python3 scripts/locomo/make_subset.py --input /path/to/locomo10.json
```

生成器固定了上游 commit SHA，输出对该版本确定性可复现。

## 3. `locomo_subset.json` 结构

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

字段语义与评测约定：

- `turns[].dia_id` —— **评测的黄金标识**。每个轮次作为一条记忆写入 store，
  检索命中后按 `dia_id` 判定是否命中证据。
- `qa[].evidence` —— 含答案的对话轮 `dia_id` 列表；检索命中判定为
  「top-k 结果中存在任一 entry 对应到 `evidence` 中的 `dia_id`」。
- `qa[].category` —— 1=multi-hop / 2=temporal / 3=open-domain / 4=single-hop /
  **5=adversarial（对话中无答案，**不计入**检索指标）**。
- 仅保留 `evidence` 中所有 `dia_id` 都存在于本次索引轮次内的 QA；
  证据落在被裁掉会话中的 QA 已丢弃（不猜测、不补造）。

## 4. `conflict_pairs.json` 结构

```jsonc
{
  "meta": { /* 分组语义与期望值定义 */ },
  "near_duplicate": [ { "id": "N01", "old": "...", "new": "...", "expect": "supersede" } ],
  "semantic": [ { "id": "S01", "old": "...", "new": "...",
                  "expect_offline": "ignore", "expect_live": "supersede",
                  "rationale": "..." } ]
}
```

分组依据是**实测事实**，不是设计偏好：

- `near_duplicate`（20 组）—— 单槽位替换（改一个词/数字），字面高度重合。
  缺省 `SimilarityJudge` + `HashingEmbedder` 下相似度可过 0.82 阈值，期望 `supersede`。
  离线可判，**进离线门禁**。
- `semantic`（10 组）—— 语义型更新（住址/职业/关系变更），字面几乎无重叠。
  实测住址式对相似度仅 0.263–0.471，
  缺省离线配置下期望 `ignore`；语义覆盖要由宿主自己的 `ConflictJudge` 完成。
  **离线只记录不计分**，避免用不成立的期望值伪造达标。

## 5. `extraction_gold.json` 结构

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

- `must_extract` —— 该输入**应该**入库的事实要点（子串关键词，非唯一答案）；
- `must_not_extract` —— 出现即判为假阳性的关键词（如闲聊内容被当事实入库）；
- `must_extract` 为空的用例表示「不应产生任何入库事实」，用于压低 Precision
  分母之外的假阳性。

## 6. 这条语料在流水线里的位置

L3 离线评测由 `moon run tests/locomo --target native` 执行。push 流水线是否跑它、以及 L0–L2 的边界，以 `.github/workflows/test-pipeline.yml` 和 `.trellis/spec/library/quality-guidelines.md` 为准。`semantic` 组的相似度数字写在本文件第 4 节。
