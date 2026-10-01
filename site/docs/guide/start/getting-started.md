# 快速上手

## 环境

- [moon](https://www.moonbitlang.com/) ≥ `0.1.20260920`（`moon version` 确认）

## 安装

:::note
尚未发布到 mooncakes。本地开发请用本仓库做 path 依赖，或把 `src/` 拷进工程。
:::

发布后在宿主 `moon.mod` / `moon.mod.json` 中加入：

```json
{
  "deps": {
    "heyq02/moomem": "0.3.0"
  }
}
```

## 最短代码

```moonbit
fn main {
  let mem = @moomem.MemoryStore::open("./memory").unwrap()

  // 对话结束后写入：提取 → 去重 → 冲突 → 嵌入 → 双索引 → 落盘
  let summary = mem.add("user-42", "我对花生过敏").unwrap()
  println("extracted=\{summary.extracted} inserted=\{summary.inserted}")

  // LLM 调用前召回：混合检索，只返回该用户记忆
  let hits = mem.recall("user-42", "花生过敏", top_k=3).unwrap()
  for e in hits {
    println("[\{e.created_at}] \{e.content}")
  }

  ignore(mem.close())
}
```

次日再 `open` 同一目录：记忆完整，recall 行为一致。

## CLI 快速演示

```bash
# 直接跑包
moon run src/cli --target native -- add \
  --db ./mem --user user-42 --text "我对花生过敏"

moon run src/cli --target native -- recall \
  --db ./mem --user user-42 --query "花生过敏"
```

完整子命令与环境变量见 [CLI](/api/commands)。可选 LLM 提取：

```bash
export MOOMEM_LLM_API_KEY=...
moon run src/cli --target native -- add \
  --db ./mem --user user-42 --text "你好！我对花生过敏" --llm
```

## 零网络示例

```bash
moon run examples/basic-store --target native
moon run examples/llm-extractor --target native
moon run examples/conflict-supersede --target native
moon run examples/cli-smoke --target native
```

## 下一步

- [持久化](/guide/start/persistence) — 目录布局与条目状态
- [安全与限制](/guide/start/security)
- [公开 API](/api/) — MemoryStore 六方法与注入点
- [LLM 注入](/api/llm)
- [Benchmark](/benchmark/) — 评测分数与本地复跑
