# 执行

1. 去掉 design.md 列出的 `pub`。
2. 新增白盒测试承接原黑盒里的内部断言：`src/diag_wbtest.mbt`、`src/json_codec_wbtest.mbt`。崩溃注入测试写在 `src/persist.mbt` 末尾，不另建 `persist_wbtest.mbt`。`moon check` 不把 `*_wbtest.mbt` 算作引用，只在 wbtest 里调用的包内方法会报 unused。
3. 导入对抗测试改为手写 JSON 行。
4. 评测包内私有函数计算诊断用 cos/jac。
5. 更新 `.trellis/spec/library/public-api-and-types.md` 与 `directory-structure.md` 里「这些 helper 保持 pub」的句子。
6. `moon test --target native` 失败数为 0。
