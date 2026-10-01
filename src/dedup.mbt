// 精确去重：同 user + 内容指纹（归一化后哈希）。
// PRD 第 9 章：完全重复的事实不重复入库，跳过并返回已存在条目 id。

/// 归一化内容（去首尾空白 + 小写）的内容指纹（FNV-1a）。
pub fn content_fingerprint(content : String) -> Int {
  fnv1a(normalize_content(content))
}

fn normalize_content(s : String) -> String {
  s.trim().to_owned().to_lower()
}

/// 按 user 分片的内容指纹索引：user → fingerprint → entry_id。
/// 只登记当前可检索（Active / Unstructured）的条目；
/// supersede / forget 时同步摘除。
pub struct DedupIndex {
  by_user : Map[String, Map[Int, String]]
}

pub fn DedupIndex::new() -> DedupIndex {
  DedupIndex::{ by_user : Map([]) }
}

/// 查询同 user 是否已存在相同内容指纹的条目；返回已存在条目 id。
pub fn DedupIndex::lookup(
  self : DedupIndex,
  user_id : String,
  content : String
) -> String? {
  match self.by_user.get(user_id) {
    Some(fp_map) => fp_map.get(content_fingerprint(content))
    None => None
  }
}

/// 登记指纹 → entry_id。
pub fn DedupIndex::register(
  self : DedupIndex,
  user_id : String,
  content : String,
  id : String
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

/// 摘除指纹（条目被 supersede / forget 时调用）。
pub fn DedupIndex::unregister(
  self : DedupIndex,
  user_id : String,
  content : String
) -> Unit {
  match self.by_user.get(user_id) {
    Some(fp_map) => fp_map.remove(content_fingerprint(content))
    None => ()
  }
}
