// 注入点：Extractor。宿主实现事实提取；缺省是 RawExtractor。
// RawExtractor 把原文以 kind=Unstructured 入库，不调用模型。

///|
/// 提取器产出的一条结构化事实。
pub(all) struct ExtractedFact {
  content : String
  kind : EntryKind
  /// 原文依据 span（LLM 提取器填写；raw 模式为 None）
  source_span : String?
  /// 本条事实是否为「降级产物」（LLM 失败 → 退回原文 unstructured）。
  /// RawExtractor 的原文直通是设计形态，恒为 false；只有失败回退才置 true。
  degraded : Bool
  /// 降级原因（degraded=true 时非 None），供 notes/metadata 透传
  degrade_reason : String?
}

///|
/// 手写 Show（原 derive(Show) 输出格式保持不变：{content: ..., kind: ..., source_span: ...}）。
/// 新增字段 degraded / degrade_reason 故意不进入 Show 输出，保持既有断言稳定。
pub impl Show for ExtractedFact with fn output(self, logger) {
  let span = match self.source_span {
    Some(s) => "Some(\{s})"
    None => "None"
  }
  logger.write_string(
    "{content: \{self.content}, kind: \{self.kind}, source_span: \{span}}",
  )
}

///|
pub extend ExtractedFact with Show::{to_string, output}

///|
/// 事实提取抽象。结构化提取由宿主实现并注入。
pub(open) trait Extractor {
  /// 只保留可复用信息；不改写事实本身；宁少勿错。
  /// 返回空数组 = 纯闲聊，不入库。
  fn extract(self : Self, user_id : String, text : String) -> Result[
    Array[ExtractedFact],
    MoomemError,
  ]
  /// 提取模式标识："raw" | "llm"。记入 stats 与 export。
  fn mode(self : Self) -> String
}

///|
/// 缺省提取器：原文直通（kind=Unstructured）。
/// 空白文本返回 0 条事实，不入库。
pub struct RawExtractor {}

///|
pub fn RawExtractor::new() -> RawExtractor {
  RawExtractor::{ }
}

///|
pub impl Extractor for RawExtractor with fn extract(_, _, text) {
  if is_blank_text(text) {
    return Ok([])
  }
  Ok(
    [
      ExtractedFact::{
        content: text,
        kind: Unstructured,
        source_span: None,
        degraded: false,
        degrade_reason: None,
      },
    ],
  )
}

///|
pub impl Extractor for RawExtractor with fn mode(_) {
  "raw"
}

///|
pub extend RawExtractor with Extractor::{extract, mode}

///|
fn is_blank_text(text : String) -> Bool {
  text.trim().length() == 0
}
