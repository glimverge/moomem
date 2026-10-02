# 持久化

`open(path)` 在目录下使用双槽全量快照（对「追加写 JSONL」的有意工程折中：当前文件系统 API 无可靠 append/rename）。

## 目录布局

```
<path>/moomem/slot0.jsonl   # 快照槽 A（首行 header + 每行一条 entry JSON）
<path>/moomem/slot1.jsonl   # 快照槽 B
<path>/moomem/head          # "0" 或 "1"，指向当前有效槽
```

每次 `add` / `forget` / `close` 完整重写**非当前槽**，成功后再写 `head`。

## 崩溃恢复

| 情况 | 行为 |
|------|------|
| 写槽中途崩溃 | 旧槽仍有效，下次 open 读 `head` 指向的完整槽 |
| `head` 损坏 | 回退到可解析且 gen 更大的槽 |
| 尾部半行 | 丢弃并计入 `stats.truncated_recovered` |

## 条目状态机

```
(空) → Active → Superseded   （冲突 Replace，记录 superseded_by）
             → Deleted       （forget 软删除，快照保留可审计）
```

`recall` 永不返回 `Superseded` / `Deleted`；可返回 `Active` 与降级产生的 `Unstructured`。

## 相关

- [安全与限制](/guide/start/security) — 双槽快照的产品边界
