// 提取 prompt 与响应解析（PRD 13.1 提取契约的落地）。
//
// 契约要点：
//   - 输出结构化事实：content + kind(fact/preference/event) + 原文依据 span；
//   - 只保留可复用信息，丢弃寒暄（facts 为空数组 = 纯闲聊）；
//   - 忠实原文，不改写、不推断；
//   - 歧义按"宁少勿错"丢弃。

// ---------------------------------------------------------------------------
// Prompt 构造
// ---------------------------------------------------------------------------

///|
/// 提取器系统提示词：约定输出格式与提取纪律。
fn extraction_system_prompt() -> String {
  let buf = StringBuilder()
  buf.write_string("你是 Agent 长期记忆系统的事实提取器。")
  buf.write_char('\n')
  buf.write_string(
    "从用户对话文本中提取值得长期记住的结构化事实。\n",
  )
  buf.write_char('\n')
  buf.write_string("提取纪律：\n")
  buf.write_string(
    "1. 只保留可复用信息：用户的稳定事实(kind=fact)、偏好(kind=preference)、发生过的事件(kind=event)。\n",
  )
  buf.write_string(
    "2. 丢弃寒暄、问候、临时性内容；没有可保留信息时返回 {\"facts\":[]}。\n",
  )
  buf.write_string(
    "3. 忠实原文：content 使用原文语言，不改写、不推断、不补充原文没有的信息。\n",
  )
  buf.write_string(
    "4. 歧义或无法确认的内容宁可丢弃（宁少勿错）。\n",
  )
  buf.write_string(
    "5. kind 只能是 \"fact\"、\"preference\"、\"event\" 三者之一。\n",
  )
  buf.write_string(
    "6. span 填写该事实在原文中的依据片段（原文子串）；无法确定时填空字符串。\n",
  )
  buf.write_char('\n')
  buf.write_string(
    "只输出一个 JSON 对象，不要输出 markdown 代码块或任何其他文字：\n",
  )
  buf.write_string(
    "{\"facts\":[{\"content\":\"...\",\"kind\":\"fact\",\"span\":\"...\"}]}",
  )
  buf.to_string()
}

///|
/// 提取器用户提示词：携带待提取的对话文本。
fn build_extraction_user_prompt(text : String) -> String {
  let buf = StringBuilder()
  buf.write_string("请从下面的对话文本中提取事实。\n")
  buf.write_string("对话文本：\n")
  buf.write_string("\"\"\"\n")
  buf.write_string(text)
  buf.write_string("\n\"\"\"")
  buf.to_string()
}

///|
/// 非法 JSON 后的重试提示词：携带上次输出与失败原因，要求严格 JSON。
fn build_retry_prompt(reason : String) -> String {
  let buf = StringBuilder()
  buf.write_string(
    "你上一次的输出不是合法的提取结果（\{reason}）。\n",
  )
  buf.write_string(
    "请重新输出：只输出一个 JSON 对象 {\"facts\":[...]}，",
  )
  buf.write_string(
    "不要包含 markdown 代码块、注释或任何其他文字。",
  )
  buf.to_string()
}

// ---------------------------------------------------------------------------
// 冲突判定 prompt（LlmConflictJudge 使用）
// ---------------------------------------------------------------------------

///|
/// 冲突判定系统提示词：约定 moomem 的三种裁决语义。
fn judge_system_prompt() -> String {
  let buf = StringBuilder()
  buf.write_string("你是 Agent 长期记忆系统的冲突判定器。\n")
  buf.write_string(
    "给定一条新事实与若干既有记忆条目，判断二者的语义关系：\n",
  )
  buf.write_string(
    "- replace：新事实与该条目矛盾，或是对同一主题的更新（旧值已过时）；\n",
  )
  buf.write_string(
    "- coexist：二者相关但都仍然有效（如同一主题的不同侧面）；\n",
  )
  buf.write_string("- ignore：二者无关。\n")
  buf.write_char('\n')
  buf.write_string(
    "判定纪律：宁少勿错——拿不准是否矛盾时选 coexist 或 ignore，不要误删仍有效的记忆。\n",
  )
  buf.write_char('\n')
  buf.write_string(
    "只输出一个 JSON 对象，不要输出 markdown 代码块或任何其他文字：\n",
  )
  buf.write_string(
    "{\"verdicts\":[{\"id\":\"<条目id>\",\"decision\":\"replace\",\"reason\":\"...\"}]}",
  )
  buf.to_string()
}

