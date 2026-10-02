// 白盒：RRF 融合与词法强命中。这些符号不是宿主契约。

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
  let tied = rrf([["a"], ["b"]], 60, 2)
  inspect(tied[0], content="a")
  inspect(tied[1], content="b")
  inspect(rrf_weighted(["a"], ["b"], 0, 3, 1.0, 1.0).length(), content="0")
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
  let appended = protect_bm25_topk(["a"], ["a", "b"], 3)
  inspect(appended.length(), content="2")
  inspect(appended[1], content="b")
}
