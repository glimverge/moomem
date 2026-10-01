// moomem 唯一的 JSON 编解码处（共享约定 7.2）。
// 使用 core/json；JSONL 一行一条 entry；快照首行为 header。
//
// 快照格式：
//   {"v":1,"gen":<递增代数>,"clock":<逻辑时钟>}
//   {entry JSON}
//   {entry JSON}
//   ...
//
// 内部函数采用 raise 风格传播错误，公开函数统一返回 Result[T, MoomemError]。

// ---------------------------------------------------------------------------
// MemoryEntry 编解码
// ---------------------------------------------------------------------------

/// MemoryEntry → Json（字段名与磁盘格式一一对应，恢复时不必重算 keywords）。
pub fn entry_to_json(e : MemoryEntry) -> Json {
  let obj : Map[String, Json] = Map([])
  obj.set("id", Json::string(e.id))
  obj.set("user_id", Json::string(e.user_id))
  obj.set("content", Json::string(e.content))
  obj.set("kind", kind_to_json(e.kind))
  obj.set("embedding", Json::array(e.embedding.map(v => Json::number(v))))
  obj.set("keywords", Json::array(e.keywords.map(k => Json::string(k))))
  obj.set("status", status_to_json(e.status))
  obj.set("created_at", Json::number(Int64::to_double(e.created_at)))
  obj.set(
    "superseded_by",
    match e.superseded_by {
      Some(id) => Json::string(id)
      None => Json::null()
    },
  )
  obj.set("seq", Json::number(e.seq.to_double()))
  obj.set("metadata", Json::object(e.metadata))
  Json::object(obj)
}

/// Json → MemoryEntry；字段缺失 / 类型不符 → StoreCorrupted。
pub fn entry_from_json(j : Json) -> Result[MemoryEntry, MoomemError] {
  try {
    Ok(entry_from_json_impl(j))
  } catch {
    e => Err(e)
  }
}

fn entry_from_json_impl(j : Json) -> MemoryEntry raise MoomemError {
  let obj = match j.as_object() {
    Some(o) => o
    None => raise MoomemError::StoreCorrupted("entry is not a JSON object")
  }
  let id = get_string_field(obj, "id")
  let user_id = get_string_field(obj, "user_id")
  let content = get_string_field(obj, "content")
  let kind = match obj.get("kind") {
    Some(k) => kind_from_json(k)
    None => raise MoomemError::StoreCorrupted("entry missing field 'kind'")
  }
  let embedding = get_double_array_field(obj, "embedding")
  let keywords = get_string_array_field(obj, "keywords")
  let status = match obj.get("status") {
    Some(s) => status_from_json(s)
    None => raise MoomemError::StoreCorrupted("entry missing field 'status'")
  }
  let created_at = get_int64_field(obj, "created_at")
  let superseded_by = match obj.get("superseded_by") {
    Some(j) =>
      match j.as_string() {
        Some(s) => Some(s)
        None => {
          if j.as_null() != None {
            None
          } else {
            raise MoomemError::StoreCorrupted(
              "field 'superseded_by' is not a string or null",
            )
          }
        }
      }
    None => None
  }
  let seq = get_int_field(obj, "seq")
  let metadata : Map[String, Json] = Map([])
  match obj.get("metadata") {
    Some(j) =>
      match j.as_object() {
        Some(m) => m.each((k, v) => metadata.set(k, v))
        None =>
          if j.as_null() == None {
            raise MoomemError::StoreCorrupted("field 'metadata' is not an object")
          }
      }
    None => ()
  }
  MemoryEntry::{
    id,
    user_id,
    content,
    kind,
    embedding,
    keywords,
    status,
    created_at,
    superseded_by,
    seq,
    metadata,
  }
}

// ---------------------------------------------------------------------------
// 状态与类型的字符串编解码
// ---------------------------------------------------------------------------

fn status_to_json(s : EntryStatus) -> Json {
  match s {
    Active => Json::string("active")
    Superseded => Json::string("superseded")
    Deleted => Json::string("deleted")
    Unstructured => Json::string("unstructured")
  }
}

fn status_from_json(j : Json) -> EntryStatus raise MoomemError {
  match j.as_string() {
    Some("active") => Active
    Some("superseded") => Superseded
    Some("deleted") => Deleted
    Some("unstructured") => Unstructured
    Some(other) =>
      raise MoomemError::StoreCorrupted("unknown status '\{other}'")
    None => raise MoomemError::StoreCorrupted("status is not a string")
  }
}

