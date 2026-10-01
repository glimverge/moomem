// 黑盒测试：核心类型 / user_id 校验 / JSON 编解码往返（T01 验收）。

test "user_id: legal ids accepted" {
  let cases = ["user-42", "a", "A.b_c-d", "0123456789", "x-y.z_w"]
  for id in cases {
    let ok = match @src.validate_user_id(id) {
      Ok(_) => true
      Err(_) => false
    }
    inspect(ok, content="true")
  }
}

test "user_id: 64 chars is the boundary" {
  // 恰好 64 个合法字符：通过
  let half = "abcdefghijklmnopqrstuvwxyzabcdef" // 32
  let legal = half + half
  inspect(legal.length(), content="64")
  let ok = match @src.validate_user_id(legal) {
    Ok(_) => true
    Err(_) => false
  }
  inspect(ok, content="true")
  // 65 个字符：拒绝
  let too_long = legal + "q"
  let rejected = match @src.validate_user_id(too_long) {
    Err(InvalidUserId(_)) => true
    _ => false
  }
  inspect(rejected, content="true")
}

test "user_id: illegal ids rejected (empty / path / charset / dot)" {
  let bad_ids = [
    "", "..", ".", "user/42", "user\\42", "user 42", "user\t42", "用户甲",
    "user@42", "user#1", "user/../../etc",
  ]
  for id in bad_ids {
    let rejected = match @src.validate_user_id(id) {
      Err(InvalidUserId(_)) => true
      _ => false
    }
    inspect(rejected, content="true")
  }
}

test "codec: MemoryEntry to_json -> from_json roundtrip" {
  let metadata : Map[String, Json] = Map([])
  metadata.set("extractor", Json::string("raw"))
  metadata.set("conflict_decision", Json::string("replace"))
  let entry : @src.MemoryEntry = @src.MemoryEntry::{
    id : "000000000001-abcd",
    user_id : "user-42",
    content : "我对花生过敏",
    kind : Unstructured,
    embedding : [0.1, 0.25, 0.5],
    keywords : ["我", "花生", "过敏"],
    status : Active,
    created_at : 42L,
    superseded_by : None,
    seq : 1,
    metadata,
  }
  let json_text = @src.entry_to_json(entry).stringify()
  let parsed = match @src.parse_json_line(json_text) {
    Ok(j) => j
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let restored = match @src.entry_from_json(parsed) {
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

test "codec: superseded entry with superseded_by roundtrip" {
  let entry : @src.MemoryEntry = @src.MemoryEntry::{
    id : "000000000002-ffff",
    user_id : "u",
    content : "用户住北京",
    kind : Fact,
    embedding : [],
    keywords : [],
    status : Superseded,
    created_at : 7L,
    superseded_by : Some("000000000003-0001"),
    seq : 2,
    metadata : Map([]),
  }
  let text = @src.entry_to_json(entry).stringify()
  let j = match @src.parse_json_line(text) {
    Ok(j) => j
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let restored = match @src.entry_from_json(j) {
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

test "codec: snapshot text build -> parse roundtrip with header" {
  let e1 : @src.MemoryEntry = @src.MemoryEntry::{
    id : "000000000001-00aa",
    user_id : "user-a",
    content : "fact one",
    kind : Fact,
    embedding : [0.5],
    keywords : ["fact", "one"],
    status : Active,
    created_at : 1L,
    superseded_by : None,
    seq : 1,
    metadata : Map([]),
  }
  let e2 : @src.MemoryEntry = @src.MemoryEntry::{
    id : "000000000002-00bb",
    user_id : "user-b",
    content : "fact two",
    kind : Preference,
    embedding : [0.25],
    keywords : ["fact", "two"],
    status : Deleted,
    created_at : 2L,
    superseded_by : None,
    seq : 2,
    metadata : Map([]),
  }
  let text = @src.build_snapshot_text(5, 2L, [e1, e2])
  let result = match @src.parse_snapshot_text(text) {
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

test "codec: version mismatch rejected" {
  let bad_header = "{\"v\":99,\"gen\":1,\"clock\":0}\n"
  let rejected = match @src.parse_snapshot_text(bad_header) {
    Err(StoreCorrupted(_)) => true
    _ => false
  }
  inspect(rejected, content="true")
}

test "codec: middle corruption rejected, tail truncation counted" {
  let e1 : @src.MemoryEntry = @src.MemoryEntry::{
    id : "000000000001-00aa",
    user_id : "u",
    content : "ok entry",
    kind : Fact,
    embedding : [],
    keywords : [],
    status : Active,
    created_at : 1L,
    superseded_by : None,
    seq : 1,
    metadata : Map([]),
  }
  let line1 = @src.entry_to_json(e1).stringify()
  // 中部损坏：两行之间夹一行坏行 → StoreCorrupted
  let middle_bad = "{\"v\":1,\"gen\":1,\"clock\":1}\n" + line1 + "\n{broken json!!!\n" + line1 + "\n"
  let rejected = match @src.parse_snapshot_text(middle_bad) {
    Err(StoreCorrupted(_)) => true
    _ => false
  }
  inspect(rejected, content="true")
  // 尾部半行损坏 → 截断计数
  let tail_bad = "{\"v\":1,\"gen\":1,\"clock\":1}\n" + line1 + "\n" + line1[:20].to_owned()
  let result = match @src.parse_snapshot_text(tail_bad) {
    Ok(r) => r
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(result.entries.length(), content="1")
  inspect(result.truncated_recovered, content="1")
}