///|
/// 冲突判定用户提示词：携带新事实与候选条目（id + 内容 + 类型）。
/// 单条内容截断到 200 字符，防止超长记忆撑爆上下文。
fn build_judge_user_prompt(
  new_content : String,
  new_kind : String,
  candidates : Array[@src.MemoryEntry],
) -> String {
  let buf = StringBuilder()
  buf.write_string("新事实：\n")
  buf.write_string("- content: \{truncate_for_prompt(new_content, 200)}\n")
  buf.write_string("- kind: \{new_kind}\n")
  buf.write_char('\n')
  buf.write_string("既有记忆条目：\n")
  for c in candidates {
    buf.write_string("- id: \{c.id}\n")
    buf.write_string("  content: \{truncate_for_prompt(c.content, 200)}\n")
    buf.write_string("  kind: \{kind_to_label(c.kind)}\n")
  }
  buf.write_char('\n')
  buf.write_string("请对每个既有条目输出裁决。")
  buf.to_string()
}

///|
/// 非法 JSON 后的重试提示词（冲突判定版）。
fn build_judge_retry_prompt(reason : String) -> String {
  let buf = StringBuilder()
  buf.write_string(
    "你上一次的输出不是合法的裁决结果（\{reason}）。\n",
  )
  buf.write_string(
    "请重新输出：只输出一个 JSON 对象 {\"verdicts\":[...]}，",
  )
  buf.write_string(
    "不要包含 markdown 代码块、注释或任何其他文字。",
  )
  buf.to_string()
}

///|
fn kind_to_label(k : @src.EntryKind) -> String {
  match k {
    @src.EntryKind::Fact => "fact"
    @src.EntryKind::Preference => "preference"
    @src.EntryKind::Event => "event"
    @src.EntryKind::Unstructured => "unstructured"
  }
}

///|
/// 超长内容截断（prompt 体积保护）。
fn truncate_for_prompt(s : String, limit : Int) -> String {
  if s.length() <= limit {
    s
  } else {
    s.view(end_offset=limit).to_owned() + "…"
  }
}

// ---------------------------------------------------------------------------
// 提取响应解析
// ---------------------------------------------------------------------------

///|
/// 解析提取响应。
/// 返回 Ok(facts) 或 Err(可读原因)。规则：
///   - 容忍 markdown 代码块围栏与前后杂散文字（截取首个 '{' 到最后一个 '}'）；
///   - "facts" 缺失或不是数组 → 非法（触发重试）；
///   - 单条 entry 的 content 为空/非字符串、kind 未知 → 丢弃该条（宁少勿错）；
///   - facts 非空但全部 entry 不可用 → 非法（触发重试，避免"格式垃圾被当成闲聊"）；
///   - facts 为空数组 → 合法（纯闲聊，不入库）。
fn parse_extraction_response(
  response : String,
  max_facts : Int,
) -> Result[Array[@src.ExtractedFact], String] {
  let j : Json = match parse_json_tolerant(response) {
    Ok(j) => j
    Err(e) => return Err(e)
  }
  let obj : Map[String, Json] = match j {
    Object(o) => o
    _ => return Err("response is not a JSON object")
  }
  let facts_json : Array[Json] = match obj.get("facts") {
    Some(Array(arr)) => arr
    Some(_) => return Err("\"facts\" is not an array")
    None => return Err("missing \"facts\" field")
  }
  if facts_json.length() == 0 {
    // 纯闲聊：合法的空结果
    return Ok([])
  }
  let facts : Array[@src.ExtractedFact] = []
  for fj in facts_json {
    if facts.length() >= max_facts {
      break // 宁少勿错：超预算的事实直接截断
    }
    match parse_one_fact(fj) {
      Some(f) => facts.push(f)
      None => () // 单条不可用 → 丢弃（宁少勿错）
    }
  }
  if facts.length() == 0 {
    return Err(
      "all \{facts_json.length()} fact entries are unusable (bad content/kind)",
    )
  }
  Ok(facts)
}

