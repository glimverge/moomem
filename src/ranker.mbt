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
/// 加权 RRF：score(id) = vector_weight/(k+vector_rank) + keyword_weight/(k+keyword_rank)；缺席通道贡献 0。
/// 排序确定性：融合分降序，相同分按 id 升序。
fn rrf_weighted(
  vector_ids : Array[String],
  keyword_ids : Array[String],
  k : Int,
  top_k : Int,
  vector_weight : Double,
  keyword_weight : Double,
) -> Array[String] {
  if k <= 0 {
    return []
  }
  let scores : Map[String, Double] = Map([])
  if vector_weight > 0.0 {
    for i = 0; i < vector_ids.length(); i = i + 1 {
      let id = vector_ids[i]
      let rank = i + 1
      let contribution = vector_weight / (k.to_double() + rank.to_double())
      let cur = match scores.get(id) {
        Some(v) => v
        None => 0.0
      }
      scores.set(id, cur + contribution)
    }
  }
  if keyword_weight > 0.0 {
    for i = 0; i < keyword_ids.length(); i = i + 1 {
      let id = keyword_ids[i]
      let rank = i + 1
      let contribution = keyword_weight / (k.to_double() + rank.to_double())
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

///|
/// 保护 BM25 top-k 成员：加权 RRF 结果若丢掉词法 top，则从尾部挤出非保护项换入。
/// 保证 adaptive 路径 Recall@5 不低于同库 BM25 单路（不改变计分子集）。
fn protect_bm25_topk(
  fused : Array[String],
  keyword_ids : Array[String],
  k : Int,
) -> Array[String] {
  let out : Array[String] = []
  let in_out : Map[String, Bool] = Map([])
  let limit = if k < fused.length() { k } else { fused.length() }
  for i = 0; i < limit; i = i + 1 {
    out.push(fused[i])
    in_out.set(fused[i], true)
  }
  let protect_n = if k < keyword_ids.length() { k } else { keyword_ids.length() }
  let keep_set : Map[String, Bool] = Map([])
  for i = 0; i < protect_n; i = i + 1 {
    keep_set.set(keyword_ids[i], true)
  }
  for i = 0; i < protect_n; i = i + 1 {
    let id = keyword_ids[i]
    if in_out.contains(id) {
      continue
    }
    // 找可替换的尾部位：非 BM25 保护集成员
    let mut replaced = false
    let mut j = out.length() - 1
    while j >= 0 {
      if !keep_set.contains(out[j]) {
        in_out.remove(out[j])
        out[j] = id
        in_out.set(id, true)
        replaced = true
        break
      }
      j = j - 1
    }
    if !replaced {
      // 结果全是保护成员且未满，或无法腾位：追加（截断到 k）
      if out.length() < k {
        out.push(id)
        in_out.set(id, true)
      }
    }
  }
  // 若仍未满（BM25 不足 k），保持 fused 已填部分
  out
}
