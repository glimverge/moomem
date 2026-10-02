// 黑盒测试：注入点抽象（Embedder / Extractor / ConflictJudge / Clock / dedup）
// 与降级路径（T02 验收，AC-05 的单元基础）。

///|
test "HashingEmbedder: deterministic and 256-dim by default" {
  let embedder = match @src.HashingEmbedder::new(256) {
    Ok(e) => e
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(embedder.dim(), content="256")
  let a = match embedder.embed(["我对花生过敏", "hello world"]) {
    Ok(vs) => vs
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(a.length(), content="2")
  inspect(a[0].length(), content="256")
  inspect(a[1].length(), content="256")
  // 同输入必同输出（确定性）
  let b = match embedder.embed(["我对花生过敏", "hello world"]) {
    Ok(vs) => vs
    Err(_) => {
      inspect("embed failed", content="SHOULD NOT REACH")
      return
    }
  }
  let mut all_equal = true
  for i = 0; i < 2; i = i + 1 {
    for j = 0; j < 256; j = j + 1 {
      if a[i][j] != b[i][j] {
        all_equal = false
      }
    }
  }
  inspect(all_equal, content="true")
  // L2 归一：每条向量模长为 1
  let mut norm_sq = 0.0
  for j = 0; j < 256; j = j + 1 {
    norm_sq = norm_sq + a[0][j] * a[0][j]
  }
  let close = norm_sq.is_close(1.0, absolute_tolerance=1.0e-9)
  inspect(close, content="true")
}

///|
test "HashingEmbedder: rejects non-positive dim" {
  let rejected = match @src.HashingEmbedder::new(0) {
    Err(EmbeddingFailure(_)) => true
    _ => false
  }
  inspect(rejected, content="true")
}

///|
test "RawExtractor: raw passthrough with kind=unstructured" {
  let extractor = @src.RawExtractor::new()
  inspect(extractor.mode(), content="raw")
  let facts = match extractor.extract("user-42", "我对花生过敏") {
    Ok(fs) => fs
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="我对花生过敏")
  inspect(facts[0].kind == Unstructured, content="true")
  inspect(facts[0].source_span == None, content="true")
  // raw 直通不是降级
  inspect(facts[0].degraded, content="false")
  inspect(facts[0].degrade_reason == None, content="true")
  // 空白文本 → 0 条（闲聊过滤入口）
  let blank = match extractor.extract("user-42", "   \n\t ") {
    Ok(fs) => fs
    Err(_) => {
      inspect("should be ok", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(blank.length(), content="0")
}

///|
test "Clock: LogicalClock increments, FixedClock constant" {
  let clock = @src.LogicalClock::new()
  inspect(clock.now_ms(), content="1")
  inspect(clock.now_ms(), content="2")
  let resumed = @src.LogicalClock::new(start=100L)
  inspect(resumed.now_ms(), content="101")
  let fixed = @src.FixedClock::new(42L)
  inspect(fixed.now_ms(), content="42")
  inspect(fixed.now_ms(), content="42")
}

