// 白盒：JSON 编解码与快照解析。这些函数不是宿主契约。

///|
test "codec: MemoryEntry to_json -> from_json roundtrip" {
  let metadata : Map[String, Json] = Map([])
  metadata.set("extractor", Json::string("raw"))
  metadata.set("conflict_decision", Json::string("replace"))
  let entry : MemoryEntry = MemoryEntry::{
    id: "000000000001-abcd",
    user_id: "user-42",
    content: "我对花生过敏",
    kind: Unstructured,
    embedding: [0.1, 0.25, 0.5],
    keywords: ["我", "花生", "过敏"],
    status: Active,
    created_at: 42L,
    superseded_by: None,
    seq: 1,
    metadata,
  }
  let json_text = entry_to_json(entry).stringify()
  let parsed = match parse_json_line(json_text) {
    Ok(j) => j
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let restored = match entry_from_json(parsed) {
    Ok(e2) => e2
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(restored.id, content="000000000001-abcd")
  inspect(restored.user_id, content="user-42")
  inspect(restored.content, content="我对花生过敏")
  inspect(restored.kind == Unstructured, content="true")
  inspect(restored.status == Active, content="true")
  inspect(restored.created_at, content="42")
  inspect(restored.seq, content="1")
  inspect(restored.superseded_by == None, content="true")
  inspect(restored.embedding.length(), content="3")
  let close = restored.embedding[0].is_close(0.1, absolute_tolerance=1.0e-9)
  inspect(close, content="true")
  let close = restored.embedding[2].is_close(0.5, absolute_tolerance=1.0e-9)
  inspect(close, content="true")
  inspect(restored.keywords.length(), content="3")
  inspect(restored.keywords[0], content="我")
  inspect(restored.keywords[1], content="花生")
  inspect(restored.keywords[2], content="过敏")
  let extractor_tag = match restored.metadata.get("extractor") {
    Some(Json::String(s)) => s
    _ => "NOT A STRING"
  }
  inspect(extractor_tag, content="raw")
  let conflict_tag = match restored.metadata.get("conflict_decision") {
    Some(Json::String(s)) => s
    _ => "NOT A STRING"
  }
  inspect(conflict_tag, content="replace")
}

///|
test "codec: superseded entry with superseded_by roundtrip" {
  let entry : MemoryEntry = MemoryEntry::{
    id: "000000000002-ffff",
    user_id: "u",
    content: "用户住北京",
    kind: Fact,
    embedding: [],
    keywords: [],
    status: Superseded,
    created_at: 7L,
    superseded_by: Some("000000000003-0001"),
    seq: 2,
    metadata: Map([]),
  }
  let text = entry_to_json(entry).stringify()
  let j = match parse_json_line(text) {
    Ok(j) => j
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let restored = match entry_from_json(j) {
    Ok(e2) => e2
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(restored.status == Superseded, content="true")
  let superseded_by = match restored.superseded_by {
    Some(id) => id
    None => "NONE"
  }
  inspect(superseded_by, content="000000000003-0001")
  inspect(restored.kind == Fact, content="true")
}

///|
test "codec: snapshot text build -> parse roundtrip with header" {
  let e1 : MemoryEntry = MemoryEntry::{
    id: "000000000001-00aa",
    user_id: "user-a",
    content: "fact one",
    kind: Fact,
    embedding: [0.5],
    keywords: ["fact", "one"],
    status: Active,
    created_at: 1L,
    superseded_by: None,
    seq: 1,
    metadata: Map([]),
  }
  let e2 : MemoryEntry = MemoryEntry::{
    id: "000000000002-00bb",
    user_id: "user-b",
    content: "fact two",
    kind: Preference,
    embedding: [0.25],
    keywords: ["fact", "two"],
    status: Deleted,
    created_at: 2L,
    superseded_by: None,
    seq: 2,
    metadata: Map([]),
  }
  let text = build_snapshot_text(5, 2L, [e1, e2])
  let result = match parse_snapshot_text(text) {
    Ok(r) => r
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(result.gen, content="5")
  inspect(result.clock, content="2")
  inspect(result.entries.length(), content="2")
  inspect(result.entries[0].content, content="fact one")
  inspect(result.entries[1].status == Deleted, content="true")
  inspect(result.truncated_recovered, content="0")
}

///|
test "codec: version mismatch rejected" {
  let bad_header = "{\"v\":99,\"gen\":1,\"clock\":0}\n"
  let rejected = match parse_snapshot_text(bad_header) {
    Err(StoreCorrupted(_)) => true
    _ => false
  }
  inspect(rejected, content="true")
}

///|
test "codec: middle corruption rejected, tail truncation counted" {
  let e1 : MemoryEntry = MemoryEntry::{
    id: "000000000001-00aa",
    user_id: "u",
    content: "ok entry",
    kind: Fact,
    embedding: [],
    keywords: [],
    status: Active,
    created_at: 1L,
    superseded_by: None,
    seq: 1,
    metadata: Map([]),
  }
  let line1 = entry_to_json(e1).stringify()
  // 中部损坏：两行之间夹一行坏行 → StoreCorrupted
  let middle_bad = "{\"v\":1,\"gen\":1,\"clock\":1}\n" +
    line1 +
    "\n{broken json!!!\n" +
    line1 +
    "\n"
  let rejected = match parse_snapshot_text(middle_bad) {
    Err(StoreCorrupted(_)) => true
    _ => false
  }
  inspect(rejected, content="true")
  // 尾部半行损坏 → 截断计数
  let tail_bad = "{\"v\":1,\"gen\":1,\"clock\":1}\n" +
    line1 +
    "\n" +
    line1[:20].to_owned()
  let result = match parse_snapshot_text(tail_bad) {
    Ok(r) => r
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(result.entries.length(), content="1")
  inspect(result.truncated_recovered, content="1")
}

///|
fn codec_base_object() -> Map[String, Json] {
  let obj : Map[String, Json] = Map([])
  obj.set("id", Json::string("000000000001-abcd"))
  obj.set("user_id", Json::string("user-42"))
  obj.set("content", Json::string("hello"))
  obj.set("kind", Json::string("fact"))
  obj.set("embedding", Json::array([Json::number(0.5)]))
  obj.set("keywords", Json::array([Json::string("hello")]))
  obj.set("status", Json::string("active"))
  obj.set("created_at", Json::number(1.0))
  obj.set("superseded_by", Json::null())
  obj.set("seq", Json::number(1.0))
  obj.set("metadata", Json::null())
  obj
}

///|
fn codec_rejects(j : Json, needle : String) -> Bool {
  match entry_from_json(j) {
    Err(StoreCorrupted(msg)) => msg.contains(needle)
    _ => false
  }
}

///|
test "codec: malformed fields and empty snapshot are rejected" {
  inspect(
    codec_rejects(Json::array([]), "not a JSON object"),
    content="true",
  )
  let missing_kind = codec_base_object()
  missing_kind.remove("kind")
  inspect(
    codec_rejects(Json::object(missing_kind), "missing field 'kind'"),
    content="true",
  )
  let missing_status = codec_base_object()
  missing_status.remove("status")
  inspect(
    codec_rejects(Json::object(missing_status), "missing field 'status'"),
    content="true",
  )
  let bad_span = codec_base_object()
  bad_span.set("superseded_by", Json::number(1.0))
  inspect(
    codec_rejects(Json::object(bad_span), "superseded_by"),
    content="true",
  )
  let bad_meta = codec_base_object()
  bad_meta.set("metadata", Json::array([]))
  inspect(
    codec_rejects(Json::object(bad_meta), "metadata"),
    content="true",
  )
  let bad_status = codec_base_object()
  bad_status.set("status", Json::string("nope"))
  inspect(
    codec_rejects(Json::object(bad_status), "unknown status"),
    content="true",
  )
  let status_num = codec_base_object()
  status_num.set("status", Json::number(1.0))
  inspect(
    codec_rejects(Json::object(status_num), "status is not a string"),
    content="true",
  )
  let bad_kind = codec_base_object()
  bad_kind.set("kind", Json::string("nope"))
  inspect(
    codec_rejects(Json::object(bad_kind), "unknown kind"),
    content="true",
  )
  let kind_num = codec_base_object()
  kind_num.set("kind", Json::number(1.0))
  inspect(
    codec_rejects(Json::object(kind_num), "kind is not a string"),
    content="true",
  )
  let id_num = codec_base_object()
  id_num.set("id", Json::number(1.0))
  inspect(
    codec_rejects(Json::object(id_num), "field 'id' is not a string"),
    content="true",
  )
  let missing_id = codec_base_object()
  missing_id.remove("id")
  inspect(
    codec_rejects(Json::object(missing_id), "field 'id' is missing"),
    content="true",
  )
  let seq_text = codec_base_object()
  seq_text.set("seq", Json::string("1"))
  inspect(
    codec_rejects(Json::object(seq_text), "field 'seq' is not a number"),
    content="true",
  )
  let missing_seq = codec_base_object()
  missing_seq.remove("seq")
  inspect(
    codec_rejects(Json::object(missing_seq), "field 'seq' is missing"),
    content="true",
  )
  let clock_text = codec_base_object()
  clock_text.set("created_at", Json::string("1"))
  inspect(
    codec_rejects(Json::object(clock_text), "field 'created_at' is not a number"),
    content="true",
  )
  let missing_clock = codec_base_object()
  missing_clock.remove("created_at")
  inspect(
    codec_rejects(Json::object(missing_clock), "field 'created_at' is missing"),
    content="true",
  )
  let emb_text = codec_base_object()
  emb_text.set("embedding", Json::string("nope"))
  inspect(
    codec_rejects(Json::object(emb_text), "field 'embedding' is not an array"),
    content="true",
  )
  let missing_emb = codec_base_object()
  missing_emb.remove("embedding")
  inspect(
    codec_rejects(Json::object(missing_emb), "field 'embedding' is missing"),
    content="true",
  )
  let emb_item = codec_base_object()
  emb_item.set("embedding", Json::array([Json::string("x")]))
  inspect(
    codec_rejects(Json::object(emb_item), "non-number"),
    content="true",
  )
  let kw_text = codec_base_object()
  kw_text.set("keywords", Json::string("nope"))
  inspect(
    codec_rejects(Json::object(kw_text), "field 'keywords' is not an array"),
    content="true",
  )
  let missing_kw = codec_base_object()
  missing_kw.remove("keywords")
  inspect(
    codec_rejects(Json::object(missing_kw), "field 'keywords' is missing"),
    content="true",
  )
  let kw_item = codec_base_object()
  kw_item.set("keywords", Json::array([Json::number(1.0)]))
  inspect(
    codec_rejects(Json::object(kw_item), "non-string"),
    content="true",
  )
  let null_ok = codec_base_object()
  let restored = match entry_from_json(Json::object(null_ok)) {
    Ok(e) => e.superseded_by == None && e.metadata.length() == 0
    Err(_) => false
  }
  inspect(restored, content="true")
  for kind in [Preference, Event] {
    let entry : MemoryEntry = MemoryEntry::{
      id: "000000000009-0001",
      user_id: "u",
      content: "kind roundtrip",
      kind,
      embedding: [],
      keywords: [],
      status: Unstructured,
      created_at: 1L,
      superseded_by: None,
      seq: 9,
      metadata: Map([]),
    }
    let back = match entry_from_json(entry_to_json(entry)) {
      Ok(e) => e.kind == kind && e.status == Unstructured
      Err(_) => false
    }
    inspect(back, content="true")
  }
  let empty = match parse_snapshot_text("") {
    Err(StoreCorrupted(msg)) => msg.contains("empty snapshot")
    _ => false
  }
  inspect(empty, content="true")
  let header = match parse_snapshot_text("[]\n") {
    Err(StoreCorrupted(msg)) => msg.contains("not a JSON object")
    _ => false
  }
  inspect(header, content="true")
  let blank_mid = match parse_snapshot_text(
    "{\"v\":1,\"gen\":1,\"clock\":1}\n\n{}\n",
  ) {
    Err(StoreCorrupted(msg)) => msg.contains("blank entry line")
    _ => false
  }
  inspect(blank_mid, content="true")
  let blank_line = match parse_json_line("   ") {
    Err(StoreCorrupted(msg)) => msg.contains("blank line")
    _ => false
  }
  inspect(blank_line, content="true")
  let bad_header = match parse_snapshot_header(Json::array([])) {
    Err(StoreCorrupted(msg)) => msg.contains("not a JSON object")
    _ => false
  }
  inspect(bad_header, content="true")
  let mismatch_obj : Map[String, Json] = Map([])
  mismatch_obj.set("v", Json::number(99.0))
  mismatch_obj.set("gen", Json::number(1.0))
  mismatch_obj.set("clock", Json::number(0.0))
  let mismatch = match parse_snapshot_header(Json::object(mismatch_obj)) {
    Err(StoreCorrupted(msg)) => msg.contains("version mismatch")
    _ => false
  }
  inspect(mismatch, content="true")
}
