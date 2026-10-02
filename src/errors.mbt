// moomem 统一错误类型。
// 一切可失败函数返回 Result[T, MoomemError]；禁止 panic / abort。

///|
/// moomem 全库唯一错误类型。
/// 声明为 suberror：内部实现可用 raise 风格传播，公开 API 统一 Result[T, MoomemError]。
pub(all) suberror MoomemError {
  /// user_id 非法：含路径穿越字符 / 非法字符 / 超长 / 为空
  InvalidUserId(String)
  /// 存储损坏：header 缺失 / 版本不符 / 双槽均损坏 / 快照中位损坏
  StoreCorrupted(String)
  /// fs 层错误包装
  IoFailure(String)
  /// 提取器连续失败达到上限（PRD 第 9 章）
  ExtractionFailure(String)
  /// 嵌入服务失败
  EmbeddingFailure(String)
  /// 当前后端不支持该操作（如 wasm/js 无注入后端时的写操作）
  BackendUnsupported(String)
  /// 状态机非法迁移 / 非法操作（如 store 已关闭、目标条目不存在）
  InvalidOperation(String)
}

///|
/// 手写 Show（原 derive(Show) 输出格式保持不变：Variant(payload)）。
pub impl Show for MoomemError with fn output(self, logger) {
  match self {
    InvalidUserId(detail) => logger.write_string("InvalidUserId(\{detail})")
    StoreCorrupted(detail) => logger.write_string("StoreCorrupted(\{detail})")
    IoFailure(detail) => logger.write_string("IoFailure(\{detail})")
    ExtractionFailure(detail) =>
      logger.write_string("ExtractionFailure(\{detail})")
    EmbeddingFailure(detail) =>
      logger.write_string("EmbeddingFailure(\{detail})")
    BackendUnsupported(detail) =>
      logger.write_string("BackendUnsupported(\{detail})")
    InvalidOperation(detail) =>
      logger.write_string("InvalidOperation(\{detail})")
  }
}

///|
pub extend MoomemError with Show::{to_string, output}

///|
/// 人类可读的错误消息（含上下文），供宿主程序展示。
pub fn MoomemError::message(self : MoomemError) -> String {
  match self {
    InvalidUserId(detail) => "invalid user_id: \{detail}"
    StoreCorrupted(detail) => "store corrupted: \{detail}"
    IoFailure(detail) => "io failure: \{detail}"
    ExtractionFailure(detail) => "extraction failure: \{detail}"
    EmbeddingFailure(detail) => "embedding failure: \{detail}"
    BackendUnsupported(detail) => "backend unsupported: \{detail}"
    InvalidOperation(detail) => "invalid operation: \{detail}"
  }
}

///|
/// 错误类别短名（供 metadata / 日志使用）
pub fn MoomemError::kind(self : MoomemError) -> String {
  match self {
    InvalidUserId(_) => "invalid_user_id"
    StoreCorrupted(_) => "store_corrupted"
    IoFailure(_) => "io_failure"
    ExtractionFailure(_) => "extraction_failure"
    EmbeddingFailure(_) => "embedding_failure"
    BackendUnsupported(_) => "backend_unsupported"
    InvalidOperation(_) => "invalid_operation"
  }
}
