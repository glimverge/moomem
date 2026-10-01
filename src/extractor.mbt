// 注入点二：Extractor（PRD 第 9 章 / 13.1 提取契约）。
// 缺省实现 RawExtractor：raw 直通模式——原文以 kind=Unstructured 入库，
// 零 LLM Key 可跑（AC-05 降级路径的天然形态）。

/// 提取器产出的一条结构化事实。
pub(all) struct ExtractedFact {
  content : String
  kind : EntryKind
  /// 原文依据 span（LLM 提取器填写；raw 模式为 None）
  source_span : String?
} derive(Show)

/// 事实提取抽象。生产环境注入 mizchi/llm 等适配实现。
pub(open) trait Extractor {
  /// 提取纪律（PRD 13.1）：只保留可复用信息；不改写事实本身；宁少勿错。
  /// 返回空数组 = 纯闲聊，不入库。
  extract(
    self : Self,
    user_id : String,
    text : String
  ) -> Result[Array[ExtractedFact], MoomemError]
  /// 提取模式标识："raw" | "llm"——记入 stats/export（12.3 可解释）。
  mode(self : Self) -> String
}

/// 缺省提取器：原文直通（kind=Unstructured），不发生闲聊过滤——
/// 原文即记忆，即 PRD 第 9 章的 raw 模式。
/// 空白文本返回 0 条事实（提取结果为空 → 不入库）。
pub struct RawExtractor {}

pub fn RawExtractor::new() -> RawExtractor {
  RawExtractor::{}
}

pub impl Extractor for RawExtractor with extract(_, _, text) {
  if is_blank_text(text) {
    return Ok([])
  }
  Ok([ExtractedFact::{ content : text, kind : Unstructured, source_span : None }])
}

pub impl Extractor for RawExtractor with mode(_) {
  "raw"
}

fn is_blank_text(text : String) -> Bool {
  text.trim().length() == 0
}
