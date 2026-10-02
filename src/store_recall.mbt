// MemoryStore::recall。仍是同一个聚合根上的方法。

// ---------------------------------------------------------------------------
// recall：向量与关键词融合
// ---------------------------------------------------------------------------

///|
/// 混合检索：向量 + BM25 双路 → RRF 融合 → 只返回 Active/Unstructured。
/// 嵌入失败时仅 BM25 单路。无结果返回空列表（不编造）。
pub fn MemoryStore::recall(
  self : MemoryStore,
  user_id : String,
  query : String,
  top_k? : Int,
) -> Result[Array[MemoryEntry], MoomemError] {
  if self.closed {
    return Err(MoomemError::InvalidOperation("store is closed"))
  }
  match validate_user_id(user_id) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let k = match top_k {
    Some(v) =>
      if v < 1 {
        DEFAULT_RECALL_TOP_K
      } else if v > MAX_RECALL_TOP_K {
        MAX_RECALL_TOP_K
      } else {
        v
      }
    None => DEFAULT_RECALL_TOP_K
  }
  let candidates_n = if self.recall_candidates > 0 {
    self.recall_candidates
  } else {
    let auto = k * 2
    if auto > MAX_RECALL_TOP_K {
      MAX_RECALL_TOP_K
    } else {
      auto
    }
  }
  let candidates_n = if candidates_n < k { k } else { candidates_n }
  // 嵌入查询（失败 → 单路 BM25）
  let query_vector : Array[Double] = match self.embedder.embed([query]) {
    Ok(vs) => if vs.length() > 0 { vs[0] } else { [] }
    Err(_) => []
  }
  let vector_hits = self.vector_index.search(user_id, query_vector, candidates_n)
  let keyword_hits = self.keyword_index.search(user_id, query, candidates_n)
  let vector_ids : Array[String] = vector_hits.map(p => p.0)
  let keyword_ids : Array[String] = keyword_hits.map(p => p.0)
  let fused = match self.fusion_policy {
    EqualRrf => rrf([vector_ids, keyword_ids], self.rrf_k, k)
    AdaptiveLexical => {
      let bm25_scores : Array[Double] = keyword_hits.map(p => p.1)
      let strong = lexical_strong(
        bm25_scores,
        self.lexical_floor,
        self.lexical_gap,
      )
      let soft = if strong && self.vector_weight_when_lexical <= 0.05 {
        let out : Array[String] = []
        let limit = if k < keyword_ids.length() { k } else { keyword_ids.length() }
        for i = 0; i < limit; i = i + 1 {
          out.push(keyword_ids[i])
        }
        out
      } else {
        let vector_weight = if strong {
          self.vector_weight_when_lexical
        } else {
          self.vector_weight_when_semantic
        }
        rrf_weighted(
          vector_ids,
          keyword_ids,
          self.rrf_k,
          k,
          vector_weight,
          1.0 - vector_weight,
        )
      }
      protect_bm25_topk(soft, keyword_ids, k)
    }
  }
  let results : Array[MemoryEntry] = []
  for id in fused {
    match self.entries.get(id) {
      Some(e) =>
        if e.user_id == user_id && e.is_recallable() {
          results.push(e)
        }
      None => ()
    }
  }
  // 补齐到 top_k（仅当已有命中；零命中返回空列表，不编造）
  match self.backfill {
    BackfillRecency =>
      if results.length() > 0 && results.length() < k {
        let in_results : Map[String, Bool] = Map([])
        for e in results {
          in_results.set(e.id, true)
        }
        match self.by_user.get(user_id) {
          Some(ids) => {
            // 最新优先（插入序倒序）
            let mut i = ids.length() - 1
            while i >= 0 && results.length() < k {
              match self.entries.get(ids[i]) {
                Some(e) =>
                  if e.is_recallable() && !in_results.contains(e.id) {
                    in_results.set(e.id, true)
                    results.push(e)
                  }
                None => ()
              }
              i = i - 1
            }
          }
          None => ()
        }
      }
    NoBackfill => ()
  }
  Ok(results)
}
