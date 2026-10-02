// 精确去重：同 user + 内容指纹（归一化后哈希）。
// 完全重复的事实不重复入库，跳过并返回已存在条目 id。
// 归一化含主语前缀/尾标点折叠，吸收 LLM 提取常见的「我/用户」措辞漂移。

///|
/// 归一化内容（去首尾空白 + 小写 + 主语前缀/尾标点）的内容指纹（FNV-1a）。
/// Package-private; host path goes through MemoryStore::add dedup.
fn content_fingerprint(content : String) -> Int {
  fnv1a(normalize_content(content))
}

///|
/// 归一化：trim → lower → 剥常见主语前缀（LLM 提取常在「我/用户」间摇摆）→ 去尾标点。
/// 使「我的工号是 A1024」与「用户的工号是 A1024」落到同一指纹。
fn normalize_content(s : String) -> String {
  let lowered = s.trim().to_owned().to_lower()
  strip_trailing_punct(strip_subject_prefix(lowered))
}

///|
/// 剥句首主语前缀（长前缀优先）：用户的 / 用户 / 我的 / 我。
fn strip_subject_prefix(s : String) -> String {
  let prefixes = ["用户的", "用户", "我的", "我"]
  for p in prefixes {
    if s.has_prefix(p) {
      match s.strip_prefix(p) {
        Some(rest) => return rest.trim_start().to_owned()
        None => ()
      }
    }
  }
  s
}

///|
/// 去掉末尾常见中英文标点，避免「……A1024」与「……A1024。」指纹分叉。
fn strip_trailing_punct(s : String) -> String {
  fn is_punct(c : Char) -> Bool {
    c == '.' ||
    c == '!' ||
    c == '?' ||
    c == ',' ||
    c == ';' ||
    c == ':' ||
    c == '。' ||
    c == '！' ||
    c == '？' ||
    c == '，' ||
    c == '；' ||
    c == '：'
  }
  let chars : Array[Char] = []
  for c in s.iter() {
    chars.push(c)
  }
  while chars.length() > 0 && is_punct(chars[chars.length() - 1]) {
    chars.remove(chars.length() - 1) |> ignore
  }
  let buf = StringBuilder()
  for c in chars {
    buf.write_char(c)
  }
  buf.to_string()
}

///|
/// 按 user 分片的内容指纹索引：user → fingerprint → entry_id。
/// 只登记当前可检索（Active / Unstructured）的条目；
/// supersede / forget 时同步摘除。
/// Package-private (abstract): host API is MemoryStore only.
struct DedupIndex {
  by_user : Map[String, Map[Int, String]]
}

///|
fn DedupIndex::new() -> DedupIndex {
  DedupIndex::{ by_user: Map([]), }
}

///|
/// 查询同 user 是否已存在相同内容指纹的条目；返回已存在条目 id。
fn DedupIndex::lookup(
  self : DedupIndex,
  user_id : String,
  content : String,
) -> String? {
  match self.by_user.get(user_id) {
    Some(fp_map) => fp_map.get(content_fingerprint(content))
    None => None
  }
}

///|
/// 登记指纹 → entry_id。
fn DedupIndex::register(
  self : DedupIndex,
  user_id : String,
  content : String,
  id : String,
) -> Unit {
  let fp = content_fingerprint(content)
  let fp_map = match self.by_user.get(user_id) {
    Some(m) => m
    None => {
      let m : Map[Int, String] = Map([])
      self.by_user.set(user_id, m)
      m
    }
  }
  fp_map.set(fp, id)
}

///|
/// 摘除指纹（条目被 supersede / forget 时调用）。
fn DedupIndex::unregister(
  self : DedupIndex,
  user_id : String,
  content : String,
) -> Unit {
  match self.by_user.get(user_id) {
    Some(fp_map) => fp_map.remove(content_fingerprint(content))
    None => ()
  }
}
