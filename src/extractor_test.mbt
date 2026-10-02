// 黑盒测试：RawExtractor 原文直通，空白文本不入库。

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