///|
/// 解析单条事实 entry；不可用返回 None。
fn parse_one_fact(fj : Json) -> @src.ExtractedFact? {
  let obj : Map[String, Json] = match fj {
    Object(o) => o
    _ => return None
  }
  let content : String = match obj.get("content") {
    Some(String(s)) => s
    _ => return None
  }
  if content.trim().length() == 0 {
    return None
  }
  let kind : @src.EntryKind = match obj.get("kind") {
    Some(String("fact")) => @src.EntryKind::Fact
    Some(String("preference")) => @src.EntryKind::Preference
    Some(String("event")) => @src.EntryKind::Event
    Some(_) => return None // 未知 kind → 丢弃（宁少勿错）
    None => return None
  }
  let span : String? = match obj.get("span") {
    Some(String(v)) => if v.trim().length() == 0 { None } else { Some(v) }
    _ => None
  }
  Some(
    @src.ExtractedFact::{
      content,
      kind,
      source_span: span,
      degraded: false,
      degrade_reason: None,
    },
  )
}

// ---------------------------------------------------------------------------
// 冲突裁决响应解析
// ---------------------------------------------------------------------------

///|
/// 解析裁决响应中单条 entry 的 decision；未知值返回 None（宁少勿错 → 视为无裁决）。
fn parse_decision(j : Json) -> @src.ConflictDecision? {
  match j {
    String("replace") => Some(@src.ConflictDecision::Replace)
    String("coexist") => Some(@src.ConflictDecision::Coexist)
    String("ignore") => Some(@src.ConflictDecision::Ignore)
    _ => None
  }
}

// ---------------------------------------------------------------------------
// JSON 容错解析辅助
// ---------------------------------------------------------------------------

///|
/// 容错 JSON 解析：先剥 markdown 代码围栏，再整体解析；
/// 整体失败时截取首个 '{' 到最后一个 '}' 之间的子串再试一次
/// （容忍 LLM 在 JSON 前后夹带说明文字的常见行为）。
fn parse_json_tolerant(text : String) -> Result[Json, String] {
  let stripped = strip_code_fence(text.trim().to_owned())
  match try_parse_json(stripped) {
    Ok(j) => Ok(j)
    Err(_) => {
      let begin = stripped.find("{")
      let end = stripped.rev_find("}")
      match (begin, end) {
        (Some(b), Some(e)) =>
          if e > b {
            try_parse_json(
              stripped.view(start_offset=b, end_offset=e + 1).to_owned(),
            )
          } else {
            Err("response is not valid JSON")
          }
        _ => Err("response contains no JSON object")
      }
    }
  }
}

///|
/// 剥掉 ``` / ```json 代码围栏：去掉首行围栏与结尾围栏行。
fn strip_code_fence(text : String) -> String {
  if !text.has_prefix("```") {
    return text
  }
  let lines : Array[String] = []
  for raw in text.split("\n") {
    lines.push(raw.to_owned())
  }
  // 去掉结尾空行与围栏行
  while lines.length() > 0 && lines[lines.length() - 1].trim().length() == 0 {
    ignore(lines.pop())
  }
  if lines.length() > 0 && lines[lines.length() - 1].trim() == "```" {
    ignore(lines.pop())
  }
  // 重新拼接（跳过首行围栏）
  let buf = StringBuilder()
  for i = 1; i < lines.length(); i = i + 1 {
    buf.write_string(lines[i])
    buf.write_char('\n')
  }
  buf.to_string().trim().to_owned()
}

///|
/// try 风格 JSON 解析包装。
fn try_parse_json(s : String) -> Result[Json, String] {
  let parsed : Json = @json.parse(s) catch {
    e => return Err("invalid JSON: \{e.to_string()}")
  }
  Ok(parsed)
}
