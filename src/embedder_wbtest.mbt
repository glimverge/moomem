// 白盒：HashingEmbedder 与余弦。这些符号不是宿主契约。

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
