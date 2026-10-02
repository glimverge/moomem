// 白盒：分词、余弦、Jaccard、SimilarityJudge。这些符号不是宿主契约。

///|
test "HashingEmbedder: identical text cosine 1, disjoint text cosine 0" {
  let embedder = match HashingEmbedder::new(64) {
    Ok(e) => e
    Err(_) => {
      inspect("init failed", content="SHOULD NOT REACH")
      return
    }
  }
  let vs = match
    embedder.embed([
      "我对花生过敏", "我对花生过敏", "完全不同的内容XYZ",
    ]) {
    Ok(vs) => vs
    Err(_) => {
      inspect("embed failed", content="SHOULD NOT REACH")
      return
    }
  }
  let close = cosine_similarity(vs[0], vs[1]).is_close(
    1.0,
    absolute_tolerance=1.0e-9,
  )
  inspect(close, content="true")
}

///|
test "cosine_similarity: handcrafted orthogonal and parallel vectors" {
  let a : Array[Double] = [1.0, 0.0]
  let b : Array[Double] = [0.0, 1.0]
  let c : Array[Double] = [2.0, 0.0]
  let zero : Array[Double] = [0.0, 0.0]
  inspect(cosine_similarity(a, a), content="1")
  inspect(cosine_similarity(a, c), content="1")
  inspect(cosine_similarity(a, b), content="0")
  inspect(cosine_similarity(a, zero), content="0")
  inspect(cosine_similarity(a, []), content="0")
  inspect(cosine_similarity(a, [1.0]), content="0")
}

///|
test "tokenize: CJK single chars + bigrams, latin words lowercased" {
  let tokens = tokenize("我爱北京")
  inspect(tokens.length(), content="7") // 4 单字 + 3 二元组
  inspect(tokens[0], content="我")
  inspect(tokens[2], content="我爱")
  inspect(tokens[6], content="北京")
  let latin = tokenize("Hello, World! 123")
  inspect(latin.length(), content="3")
  inspect(latin[0], content="hello")
  inspect(latin[1], content="world")
  inspect(latin[2], content="123")
  let mixed = tokenize("用MoonBit写记忆")
  // 拉丁词 1 个 + CJK 单字 3 个 + 二元组 2 个 + CJK 单字 1 个起始
  inspect(mixed.length(), content="7")
  inspect(mixed[0], content="用")
  inspect(mixed[1], content="moonbit")
  inspect(mixed[6], content="记忆")
  inspect(tokenize("   ").length(), content="0")
}

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
}
