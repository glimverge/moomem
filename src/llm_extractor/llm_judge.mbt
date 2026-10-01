// moomem W2：基于 mizchi/llm 的冲突判定适配器（PRD 13.2 冲突判定契约）。
//
// 实现 ConflictJudge trait 的 LLM 裁决版：
//   - replace：新事实与旧条目矛盾/更新旧条目（触发 supersede 状态机）；
//   - coexist：相关但都有效（并存并标记 metadata）；
//   - ignore：无关（不产生裁决）。
//
// 稳定性（与 LlmExtractor 对齐）：
//   - 无候选时零 LLM 调用；
//   - 单次 judge 最多 2 次 LLM 调用（首次 + 非法 JSON 重试 1 次）；
//   - 重试仍失败返回 Err，由 MemoryStore 降级为"不产生裁决"（两条并存，
//     AddSummary.degraded=true、notes 含原因——失败对宿主可见）。

/// LLM 冲突判定适配器：实现核心包的 ConflictJudge trait。
pub struct LlmConflictJudge {
  /// 注入的 LLM 客户端（mizchi/llm Provider trait 对象）
  provider : &@llm.Provider
  /// 累计 LLM 调用次数（观测指标）
  mut llm_calls : Int
  /// 最近一次失败原因；None = 最近一次判定成功
  mut last_failure : String?
}

/// 构造 LlmConflictJudge。provider 可为真实 provider 或测试 mock。
pub fn LlmConflictJudge::new(
  provider : &@llm.Provider
) -> LlmConflictJudge {
  LlmConflictJudge::{
    provider,
    llm_calls : 0,
    last_failure : None,
  }
}

/// 累计 LLM 调用次数（观测：单次 judge ≤ 2 次）。
pub fn LlmConflictJudge::llm_call_count(self : LlmConflictJudge) -> Int {
  self.llm_calls
}

/// 最近一次失败原因；None = 最近一次判定成功。
pub fn LlmConflictJudge::last_failure_reason(self : LlmConflictJudge) -> String? {
  self.last_failure
}

/// 单次 LLM 调用（与 LlmExtractor::request 同构）。
fn LlmConflictJudge::request(
  self : LlmConflictJudge,
  messages : Array[@llm.Message]
) -> Result[String, String] {
  self.llm_calls = self.llm_calls + 1
  let buf = StringBuilder()
  let failure : Array[String] = []
  let handler : @llm.StreamHandler = @llm.StreamHandler::{
    on_event : fn(event : @llm.StreamEvent) {
      match event {
        @llm.StreamEvent::TextDelta(s) => buf.write_string(s)
        @llm.StreamEvent::Error(msg) => failure.push(msg)
        _ => ()
      }
    },
  }
  self.provider.stream(messages, [], handler)
  match failure.length() > 0 {
    true => Err(
      "llm provider '\{self.provider.name()}' stream error: \{failure[0]}",
    )
    false => Ok(buf.to_string())
  }
}