fn kind_to_json(k : EntryKind) -> Json {
  match k {
    Fact => Json::string("fact")
    Preference => Json::string("preference")
    Event => Json::string("event")
    Unstructured => Json::string("unstructured")
  }
}

fn kind_from_json(j : Json) -> EntryKind raise MoomemError {
  match j.as_string() {
    Some("fact") => Fact
    Some("preference") => Preference
    Some("event") => Event
    Some("unstructured") => Unstructured
    Some(other) => raise MoomemError::StoreCorrupted("unknown kind '\{other}'")
    None => raise MoomemError::StoreCorrupted("kind is not a string")
  }
}

// ---------------------------------------------------------------------------
// 字段读取辅助（类型不符一律 raise StoreCorrupted）
// ---------------------------------------------------------------------------

fn get_string_field(obj : Map[String, Json], key : String) -> String raise MoomemError {
  match obj.get(key) {
    Some(j) =>
      match j.as_string() {
        Some(s) => s
        None => raise MoomemError::StoreCorrupted("field '\{key}' is not a string")
      }
    None => raise MoomemError::StoreCorrupted("field '\{key}' is missing")
  }
}

fn get_int_field(obj : Map[String, Json], key : String) -> Int raise MoomemError {
  match obj.get(key) {
    Some(j) =>
      match j.as_number() {
        Some(n) => n.to_int()
        None => raise MoomemError::StoreCorrupted("field '\{key}' is not a number")
      }
    None => raise MoomemError::StoreCorrupted("field '\{key}' is missing")
  }
}

fn get_int64_field(obj : Map[String, Json], key : String) -> Int64 raise MoomemError {
  match obj.get(key) {
    Some(j) =>
      match j.as_number() {
        Some(n) => n.to_int64()
        None => raise MoomemError::StoreCorrupted("field '\{key}' is not a number")
      }
    None => raise MoomemError::StoreCorrupted("field '\{key}' is missing")
  }
}

fn get_double_array_field(
  obj : Map[String, Json],
  key : String
) -> Array[Double] raise MoomemError {
  match obj.get(key) {
    Some(j) =>
      match j.as_array() {
        Some(items) => {
          let out : Array[Double] = []
          for item in items {
            match item.as_number() {
              Some(n) => out.push(n)
              None =>
                raise MoomemError::StoreCorrupted(
                  "field '\{key}' contains non-number item",
                )
            }
          }
          out
        }
        None => raise MoomemError::StoreCorrupted("field '\{key}' is not an array")
      }
    None => raise MoomemError::StoreCorrupted("field '\{key}' is missing")
  }
}

fn get_string_array_field(
  obj : Map[String, Json],
  key : String
) -> Array[String] raise MoomemError {
  match obj.get(key) {
    Some(j) =>
      match j.as_array() {
        Some(items) => {
          let out : Array[String] = []
          for item in items {
            match item.as_string() {
              Some(s) => out.push(s)
              None =>
                raise MoomemError::StoreCorrupted(
                  "field '\{key}' contains non-string item",
                )
            }
          }
          out
        }
        None => raise MoomemError::StoreCorrupted("field '\{key}' is not an array")
      }
    None => raise MoomemError::StoreCorrupted("field '\{key}' is missing")
  }
}

// ---------------------------------------------------------------------------
// 快照 header / 整体编解码
// ---------------------------------------------------------------------------

/// 快照 header：{"v":1,"gen":..,"clock":..}
fn snapshot_header_to_json(v : Int, gen : Int, clock : Int64) -> Json {
  let obj : Map[String, Json] = Map([])
  obj.set("v", Json::number(v.to_double()))
  obj.set("gen", Json::number(gen.to_double()))
  obj.set("clock", Json::number(Int64::to_double(clock)))
  Json::object(obj)
}

/// 解析 header 行；校验版本号。返回 (v, gen, clock)。
pub fn parse_snapshot_header(j : Json) -> Result[(Int, Int, Int64), MoomemError] {
  try {
    let obj = match j.as_object() {
      Some(o) => o
      None =>
        raise MoomemError::StoreCorrupted("snapshot header is not a JSON object")
    }
    let v = get_int_field(obj, "v")
    if v != SNAPSHOT_VERSION {
      raise MoomemError::StoreCorrupted(
        "snapshot version mismatch: expected \{SNAPSHOT_VERSION}, got \{v}",
      )
    }
    let gen = get_int_field(obj, "gen")
    let clock = get_int64_field(obj, "clock")
    Ok((v, gen, clock))
  } catch {
    e => Err(e)
  }
}

