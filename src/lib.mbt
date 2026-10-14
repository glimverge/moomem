// moomem —— MoonBit 嵌入式 Agent 记忆层库
//
// 公开 API 表面（详见 README.md）：
//   MemoryStore::open / add / recall / forget / stats / close
//   注入点 trait：Embedder / Extractor / ConflictJudge / PersistenceBackend / Clock
//   错误类型：MoomemError
//
// 设计约束：
//   - 一切可失败操作返回 Result[T, MoomemError]，禁止 panic
//   - JSON 编解码只出现在 json_codec.mbt
//   - fs 调用只出现在 persist.mbt（moonbitlang/x/fs 唯一依赖）

///|
/// 库版本号。与 `moon.mod` 和 `package.json` 相同，由 `bumpp` 一起改。
/// `SNAPSHOT_VERSION` 是快照格式，不跟着发版号走。
pub const MOOMEM_VERSION : String = "0.7.3"

///|
/// 快照格式版本（header 中的 "v" 字段）
pub const SNAPSHOT_VERSION : Int32 = 1