pub impl @src.ConflictJudge for LlmConflictJudge with judge(
  self,
  new_fact,
  candidates
) {
  // 无候选：零调用，直接无裁决
  if candidates.length() == 0 {
    return Ok([])
  }
  let system_msg = @llm.Message::system(judge_system_prompt())
  let user_msg = @llm.Message::user(
    build_judge_user_prompt(
      new_fact.content,
      kind_to_label(new_fact.kind),
      candidates,
    ),
  )
  // ---- 第 1 次调用 ----
  let first : String = match self.request([system_msg, user_msg]) {
    Err(reason) => {
      // 网络/鉴权失败：不重试，返回 Err（store 降级为并存，原因可见）
      self.last_failure = Some(reason)
      return Err(@src.MoomemError::ExtractionFailure(
        "llm conflict judge failed: \{reason}",
      ))
    }
    Ok(resp) => resp
  }
  match parse_verdicts_response(first, candidates) {
    Ok(verdicts) => {
      self.last_failure = None
      return Ok(verdicts)
    }
    Err(parse_err) => {
      // ---- 非法 JSON：重试 1 次 ----
      let retry_messages : Array[@llm.Message] = [
        system_msg,
        user_msg,
        @llm.Message::assistant(first),
        @llm.Message::user(build_judge_retry_prompt(parse_err)),
      ]
      let second : String = match self.request(retry_messages) {
        Err(reason) => {
          self.last_failure = Some(reason)
          return Err(@src.MoomemError::ExtractionFailure(
            "llm conflict judge failed: \{reason}",
          ))
        }
        Ok(resp) => resp
      }
      match parse_verdicts_response(second, candidates) {
        Ok(verdicts) => {
          self.last_failure = None
          Ok(verdicts)
        }
        Err(err2) => {
          self.last_failure = Some(
            "invalid JSON from llm after 1 retry; first: \{parse_err}; retry: \{err2}",
          )
          Err(@src.MoomemError::ExtractionFailure(
            "llm conflict judge degraded (no verdicts): invalid JSON after 1 retry; first: \{parse_err}; retry: \{err2}",
          ))
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 裁决响应解析
// ---------------------------------------------------------------------------

/// 解析裁决响应。
/// 规则：
///   - 容忍 markdown 围栏与前后杂散文字（复用 parse_json_tolerant）；
///   - "verdicts" 缺失或不是数组 → 非法（触发重试）；
///   - id 未知 / decision 未知 → 丢弃该裁决（宁少勿错，等同无裁决）；
///   - 同一 id 重复裁决 → 取第一个；
///   - 全部裁决不可用但 verdicts 非空 → 非法（触发重试）；
///   - verdicts 为空数组 → 合法（全部 ignore，无裁决）。
fn parse_verdicts_response(
  response : String,
  candidates : Array[@src.MemoryEntry]
) -> Result[Array[@src.ConflictVerdict], String] {
  let j : Json = match parse_json_tolerant(response) {
    Ok(j) => j
    Err(e) => return Err(e)
  }
  let obj : Map[String, Json] = match j.as_object() {
    Some(o) => o
    None => return Err("response is not a JSON object")
  }
  let verdicts_json : Array[Json] = match obj.get("verdicts") {
    Some(v) =>
      match v.as_array() {
        Some(arr) => arr
        None => return Err("\"verdicts\" is not an array")
      }
    None => return Err("missing \"verdicts\" field")
  }
  if verdicts_json.length() == 0 {
    return Ok([])
  }
  // 候选 id → 条目索引（LLM 用 id 引用候选）
  let by_id : Map[String, @src.MemoryEntry] = Map([])
  for c in candidates {
    if !by_id.contains(c.id) {
      by_id.set(c.id, c)
    }
  }
  let seen : Map[String, Bool] = Map([])
  let verdicts : Array[@src.ConflictVerdict] = []
  let mut dropped = 0
  for vj in verdicts_json {
    let vo : Map[String, Json] = match vj.as_object() {
      Some(o) => o
      None => {
        dropped = dropped + 1
        continue
      }
    }
    let id : String = match vo.get("id") {
      Some(i) =>
        match i.as_string() {
          Some(s) => s
          None => {
            dropped = dropped + 1
            continue
          }
        }
      None => {
        dropped = dropped + 1
        continue
      }
    }
    let decision : @src.ConflictDecision = match vo.get("decision") {
      Some(d) =>
        match parse_decision(d) {
          Some(dec) => dec
          None => {
            dropped = dropped + 1
            continue
          }
        }
      None => {
        dropped = dropped + 1
        continue
      }
    }
    match by_id.get(id) {
      Some(existing) =>
        if !seen.contains(id) {
          seen.set(id, true)
          verdicts.push(
            @src.ConflictVerdict::{ existing, decision },
          )
        } else {
          dropped = dropped + 1 // 重复裁决丢弃
        }
      None => dropped = dropped + 1 // 未知 id 丢弃
    }
  }
  if verdicts.length() == 0 && dropped == verdicts_json.length() {
    return Err(
      "all \{verdicts_json.length()} verdict entries are unusable (bad id/decision)",
    )
  }
  Ok(verdicts)
}
