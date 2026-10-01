// RRF 融合器（Reciprocal Rank Fusion）：将两路召回的 id 列表融合重排。
// score(id) = Σ_lists w / (k + rank)，rank 为该 id 在对应列表中的 1 基名次。

///|
/// 等权 RRF 融合：lists 为各路召回的 id 有序列表（已按相关性降序）；
/// k 为平滑常数（缺省 60），top_k 为截断长度。
/// 排序确定性：融合分降序，相同分按 id 升序。
/// Package-private; used by MemoryStore::recall only.
fn rrf(lists : Array[Array[String]], k : Int, top_k : Int) -> Array[String] {
  if k <= 0 {
    return []
  }
  let scores : Map[String, Double] = Map([])
  for list in lists {
    for i = 0; i < list.length(); i = i + 1 {
      let id = list[i]
      let rank = i + 1
      let contribution = 1.0 / (k.to_double() + rank.to_double())
      let cur = match scores.get(id) {
        Some(v) => v
        None => 0.0
      }
      scores.set(id, cur + contribution)
    }
  }
  rank_scores_to_ids(scores, top_k)
}

///|
/// 加权 RRF：score(id) = w_v/(k+rank_v) + w_b/(k+rank_b)；缺席通道贡献 0。
/// 排序确定性：融合分降序，相同分按 id 升序。
fn rrf_weighted(
  vec_ids : Array[String],
  kw_ids : Array[String],
  k : Int,
  top_k : Int,
  w_v : Double,
  w_b : Double,
) -> Array[String] {
  if k <= 0 {
    return []
  }
  let scores : Map[String, Double] = Map([])
  if w_v > 0.0 {
    for i = 0; i < vec_ids.length(); i = i + 1 {
      let id = vec_ids[i]
      let rank = i + 1
      let contribution = w_v / (k.to_double() + rank.to_double())
      let cur = match scores.get(id) {
        Some(v) => v
        None => 0.0
      }
      scores.set(id, cur + contribution)
    }
  }
  if w_b > 0.0 {
    for i = 0; i < kw_ids.length(); i = i + 1 {
      let id = kw_ids[i]
      let rank = i + 1
      let contribution = w_b / (k.to_double() + rank.to_double())
      let cur = match scores.get(id) {
        Some(v) => v
        None => 0.0
      }
      scores.set(id, cur + contribution)
    }
  }
  rank_scores_to_ids(scores, top_k)
}

///|
fn rank_scores_to_ids(scores : Map[String, Double], top_k : Int) -> Array[String] {
  let ranked : Array[(String, Double)] = []
  for kv in scores.iter() {
    ranked.push(kv)
  }
  ranked.sort_by((a, b) => {
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
  let out : Array[String] = []
  let limit = if top_k < ranked.length() { top_k } else { ranked.length() }
  for i = 0; i < limit; i = i + 1 {
    out.push(ranked[i].0)
  }
  out
}

///|
/// 词法强命中判定（仅用 BM25 分数尺度）。
/// bm25_scores 按相关性降序；空 → false。
/// lexical_strong ⇔ b1 >= floor 且（仅 1 命中 或 b1 >= b2 * gap）。
fn lexical_strong(
  bm25_scores : Array[Double],
  floor : Double,
  gap : Double,
) -> Bool {
  if bm25_scores.length() == 0 {
    return false
  }
  let b1 = bm25_scores[0]
  if b1 < floor {
    return false
  }
  if bm25_scores.length() == 1 {
    return true
  }
  let b2 = bm25_scores[1]
  b1 >= b2 * gap
}
