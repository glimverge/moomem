# heyq02/moomem

<p>
  <a href="https://mooncakes.io/docs/heyq02/moomem/"><img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fmooncakes.io%2Fapi-new%2Fv0%2Fmanifest%2Fheyq02%2Fmoomem&query=%24.latest_version&label=mooncake&style=flat-square&colorA=564341&colorB=EDED91" alt="version" /></a>
  <a href="https://mooncakes.io/docs/heyq02/moomem/"><img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fmooncakes.io%2Fapi-new%2Fv0%2Fmanifest%2Fheyq02%2Fmoomem&query=%24.downloads&label=downloads&style=flat-square&colorA=564341&colorB=EDED91" alt="downloads" /></a>
  <a href="https://coveralls.io/github/glimverge/moomem?branch=main"><img src="https://img.shields.io/coverallsCoverage/github/glimverge/moomem?branch=main&style=flat-square&colorA=564341&colorB=EDED91" alt="coverage" /></a>
  <a href="https://github.com/glimverge/moomem/blob/main/LICENSE"><img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fmooncakes.io%2Fapi-new%2Fv0%2Fmanifest%2Fheyq02%2Fmoomem&query=%24.metadata.license&label=license&style=flat-square&colorA=564341&colorB=EDED91" alt="license" /></a>
</p>

MoonBit 嵌入式 Agent 记忆层。嵌在宿主进程里，崩溃后仍从上一份完整快照恢复。缺省不需要 API Key。

| | |
| --- | --- |
| 检索 | 向量 + BM25，按 `user_id` 分片 |
| 持久化 | native 双槽 JSONL + `head`；wasm、wasm-gc、js 只在进程内存 |
| 缺省 | 离线、确定性。要换模型，注入 `Embedder`、`Extractor`、`ConflictJudge` |

## 使用

```bash
moon add heyq02/moomem
```

```moonbit
fn main {
  let mem = @moomem.MemoryStore::open("./memory").unwrap()

  let summary = mem.add("user-42", "我对花生过敏").unwrap()
  println("extracted=\{summary.extracted} inserted=\{summary.inserted}")

  let hits = mem.recall("user-42", "花生过敏", top_k=3).unwrap()
  for e in hits {
    println("[\{e.created_at}] \{e.content}")
  }

  ignore(mem.close())
}
```

> [!NOTE]
> 同一目录再次 `open`，记忆还在。wasm、wasm-gc、js 缺省只留在进程内存里。要换真实模型，在 `open` 时注入 `Embedder`、`Extractor`、`ConflictJudge`。

> [!TIP]
> native 上 `open("./memory")` 会写成 `<path>/moomem/head` 加两个 `slot*.jsonl`。先把整份快照写入非当前槽，成功后再拨 `head`。索引不落盘，`open` 时从快照重建。

## 作用

Qwen 和 DeepSeek 只把一句话变成向量和事实，它们不保存。moomem 把结果按 `user_id` 留下，下次 `recall` 从这里取，不再把原话发给模型。

[`playground/`](playground/) 依赖已发布的 `heyq02/moomem`，注入这两个模型后跑 `moon run cmd/main`。下面是这一轮的结果：

| 检查 | 跑出来的结果 | moomem 做了什么 |
|---|---|---|
| 我对花生过敏、我住在北京 | `extracted=1 inserted=1` | 收下模型抽出的事实 |
| 今天天气不错 | `extracted=0 inserted=0` | 闲聊不入库 |
| 过敏再说一遍 | `duplicates=1 inserted=0` | 认出重复，不存成第二条 |
| 另一个用户搜过敏 | 无命中 | 按用户隔开 |
| 关掉再 `open` | 过敏和住址还在 | 写在磁盘上，不靠这次进程 |
| `forget` 后再搜过敏 | 不再出现 | 删掉一条，之后的召回遵守这次删除 |

> [!NOTE]
> 没有另跑一个摘掉 moomem 的对照。上表这些 `user_id`、`./memory`、关掉再打开还在，模型接口本身没有。

> [!IMPORTANT]
> 「我搬到深圳了」没有盖掉「我住在北京」。缺省冲突判定只在相似度够高时覆盖，这两句会并存。

## LoCoMo 抽样

本地 `moon run benchmark --target native`，密钥在 `benchmark/.env`。远端不跑。

| 类别 | 判对 |
| --- | --- |
| 多跳 | 4/4 |
| 时间 | 2/3 |
| 开放 | 1/1 |
| 单跳 | 10/12 |
| **合计** | **17/20** |

> [!IMPORTANT]
> 这 20 题不是 Mem0 公布的全量 1540 题，也不能和他们 top 200、GPT 作答的 92.5% 直接比。逐题记录在 `benchmark/results/locomo-20.json`。

> [!WARNING]
> 题目文件派生自 LoCoMo，CC BY-NC 4.0，不适用本仓库的 MIT。

<details>
<summary>抽样协议</summary>

协议对齐 [memory-benchmarks](https://github.com/mem0ai/memory-benchmarks) 的 LoCoMo：按轮次写入，检索后让模型只根据命中作答，裁判判 `CORRECT` / `WRONG`。固定种子 `20261014` 抽到 Evan / Sam 这一段（509 轮），再抽 20 道可计分题。嵌入是 `qwen3.7-text-embedding-flash`，作答和裁判都是 `deepseek-flash`。`recall` 每次取前 50 条。

</details>

## License

<!-- automd:contributors license=MIT author="heyq02" github="glimverge/moomem" -->

Published under the [MIT](https://github.com/glimverge/moomem/blob/main/LICENSE) license.
Made by [@heyq02](https://github.com/heyq02) and [community](https://github.com/glimverge/moomem/graphs/contributors) 💛
<br><br>
<a href="https://github.com/glimverge/moomem/graphs/contributors">
<img src="https://contrib.rocks/image?repo=glimverge/moomem" />
</a>

<!-- /automd -->

<!-- automd:with-automd -->

---

_🤖 auto updated with [automd](https://automd.unjs.io)_

<!-- /automd -->
