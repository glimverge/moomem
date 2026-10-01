// 白盒测试：双索引（向量余弦 / BM25 CJK 分词）与 RRF 融合（T03 验收）。
// VectorIndex / KeywordIndex / rrf 为 package-private，故用 _wbtest。
// 核心断言：user 分片隔离的结构保证（AC-02 的索引层基础）。

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

///|
test "KeywordIndex: CJK query hits, per-user isolation, remove" {
  let index = KeywordIndex::new()
  index.upsert("user-a", "a-1", tokenize("我对花生过敏"))
  index.upsert("user-a", "a-2", tokenize("花生过敏要小心"))
  index.upsert("user-b", "b-1", tokenize("我对花生过敏"))
  // 中文查询命中
  let hits = index.search("user-a", "花生过敏", 5)
  inspect(hits.length(), content="2")
  inspect(hits[0].0, content="a-1")
  // 跨 user 隔离
  let hits_b = index.search("user-b", "花生过敏", 5)
  inspect(hits_b.length(), content="1")
  inspect(hits_b[0].0, content="b-1")
  inspect(index.search("user-c", "花生过敏", 5).length(), content="0")
  // 无关查询：空结果（不编造）
  inspect(index.search("user-a", "量子纠缠", 5).length(), content="0")
  // 摘除
  index.remove("user-a", "a-1")
  let after = index.search("user-a", "花生过敏", 5)
  inspect(after.length(), content="1")
  inspect(after[0].0, content="a-2")
  inspect(index.size("user-a"), content="1")
}

///|
test "KeywordIndex: BM25 ranking prefers stronger match" {
  let index = KeywordIndex::new()
  index.upsert("u", "doc-once", tokenize("花生"))
  index.upsert("u", "doc-many", tokenize("花生 花生 花生 花生"))
  let hits = index.search("u", "花生", 2)
  inspect(hits.length(), content="2")
  inspect(hits[0].0, content="doc-many") // tf 更高者排前
}

///|
test "rrf: fuses two ranked lists with deterministic order" {
  let list_a = ["x", "y", "z"]
  let list_b = ["y", "w", "x"]
  let fused = rrf([list_a, list_b], 60, 3)
  // y: 1/62 + 1/61; x: 1/61 + 1/63; z: 1/62; w: 1/62
  // y > x > z == w（z 与 w 同分，按 id 升序：w < z）
  inspect(fused.length(), content="3")
  inspect(fused[0], content="y")
  inspect(fused[1], content="x")
  inspect(fused[2], content="w")
}

///|
test "rrf: single list passes through, top_k truncates" {
  let single = rrf([["a", "b", "c"]], 60, 10)
  inspect(single.length(), content="3")
  inspect(single[0], content="a")
  let truncated = rrf([["a", "b", "c"]], 60, 2)
  inspect(truncated.length(), content="2")
  inspect(truncated[0], content="a")
  inspect(truncated[1], content="b")
  // 空输入
  inspect(rrf([], 60, 5).length(), content="0")
  // k 非法 → 空
  inspect(rrf([["a"]], 0, 5).length(), content="0")
}

///|
test "rrf_weighted: equal weights match equal rrf on two lists" {
  let vec = ["x", "y", "z"]
  let kw = ["y", "w", "x"]
  let equal = rrf([vec, kw], 60, 3)
  let weighted = rrf_weighted(vec, kw, 60, 3, 1.0, 1.0)
  inspect(weighted.length(), content="3")
  inspect(weighted[0], content=equal[0])
  inspect(weighted[1], content=equal[1])
  inspect(weighted[2], content=equal[2])
}

///|
test "rrf_weighted: lexical-favoring weight preserves BM25 top" {
  // BM25 强命中 b 排第一；向量把 a 排第一。降权向量后 b 应胜出。
  let vec = ["a", "b", "c"]
  let kw = ["b", "c", "a"]
  let fused = rrf_weighted(vec, kw, 60, 3, 0.15, 0.85)
  inspect(fused[0], content="b")
}

///|
test "lexical_strong: single hit above floor" {
  inspect(lexical_strong([2.0], 1.5, 1.2), content="true")
  inspect(lexical_strong([1.0], 1.5, 1.2), content="false")
  inspect(lexical_strong([], 1.5, 1.2), content="false")
}

///|
test "lexical_strong: gap and floor boundaries" {
  // top1/top2 = 2.4/2.0 = 1.2 → 刚好达标
  inspect(lexical_strong([2.4, 2.0], 1.5, 1.2), content="true")
  // 倍差不足
  inspect(lexical_strong([2.3, 2.0], 1.5, 1.2), content="false")
  // floor 不足
  inspect(lexical_strong([1.4, 1.0], 1.5, 1.2), content="false")
}

///|
test "protect_bm25_topk: reinjects missing BM25 tops" {
  // fused 丢掉了 BM25 的 b（第 2）；应换入
  let fused = ["x", "y", "z"]
  let kw = ["a", "b", "c"]
  let out = protect_bm25_topk(fused, kw, 3)
  inspect(out.length(), content="3")
  inspect(out.contains("a"), content="true")
  inspect(out.contains("b"), content="true")
  inspect(out.contains("c"), content="true")
}

///|
test "DedupIndex: register / lookup / unregister per user" {
  let dedup = DedupIndex::new()
  dedup.register("user-a", "  我对花生过敏 ", "id-1")
  // 归一化后命中（大小写与首尾空白不敏感）
  inspect(
    dedup.lookup("user-a", "我对花生过敏") == Some("id-1"),
    content="true",
  )
  inspect(dedup.lookup("user-a", "I 对花生过敏") == None, content="true")
  // 跨 user 不命中（隔离）
  inspect(dedup.lookup("user-b", "我对花生过敏") == None, content="true")
  // 摘除后不命中
  dedup.unregister("user-a", "我对花生过敏")
  inspect(dedup.lookup("user-a", "我对花生过敏") == None, content="true")
}

///|
test "DedupIndex: subject-prefix / trailing-punct normalize as same fingerprint" {
  let dedup = DedupIndex::new()
  dedup.register("user-a", "用户的工号是 A1024。", "id-emp")
  // 「我的」主语与尾标点差异应命中同一指纹
  inspect(
    dedup.lookup("user-a", "我的工号是 A1024") == Some("id-emp"),
    content="true",
  )
  inspect(
    dedup.lookup("user-a", "工号是 A1024") == Some("id-emp"),
    content="true",
  )
  // 不同槽位值不应误命中
  inspect(dedup.lookup("user-a", "我的工号是 B2048") == None, content="true")
}
