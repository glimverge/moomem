// 白盒：SimilarityJudge 与关键词 Jaccard。这些符号不是宿主契约。

///|
test "SimilarityJudge: replace / coexist / ignore bands" {
  let embedder = match HashingEmbedder::new(256) {
    Ok(e) => e
    Err(_) => {
      inspect("init failed", content="SHOULD NOT REACH")
      return
    }
  }
  // 阈值 0.9：精确测试三个区间
  let judge = SimilarityJudge::new(0.9, embedder)
  let make_entry = (id : String, content : String, emb : Array[Double]) => MemoryEntry::{
    id,
    user_id: "user-42",
    content,
    kind: Fact,
    embedding: emb,
    keywords: tokenize(content),
    status: Active,
    created_at: 1L,
    superseded_by: None,
    seq: 1,
    metadata: Map([]),
  }
  let embed_one = (text : String) => {
    match embedder.embed([text]) {
      Ok(vs) => vs[0]
      Err(_) => []
    }
  }
  // 候选 1：与新事实完全相同 → cosine 1.0 ≥ 0.9 → Replace
  let cand_same = make_entry(
    "e-same",
    "用户住北京",
    embed_one("用户住北京"),
  )
  // 候选 2：近似（嵌入接近但关键词不完全重合）→ sim ∈ [0.75, 0.9) → Coexist
  let cand_partial = make_entry(
    "e-partial",
    "用户住北京附近",
    embed_one("用户住北京附近"),
  )
  // 候选 3：完全无关 → sim < 0.75 → Ignore
  let cand_far = make_entry(
    "e-far",
    "今天天气不错",
    embed_one("今天天气不错"),
  )
  let fact : ExtractedFact = ExtractedFact::{
    content: "用户住北京",
    kind: Fact,
    source_span: None,
    degraded: false,
    degrade_reason: None,
  }
  let verdicts = match judge.judge(fact, [cand_same, cand_partial, cand_far]) {
    Ok(vs) => vs
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  // 期望：cand_same → Replace；cand_partial → Coexist（sim=0.832 ∈ [0.75, 0.9)）；cand_far 无裁决
  inspect(verdicts.length(), content="2")
  inspect(verdicts[0].existing.id, content="e-same")
  inspect(verdicts[0].decision == Replace, content="true")
  inspect(verdicts[1].existing.id, content="e-partial")
  inspect(verdicts[1].decision == Coexist, content="true")
}

///|
test "SimilarityJudge: keyword jaccard" {
  // tokenize("我爱北京") = {我,爱,北,京,我爱,爱北,北京}（7 个去重 token）
  let jac_full = keyword_jaccard("我爱北京", ["我", "爱", "北京"])
  let close = jac_full.is_close(3.0 / 7.0, absolute_tolerance=1.0e-9)
  inspect(close, content="true")
  let jac_partial = keyword_jaccard("我爱北京", [
    "我", "恨", "上海",
  ])
  let close = jac_partial.is_close(1.0 / 9.0, absolute_tolerance=1.0e-9)
  inspect(close, content="true")
  inspect(keyword_jaccard("我爱你", ["无关词"]), content="0")
  inspect(keyword_jaccard("", []), content="0")
  inspect(Replace.to_string(), content="Replace")
  inspect(Coexist.to_string(), content="Coexist")
  inspect(Ignore.to_string(), content="Ignore")
}

///|
struct ConflictFailingEmbedder {}

///|
impl Embedder for ConflictFailingEmbedder with fn embed(_, _) {
  Err(MoomemError::EmbeddingFailure("down"))
}

///|
impl Embedder for ConflictFailingEmbedder with fn dim(_) {
  4
}

///|
struct ConflictEmptyEmbedder {}

///|
impl Embedder for ConflictEmptyEmbedder with fn embed(_, _) {
  Ok([])
}

///|
impl Embedder for ConflictEmptyEmbedder with fn dim(_) {
  4
}

///|
test "SimilarityJudge: embedder failure falls back to keyword overlap" {
  let failing = SimilarityJudge::new(0.5, ConflictFailingEmbedder::{  })
  let fact : ExtractedFact = ExtractedFact::{
    content: "我爱北京",
    kind: Fact,
    source_span: None,
    degraded: false,
    degrade_reason: None,
  }
  let cand = MemoryEntry::{
    id: "c1",
    user_id: "user-42",
    content: "旧事实",
    kind: Fact,
    embedding: [1.0, 0.0],
    keywords: tokenize("我爱北京"),
    status: Active,
    created_at: 1L,
    superseded_by: None,
    seq: 1,
    metadata: Map([]),
  }
  let verdicts = match failing.judge(fact, [cand]) {
    Ok(vs) => vs
    Err(_) => {
      inspect("judge failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(verdicts.length(), content="1")
  inspect(verdicts[0].decision == Replace, content="true")
  let empty = SimilarityJudge::new(0.5, ConflictEmptyEmbedder::{  })
  let none = match empty.judge(fact, [cand]) {
    Ok(vs) => vs.length()
    Err(_) => -1
  }
  inspect(none, content="1")
}
