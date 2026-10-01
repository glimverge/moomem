// 每 user 物理分片的余弦近邻索引（暴力扫描 + 全量排序取 top-k）。
// 分片即隔离的结构保证（FR-04 / AC-02）：任何检索必须显式携带 user_id。

///|
/// 向量索引：user_id → (entry_id → 向量)。
/// Package-private (abstract): host API is MemoryStore only.
struct VectorIndex {
  shards : Map[String, Map[String, Array[Double]]]
}

///|
fn VectorIndex::new() -> VectorIndex {
  VectorIndex::{ shards: Map([]), }
}

///|
fn VectorIndex::shard(
  self : VectorIndex,
  user_id : String,
) -> Map[String, Array[Double]] {
  match self.shards.get(user_id) {
    Some(m) => m
    None => {
      let m : Map[String, Array[Double]] = Map([])
      self.shards.set(user_id, m)
      m
    }
  }
}

///|
/// 写入 / 覆盖某 user 的一条向量。
fn VectorIndex::upsert(
  self : VectorIndex,
  user_id : String,
  id : String,
  vec : Array[Double],
) -> Unit {
  self.shard(user_id).set(id, vec)
}

///|
/// 摘除某 user 的一条向量（supersede / forget 共用）。
fn VectorIndex::remove(
  self : VectorIndex,
  user_id : String,
  id : String,
) -> Unit {
  match self.shards.get(user_id) {
    Some(m) => m.remove(id)
    None => ()
  }
}

///|
/// 某 user 分片的条目数（wbtest 用；主路径不读 size）。
#warnings("-unused_value")
fn VectorIndex::size(self : VectorIndex, user_id : String) -> Int {
  match self.shards.get(user_id) {
    Some(m) => m.length()
    None => 0
  }
}

///|
/// 余弦近邻检索：仅在该 user 分片内暴力扫描，按相似度降序取前 k。
/// 零相似（正交 / 查询向量为空）不返回，保证"无结果返回空列表"。
/// 排序确定性：相似度降序，相同分按 id 升序。
fn VectorIndex::search(
  self : VectorIndex,
  user_id : String,
  qvec : Array[Double],
  k : Int,
) -> Array[(String, Double)] {
  if qvec.length() == 0 {
    return []
  }
  let scored : Array[(String, Double)] = []
  match self.shards.get(user_id) {
    Some(m) =>
      for kv in m.iter() {
        let score = cosine_similarity(qvec, kv.1)
        if score > 0.0 {
          scored.push((kv.0, score))
        }
      }
    None => ()
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
