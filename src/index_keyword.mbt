// 每 user 物理分片的内置 BM25 关键词索引。
// 分词器：CJK 单字 + 相邻二元组；拉丁字母数字串按词（统一小写）。
// 与 HashingEmbedder 共用同一 tokenize，保证语义一致性。

///|
/// BM25 参数（经典默认值）；package-private.
const BM25_K1 : Double = 1.5

///|
const BM25_B : Double = 0.75

///|
/// 判断是否 CJK 表意字符（含扩展 A 区与兼容表意区）。
fn is_cjk_char(c : Char) -> Bool {
  let v = c.to_int()
  if v >= 0x3400 {
    if v <= 0x4DBF {
      return true // CJK 扩展 A
    }
    if v >= 0x4E00 {
      if v <= 0x9FFF {
        return true // CJK 基本区
      }
      if v >= 0xF900 && v <= 0xFAFF {
        return true // CJK 兼容表意区
      }
    }
  }
  false
}

///|
fn is_latin_word_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

///|
/// 分词器：CJK 逐字出单字 token，相邻 CJK 字额外出二元组 token；
/// 拉丁字母数字连续串出一个词 token（小写化）；其余字符为分隔符。
/// 确定性、无外部依赖，三后端一致；被 BM25 索引与 HashingEmbedder 共用。
fn tokenize(text : String) -> Array[String] {
  let tokens : Array[String] = []
  let buf = StringBuilder()
  let mut prev_cjk : Char? = None
  for c in text.iter() {
    if is_cjk_char(c) {
      flush_word(buf, tokens)
      tokens.push("\{c}")
      match prev_cjk {
        Some(p) => tokens.push("\{p}\{c}")
        None => ()
      }
      prev_cjk = Some(c)
    } else if is_latin_word_char(c) {
      buf.write_char(c)
      prev_cjk = None
    } else {
      flush_word(buf, tokens)
      prev_cjk = None
    }
  }
  flush_word(buf, tokens)
  tokens
}

///|
fn flush_word(buf : StringBuilder, tokens : Array[String]) -> Unit {
  if buf.is_empty() == false {
    tokens.push(buf.to_string().to_lower())
    buf.reset()
  }
}

// ---------------------------------------------------------------------------
// BM25 分片索引
// ---------------------------------------------------------------------------

///|
priv struct Bm25Doc {
  tf : Map[String, Int]
  len : Int
}

///|
/// BM25 索引：按 user 物理分片，维护每 user 的 df 与总词长。
/// Package-private (abstract): host API is MemoryStore only.
struct KeywordIndex {
  // user → (entry_id → doc)
  shards : Map[String, Map[String, Bm25Doc]]
  // user → (term → 文档频率 df)
  df : Map[String, Map[String, Int]]
  // user → 分片总词长（所有 doc len 之和）
  total_len : Map[String, Int]
}

///|
fn KeywordIndex::new() -> KeywordIndex {
  KeywordIndex::{ shards: Map([]), df: Map([]), total_len: Map([]), }
}

///|
fn KeywordIndex::shard(
  self : KeywordIndex,
  user_id : String,
) -> Map[String, Bm25Doc] {
  match self.shards.get(user_id) {
    Some(m) => m
    None => {
      let m : Map[String, Bm25Doc] = Map([])
      self.shards.set(user_id, m)
      m
    }
  }
}

///|
fn KeywordIndex::df_shard(
  self : KeywordIndex,
  user_id : String,
) -> Map[String, Int] {
  match self.df.get(user_id) {
    Some(m) => m
    None => {
      let m : Map[String, Int] = Map([])
      self.df.set(user_id, m)
      m
    }
  }
}

///|
fn KeywordIndex::add_total_len(
  self : KeywordIndex,
  user_id : String,
  delta : Int,
) -> Unit {
  let cur = match self.total_len.get(user_id) {
    Some(v) => v
    None => 0
  }
  self.total_len.set(user_id, cur + delta)
}

