// 白盒：分词与 KeywordIndex。这些符号不是宿主契约。

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
