# Implement — README 介绍页与 site MVP

## Checklist

1. [x] 改写 `README.md` 为介绍骨架（按 `design.md`）；迁出章节改为站内链接
2. [x] 更新 `site/rspress.config.ts`（title、socialLinks）与 `site/docs/_nav.json`
3. [x] 重写 `site/docs/index.md` 中文首页
4. [x] 重写 `guide/start/introduction.md`、`getting-started.md`；新建 `persistence.md`、`security.md`；更新 `start/_meta.json` 与 `guide/_meta.json`
5. [x] 充实 `api/index.mdx`、`api/commands.mdx`（必要时加 `llm` 页并更新 `api/_meta.json`）
6. [x] 给 `benchmark/index.mdx` 补中文导语与命令入口（不改归档数据逻辑）
7. [x] 删除 `site/docs/guide/use-mdx/**` 整树
8. [x] 本地 `pnpm`/`npm` 在 `site/` 下 build 或 dev 冒烟（按仓库既有脚本），确认无断链到已删页
9. [x] 纠正发布状态：`README.md` / `guide/start/getting-started.md` 去掉「尚未发布」，安装改为 `moon add heyq02/moomem`（不钉版本号）

## Validation

```bash
# 站点构建（以 site/package.json scripts 为准）
cd site && pnpm install && pnpm build
```

人工扫：README 链接 → 站内路径；主导航无 rspress / use-mdx。

## Rollback

还原 `README.md` 与 `site/docs/**`、`rspress.config.ts` 即可；无运行时数据迁移。

## Risky files

- `README.md`（对外第一印象）
- `site/docs/_nav.json`、`guide/_meta.json`（断链风险）
- 删除 `use-mdx/**`（须同步 meta）