///|
/// 写入 / 覆盖某 user 的一条文档（keywords 为 tokenize 结果）。
/// 覆盖时先按旧文档回滚 df 与总词长，保证统计正确。
fn KeywordIndex::upsert(
  self : KeywordIndex,
  user_id : String,
  id : String,
  keywords : Array[String],
) -> Unit {
  let shard = self.shard(user_id)
  // 回滚旧文档统计
  match shard.get(id) {
    Some(old) => {
      let df_map = self.df_shard(user_id)
      for term in old.tf.keys() {
        match df_map.get(term) {
          Some(n) =>
            if n <= 1 {
              df_map.remove(term)
            } else {
              df_map.set(term, n - 1)
            }
          None => ()
        }
      }
      self.add_total_len(user_id, -old.len)
    }
    None => ()
  }
  // 建新文档
  let tf : Map[String, Int] = Map([])
  for t in keywords {
    let cur = match tf.get(t) {
      Some(n) => n
      None => 0
    }
    tf.set(t, cur + 1)
  }
  shard.set(id, Bm25Doc::{ tf, len: keywords.length(), })
  self.add_total_len(user_id, keywords.length())
  // 更新 df（按去重词表）
  let df_map = self.df_shard(user_id)
  for term in tf.keys() {
    let cur = match df_map.get(term) {
      Some(n) => n
      None => 0
    }
    df_map.set(term, cur + 1)
  }
}

///|
/// 摘除某 user 的一条文档（supersede / forget 共用）。
fn KeywordIndex::remove(
  self : KeywordIndex,
  user_id : String,
  id : String,
) -> Unit {
  match self.shards.get(user_id) {
    Some(shard) =>
      match shard.get(id) {
        Some(doc) => {
          let df_map = self.df_shard(user_id)
          for term in doc.tf.keys() {
            match df_map.get(term) {
              Some(n) =>
                if n <= 1 {
                  df_map.remove(term)
                } else {
                  df_map.set(term, n - 1)
                }
              None => ()
            }
          }
          self.add_total_len(user_id, -doc.len)
          shard.remove(id)
        }
        None => ()
      }
    None => ()
  }
}

///|
/// 某 user 分片的条目数（wbtest 用；主路径不读 size）。
#warnings("-unused_value")
fn KeywordIndex::size(self : KeywordIndex, user_id : String) -> Int {
  match self.shards.get(user_id) {
    Some(m) => m.length()
    None => 0
  }
}

///|
/// BM25 检索：仅在该 user 分片内打分，按分数降序取前 k。
/// 排序确定性：分数降序，相同分按 id 升序。
fn KeywordIndex::search(
  self : KeywordIndex,
  user_id : String,
  query : String,
  k : Int,
) -> Array[(String, Double)] {
  let query_terms = tokenize(query)
  if query_terms.length() == 0 {
    return []
  }
  let shard = match self.shards.get(user_id) {
    Some(m) => m
    None => return []
  }
  let n_docs = shard.length()
  if n_docs == 0 {
    return []
  }
  let total_len = match self.total_len.get(user_id) {
    Some(v) => v
    None => 0
  }
  let avgdl = total_len.to_double() / n_docs.to_double()
  if avgdl <= 0.0 {
    return []
  }
  let df_map = self.df_shard(user_id)
  let scored : Array[(String, Double)] = []
  for kv in shard.iter() {
    let id = kv.0
    let doc = kv.1
    let mut score = 0.0
    for term in query_terms {
      let tf = match doc.tf.get(term) {
        Some(v) => v
        None => 0
      }
      if tf == 0 {
        continue
      }
      let df = match df_map.get(term) {
        Some(v) => v
        None => 0
      }
      let idf = @math.ln(
        1.0 + ((n_docs - df).to_double() + 0.5) / (df.to_double() + 0.5),
      )
      let tf_d = tf.to_double()
      let norm = BM25_K1 * (1.0 - BM25_B + BM25_B * doc.len.to_double() / avgdl)
      score = score + idf * tf_d * (BM25_K1 + 1.0) / (tf_d + norm)
    }
    if score > 0.0 {
      scored.push((id, score))
    }
  }
  scored.sort_by((a, b) => {
    if a.1 > b.1 {
      -1
    } else if a.1 < b.1 {
      1
    } else if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  let out : Array[(String, Double)] = []
  let limit = if k < scored.length() { k } else { scored.length() }
  for i = 0; i < limit; i = i + 1 {
    out.push(scored[i])
  }
  out
}
