# playground

宿主示例。依赖已发布的 `heyq02/moomem@0.8.1`，不编译本仓库的 `src/`。Qwen 做嵌入，DeepSeek 做提取。

## 跑

在这个目录：

```bash
cp .env.example .env
moon update
moon run cmd/main
```

`.env` 需要 `DEEPSEEK_API_KEY`、`DEEPSEEK_BASE_URL`、`DEEPSEEK_MODEL`、`QWEN_API_KEY`、`QWEN_BASE_URL`、`QWEN_MODEL`。不要提交 `.env`。

## 它在验什么

`cmd/main` 会清掉 `./memory`，写入几句话，再关掉打开。任一检查失败就退出。

- 「我对花生过敏」「我住在北京」会入库
- 「今天天气不错」不入库
- 同一句过敏再说一遍，不再插入
- 另一个用户召回不到这些记忆
- 关掉再打开，记忆还在
- `forget` 之后，过敏不再被召回

「我搬到深圳了」不会盖掉「我住在北京」。缺省冲突判定只在相似度够高时覆盖，这两句会并存。问「我住在哪里」时，旧地址仍可能排在前面。

`memory/` 是运行时目录，由仓库根目录的 `.gitignore` 忽略。
