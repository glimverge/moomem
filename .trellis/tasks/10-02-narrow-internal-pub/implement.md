# 执行

1. 去掉 design.md 列出的 `pub`。
2. 新增白盒测试承接原黑盒里的内部断言：`src/diag_wbtest.mbt`、`src/json_codec_wbtest.mbt`、`src/persist_wbtest.mbt`。
3. 导入对抗测试改为手写 JSON 行。
4. 评测包内私有函数计算诊断用 cos/jac。
5. 更新 `.trellis/spec/library/public-api-and-types.md` 与 `directory-structure.md` 里「这些 helper 保持 pub」的句子。
6. `moon test --target native` 失败数为 0。
