// 黑盒测试：HashingEmbedder 的缺省维度、确定性与非法维度。

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