/// 解析单行 JSON（空行 / 语法错误 → StoreCorrupted）。
pub fn parse_json_line(line : String) -> Result[Json, MoomemError] {
  try {
    let trimmed = line.trim()
    if trimmed.length() == 0 {
      raise MoomemError::StoreCorrupted("blank line in snapshot")
    }
    Ok(@json.parse(trimmed))
  } catch {
    e => Err(MoomemError::StoreCorrupted("invalid JSON line: \{e.to_string()}"))
  }
}

/// 组装完整快照文本：header 行 + 每条 entry 一行 JSON。
pub fn build_snapshot_text(
  gen : Int,
  clock : Int64,
  entries : Array[MemoryEntry]
) -> String {
  let buf = StringBuilder()
  buf.write_string(
    snapshot_header_to_json(SNAPSHOT_VERSION, gen, clock).stringify(),
  )
  buf.write_char('\n')
  for e in entries {
    buf.write_string(entry_to_json(e).stringify())
    buf.write_char('\n')
  }
  buf.to_string()
}

/// 快照解析结果：header 代数与时钟 + 条目列表（按文件序） + 截断计数。
pub struct SnapshotParseResult {
  gen : Int
  clock : Int64
  entries : Array[MemoryEntry]
  truncated_recovered : Int
}

/// 解析快照文本。
/// 规则（架构文档 1.4 / PRD 第 15 章）：
///   - 首行必须是合法 header 且版本匹配，否则 StoreCorrupted；
///   - 尾部不完整行（半行损坏）丢弃并计入 truncated_recovered；
///   - 中部损坏行不属于尾部截断，报 StoreCorrupted。
pub fn parse_snapshot_text(text : String) -> Result[SnapshotParseResult, MoomemError] {
  try {
    Ok(parse_snapshot_text_impl(text))
  } catch {
    e => Err(e)
  }
}

fn parse_snapshot_text_impl(
  text : String
) -> SnapshotParseResult raise MoomemError {
  // 收集行并剥掉尾部空行
  let lines : Array[String] = []
  for raw in text.split("\n") {
    lines.push(raw.to_owned())
  }
  while lines.length() > 0 && lines[lines.length() - 1].trim().length() == 0 {
    ignore(lines.pop())
  }
  if lines.length() == 0 {
    raise MoomemError::StoreCorrupted("empty snapshot")
  }
  let header_json = parse_json_line_impl(lines[0])
  let obj = match header_json.as_object() {
    Some(o) => o
    None => raise MoomemError::StoreCorrupted("snapshot header is not a JSON object")
  }
  let v = get_int_field(obj, "v")
  if v != SNAPSHOT_VERSION {
    raise MoomemError::StoreCorrupted(
      "snapshot version mismatch: expected \{SNAPSHOT_VERSION}, got \{v}",
    )
  }
  let gen = get_int_field(obj, "gen")
  let clock = get_int64_field(obj, "clock")
  let entries : Array[MemoryEntry] = []
  let mut truncated = 0
  for i = 1; i < lines.length(); i = i + 1 {
    let line = lines[i]
    if line.trim().length() == 0 {
      raise MoomemError::StoreCorrupted(
        "blank entry line at \{i + 1} (not a tail truncation)",
      )
    }
    let parsed_ok : Bool = try {
      let j = parse_json_line_impl(line)
      let entry = entry_from_json_impl(j)
      entries.push(entry)
      true
    } catch {
      _ => false
    }
    if !parsed_ok {
      if i == lines.length() - 1 {
        // 尾部半行损坏：丢弃并计数
        truncated = truncated + 1
      } else {
        raise MoomemError::StoreCorrupted(
          "corrupted entry at line \{i + 1} (not a tail truncation)",
        )
      }
    }
  }
  SnapshotParseResult::{ gen, clock, entries, truncated_recovered : truncated }
}

fn parse_json_line_impl(line : String) -> Json raise MoomemError {
  let trimmed = line.trim().to_owned()
  if trimmed.length() == 0 {
    raise MoomemError::StoreCorrupted("blank line in snapshot")
  }
  try {
    @json.parse(trimmed)
  } catch {
    e => raise MoomemError::StoreCorrupted("invalid JSON line: \{e.to_string()}")
  }
}
