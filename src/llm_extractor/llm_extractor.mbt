// moomem W2：基于 mizchi/llm 的事实提取适配器。
//
// 架构约束（铁律）：核心包 src/ 不得 import mizchi/llm；
// 本包是独立适配层，仅依赖 mizchi/llm 主包（纯 trait/类型层，不含 ffi）。
// LLM 客户端通过 mizchi/llm 的 Provider trait 注入——
// 生产注入 OpenAIProvider / AnthropicProvider（mizchi/llm/openai 等子包），
// 测试注入任意 Provider 实现（本包测试用脚本化 mock，零网络）。

///|
/// 提取失败降级策略（PRD 13.3）。
pub(all) enum DegradePolicy {
  /// 降级：extract 返回原文的 unstructured 事实（不抛错），
  /// 失败原因通过 LlmExtractor::last_failure_reason() 可见。
  ReturnRaw
  /// 抛错：extract 返回 Err(原因)，由 MemoryStore 统一降级
  /// （AddSummary.degraded=true、notes 含原因、metadata.extraction_degraded=true，
  /// 并参与 PRD 第 9 章"连续 3 次失败熔断"）。
  PropagateError
}

///|
/// LLM 事实提取适配器：实现核心包的 Extractor trait（PRD 13.1 提取契约）。
///
/// 稳定性（PRD 13.3）：
///   - 单次 extract 最多 2 次 LLM 调用（首次 + 非法 JSON 重试 1 次）；
///   - 网络/鉴权失败不重试，直接降级（重试大概率同样失败且浪费预算）；
///   - 降级永不 panic，按 DegradePolicy 返回。
pub struct LlmExtractor {
  /// 注入的 LLM 客户端（mizchi/llm Provider trait 对象）
  provider : &@llm.Provider
  /// 单次提取最多接受的事实条数（宁少勿错 + 防 prompt 注入洪水，默认 16）
  max_facts : Int
  /// 降级策略（默认 ReturnRaw：不抛错）
  degrade : DegradePolicy
  /// 累计 LLM 调用次数（观测指标，用于验证调用预算）
  mut llm_calls : Int
  /// 最近一次提取/降级的失败原因；None = 最近一次提取成功
  mut last_failure : String?
}

///|
/// 构造 LLMExtractor。
/// provider：任意 mizchi/llm Provider 实现（真实 provider 或测试 mock）。
/// max_facts：单次提取接受的事实条数上限（默认 16）。
/// degrade：失败降级策略（默认 ReturnRaw，见 DegradePolicy 文档）。
pub fn LlmExtractor::new(
  provider : &@llm.Provider,
  max_facts? : Int = 16,
  degrade? : DegradePolicy = ReturnRaw,
) -> LlmExtractor {
  let cap = if max_facts < 1 { 1 } else { max_facts }
  LlmExtractor::{
    provider,
    max_facts: cap,
    degrade,
    llm_calls: 0,
    last_failure: None,
  }
}

///|
/// 累计 LLM 调用次数（观测：验证单次 add 提取链路 ≤ 2 次调用）。
pub fn LlmExtractor::llm_call_count(self : LlmExtractor) -> Int {
  self.llm_calls
}

///|
/// 最近一次失败原因；None = 最近一次提取成功。
/// 降级发生后宿主可读取此值上报/落日志（PRD 12.3 可解释）。
pub fn LlmExtractor::last_failure_reason(self : LlmExtractor) -> String? {
  self.last_failure
}

///|
/// 单次 LLM 调用：驱动 provider.stream，收集文本与流错误。
/// 网络失败、鉴权失败等以 StreamEvent::Error 形式上报（mizchi/llm 约定），
/// 本函数将其转为 Err(可读原因)；正常完成返回全部 TextDelta 拼接。
fn LlmExtractor::request(
  self : LlmExtractor,
  messages : Array[@llm.Message],
) -> Result[String, String] {
  self.llm_calls = self.llm_calls + 1
  let buf = StringBuilder()
  // 用数组而非可变局部做闭包捕获，避免跨闭包可变捕获的语义歧义
  let failure : Array[String] = []
  let handler : @llm.StreamHandler = @llm.StreamHandler::{
    on_event: fn(event : @llm.StreamEvent) {
      match event {
        @llm.StreamEvent::TextDelta(s) => buf.write_string(s)
        @llm.StreamEvent::Error(msg) => failure.push(msg)
        _ => ()
      }
    },
  }
  self.provider.stream(messages, [], handler)
  match failure.length() > 0 {
    true =>
      Err("llm provider '\{self.provider.name()}' stream error: \{failure[0]}")
    false => Ok(buf.to_string())
  }
}

///|
/// 按策略降级：返回原文 unstructured（不抛错）或 Err(原因)。
fn LlmExtractor::degrade_to(
  self : LlmExtractor,
  text : String,
  reason : String,
) -> Result[Array[@src.ExtractedFact], @src.MoomemError] {
  self.last_failure = Some(reason)
  match self.degrade {
    ReturnRaw =>
      Ok([
        @src.ExtractedFact::{
          content: text,
          kind: @src.EntryKind::Unstructured,
          source_span: None,
        },
      ])
    PropagateError =>
      Err(
        @src.MoomemError::ExtractionFailure("llm extractor degraded: \{reason}"),
      )
  }
}

///|
pub impl @src.Extractor for LlmExtractor with fn extract(self, _user_id, text) {
  // 空白文本：不消耗 LLM 调用，直接视为纯闲聊（与 RawExtractor 语义对齐）
  if text.trim().length() == 0 {
    return Ok([])
  }
  let system_msg = @llm.Message::system(extraction_system_prompt())
  let user_msg = @llm.Message::user(build_extraction_user_prompt(text))
  let messages : Array[@llm.Message] = [system_msg, user_msg]
  // ---- 第 1 次调用 ----
  let first : String = match self.request(messages) {
    Err(reason) =>
      // 网络/鉴权失败：不重试，直接降级（原因对宿主可见）
      return self.degrade_to(text, reason)
    Ok(resp) => resp
  }
  match parse_extraction_response(first, self.max_facts) {
    Ok(facts) => {
      self.last_failure = None
      return Ok(facts)
    }
    Err(parse_err) => {
      // ---- 非法 JSON：重试 1 次（带上纠正指令与上次输出）----
      let retry_messages : Array[@llm.Message] = [
        system_msg,
        user_msg,
        @llm.Message::assistant(first),
        @llm.Message::user(build_retry_prompt(parse_err)),
      ]
      let second : String = match self.request(retry_messages) {
        Err(reason) => return self.degrade_to(text, reason)
        Ok(resp) => resp
      }
      match parse_extraction_response(second, self.max_facts) {
        Ok(facts) => {
          self.last_failure = None
          Ok(facts)
        }
        Err(err2) =>
          self.degrade_to(
            text,
            "invalid JSON from llm after 1 retry; first: \{parse_err}; retry: \{err2}",
          )
      }
    }
  }
}

///|
pub impl @src.Extractor for LlmExtractor with fn mode(_) {
  "llm"
}

///|
pub extend LlmExtractor with @src.Extractor::{extract, mode}
