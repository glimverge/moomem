# Changelog

Keep a Changelog 风格；版本号取自 `moon.mod` 与 `MOOMEM_VERSION`（两者须同步）。

## [Unreleased]

### 杂项 / 清理
- 删除 `.trellis/tasks/archive/`（20 个历史任务目录），移除与现行代码脱节的平行叙述
- 修正 `spec/library/directory-structure.md` 版本 0.6.0 → 0.7.1
- 刷新 `ARCHITECTURE.md` 版本/日期，并改定性为"设计边界文档"
- `AGENTS.md` Trellis 块指向 `.trellis/scripts`；`workspace/index.md` 模板去 `tasks/archive`
- `.gitignore` 增加 `.workbuddy/`
- 新增项目管理套件：`STATUS.md` / `ROADMAP.md` / `CHANGELOG.md` / `DECISIONS.md`

## [0.7.1] - 2026-10-02

### 修复
- 发版流程保证 `MOOMEM_VERSION` 与 `moon.mod` 锁定同步（`fix(release)`）
- 同步版本常量到 0.7.0 并文档化磁盘快照布局
- README 更新 demo 使用说明；新增 demo 环境配置示例

### 新增
- `llms.txt` 文档
- 扩展 `AGENTS.md`（moomem 与 demo 项目）

（更早版本不在此追溯；详见 git 历史）
