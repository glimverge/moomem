// 白盒：Show 与 is_recallable。AddSummary / StoreStats 不能在黑盒测试里构造。

///|
test "Show and is_recallable cover every status and kind" {
  inspect(Active.to_string(), content="Active")
  inspect(Superseded.to_string(), content="Superseded")
  inspect(Deleted.to_string(), content="Deleted")
  inspect(EntryStatus::Unstructured.to_string(), content="Unstructured")
  inspect(Fact.to_string(), content="Fact")
  inspect(Preference.to_string(), content="Preference")
  inspect(Event.to_string(), content="Event")
  inspect(ById("e-1").to_string(), content="ById(e-1)")
  inspect(All.to_string(), content="All")
  inspect(NoBackfill.to_string(), content="NoBackfill")
  inspect(BackfillRecency.to_string(), content="BackfillRecency")
  inspect(EqualRrf.to_string(), content="EqualRrf")
  inspect(AdaptiveLexical.to_string(), content="AdaptiveLexical")
  let entry = MemoryEntry::{
    id: "000000000001-abcd",
    user_id: "user-42",
    content: "hello",
    kind: Fact,
    embedding: [1.0],
    keywords: ["hello", "world"],
    status: Active,
    created_at: 3L,
    superseded_by: None,
    seq: 1,
    metadata: Map([]),
  }
  inspect(entry.is_recallable(), content="true")
  inspect(entry.to_string().contains("superseded_by: none"), content="true")
  inspect(entry.to_string().contains("keywords: 2"), content="true")
  entry.status = EntryStatus::Unstructured
  inspect(entry.is_recallable(), content="true")
  entry.status = Superseded
  entry.superseded_by = Some("other")
  inspect(entry.is_recallable(), content="false")
  inspect(entry.to_string().contains("superseded_by: other"), content="true")
  entry.status = Deleted
  inspect(entry.is_recallable(), content="false")
  let summary = AddSummary::{
    extracted: 2,
    inserted: 1,
    duplicates: 1,
    superseded: 0,
    degraded: true,
    notes: ["first", "second"],
  }
  inspect(
    summary.to_string(),
    content="{extracted: 2, inserted: 1, duplicates: 1, superseded: 0, degraded: true, notes: [first, second]}",
  )
  let empty_notes = AddSummary::{
    ..summary,
    notes: [],
  }
  inspect(empty_notes.to_string().contains("notes: []"), content="true")
  let fresh = StoreStats::{
    total: 0,
    active: 0,
    superseded: 0,
    deleted: 0,
    unstructured: 0,
    bytes_on_disk: 0L,
    last_write_at: None,
    truncated_recovered: 0,
    extractor_mode: "raw",
  }
  inspect(fresh.to_string().contains("last_write_at: None"), content="true")
  let written = StoreStats::{
    ..fresh,
    last_write_at: Some(7L),
    unstructured: 1,
  }
  inspect(written.to_string().contains("last_write_at: Some(7)"), content="true")
}
