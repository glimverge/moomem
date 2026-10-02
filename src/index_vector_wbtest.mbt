// 白盒：VectorIndex。分片隔离是跨用户不泄漏的索引层基础。

///|
test "VectorIndex: per-user isolation and top-k search" {
  let embedder = match HashingEmbedder::new(64) {
    Ok(e) => e
    Err(_) => {
      inspect("init failed", content="SHOULD NOT REACH")
      return
    }
  }
  let embed_one = (text : String) => {
    match embedder.embed([text]) {
      Ok(vs) => vs[0]
      Err(_) => []
    }
  }
  let index = VectorIndex::new()
  index.upsert("user-a", "a-1", embed_one("我对花生过敏"))
  index.upsert("user-a", "a-2", embed_one("花生过敏很严重"))
  index.upsert("user-b", "b-1", embed_one("我对花生过敏"))
  // user-a 检索：只命中 user-a 的条目
  let hits = index.search("user-a", embed_one("我对花生过敏"), 5)
  inspect(hits.length(), content="2")
  inspect(hits[0].0, content="a-1") // 完全相同 → cosine 1.0 排第一
  for h in hits {
    if h.0 != "a-1" && h.0 != "a-2" {
      inspect(h.0, content="LEAK")
    }
  }
  // user-b 检索：只命中 user-b 的条目
  let hits_b = index.search("user-b", embed_one("我对花生过敏"), 5)
  inspect(hits_b.length(), content="1")
  inspect(hits_b[0].0, content="b-1")
  // 不存在的 user：空结果
  inspect(
    index.search("user-c", embed_one("我对花生过敏"), 5).length(),
    content="0",
  )
  // 空查询向量：空结果（嵌入失败降级时的安全性）
  let empty : Array[Double] = []
  inspect(index.search("user-a", empty, 5).length(), content="0")
  // 零相似（正交）不返回
  let ortho = index.search("user-a", embed_one("zzz qqq xxx"), 5)
  inspect(ortho.length(), content="0")
}

///|
test "VectorIndex: remove drops entry from search" {
  let embedder = match HashingEmbedder::new(64) {
    Ok(e) => e
    Err(_) => {
      inspect("init failed", content="SHOULD NOT REACH")
      return
    }
  }
  let embed_one = (text : String) => {
    match embedder.embed([text]) {
      Ok(vs) => vs[0]
      Err(_) => []
    }
  }
  let index = VectorIndex::new()
  index.upsert("u", "id-1", embed_one("我爱北京"))
  index.upsert("u", "id-2", embed_one("我爱北京"))
  inspect(index.size("u"), content="2")
  index.remove("u", "id-1")
  inspect(index.size("u"), content="1")
  let hits = index.search("u", embed_one("我爱北京"), 5)
  inspect(hits.length(), content="1")
  inspect(hits[0].0, content="id-2")
}
