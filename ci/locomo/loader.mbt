// Fixture loaders for LoCoMo subset / conflict pairs / extraction gold.

///|
struct LocomoTurn {
  dia_id : String
  text : String
}

///|
struct LocomoQA {
  question : String
  category : Int
  evidence : Array[String]
}

///|
struct LocomoConversation {
  sample_id : String
  turns : Array[LocomoTurn]
  qa : Array[LocomoQA]
}

///|
struct LocomoSubset {
  conversations : Array[LocomoConversation]
}

///|
struct ConflictPairCase {
  id : String
  old_text : String
  new_text : String
}

///|
struct ConflictFixture {
  near_duplicate : Array[ConflictPairCase]
  semantic : Array[ConflictPairCase]
}

///|
struct ExtractionCase {
  id : String
  text : String
  must_extract : Array[String]
  must_not_extract : Array[String]
}

///|
fn json_str(j : Json) -> String? {
  if j is String(s) {
    Some(s)
  } else {
    None
  }
}

///|
fn json_num_int(j : Json) -> Int? {
  if j is Number(n, ..) {
    Some(n.to_int())
  } else {
    None
  }
}

///|
fn json_obj(j : Json) -> Map[String, Json]? {
  if j is Object(obj) {
    Some(obj)
  } else {
    None
  }
}

///|
fn json_arr(j : Json) -> Array[Json]? {
  if j is Array(a) {
    Some(a)
  } else {
    None
  }
}

///|
fn json_str_field(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(v) => json_str(v)
    None => None
  }
}

///|
fn json_arr_field(obj : Map[String, Json], key : String) -> Array[Json]? {
  match obj.get(key) {
    Some(v) => json_arr(v)
    None => None
  }
}

///|
fn parse_string_array(arr : Array[Json]) -> Array[String] {
  let out : Array[String] = []
  for item in arr {
    match json_str(item) {
      Some(s) => out.push(s)
      None => ()
    }
  }
  out
}

///|
fn load_locomo_subset(path : String) -> LocomoSubset {
  let text = read_text_file(path)
  let root = @json.parse(text) catch {
    _ => fail("fixture is not valid JSON: \{path}")
  }
  let root_obj = match json_obj(root) {
    Some(o) => o
    None => fail("fixture root is not an object: \{path}")
  }
  let convs_json = match json_arr_field(root_obj, "conversations") {
    Some(a) => a
    None => fail("fixture missing conversations[]: \{path}")
  }
  let conversations : Array[LocomoConversation] = []
  for cj in convs_json {
    let obj = match json_obj(cj) {
      Some(o) => o
      None => fail("conversation entry is not an object")
    }
    let sample_id = match json_str_field(obj, "sample_id") {
      Some(s) => s
      None => fail("conversation missing sample_id")
    }
    let turns : Array[LocomoTurn] = []
    let sessions = match json_arr_field(obj, "sessions") {
      Some(a) => a
      None => fail("conversation \{sample_id} missing sessions[]")
    }
    for sj in sessions {
      let sobj = match json_obj(sj) {
        Some(o) => o
        None => fail("session is not an object in \{sample_id}")
      }
      let tarr = match json_arr_field(sobj, "turns") {
        Some(a) => a
        None => fail("session missing turns[] in \{sample_id}")
      }
      for tj in tarr {
        let tobj = match json_obj(tj) {
          Some(o) => o
          None => fail("turn is not an object in \{sample_id}")
        }
        let dia_id = match json_str_field(tobj, "dia_id") {
          Some(s) => s
          None => fail("turn missing dia_id in \{sample_id}")
        }
        let ttext = match json_str_field(tobj, "text") {
          Some(s) => s
          None => fail("turn missing text in \{sample_id}")
        }
        turns.push(LocomoTurn::{ dia_id, text: ttext, })
      }
    }
    let qa : Array[LocomoQA] = []
    let qarr = match json_arr_field(obj, "qa") {
      Some(a) => a
      None => fail("conversation \{sample_id} missing qa[]")
    }
    for qj in qarr {
      let qobj = match json_obj(qj) {
        Some(o) => o
        None => fail("qa entry is not an object in \{sample_id}")
      }
      let question = match json_str_field(qobj, "question") {
        Some(s) => s
        None => fail("qa missing question in \{sample_id}")
      }
      let category = match qobj.get("category") {
        Some(v) =>
          match json_num_int(v) {
            Some(n) => n
            None => fail("qa category not a number in \{sample_id}")
          }
        None => fail("qa missing category in \{sample_id}")
      }
      let evidence = match json_arr_field(qobj, "evidence") {
        Some(a) => parse_string_array(a)
        None => []
      }
      qa.push(LocomoQA::{ question, category, evidence, })
    }
    conversations.push(LocomoConversation::{ sample_id, turns, qa, })
  }
  LocomoSubset::{ conversations, }
}

///|
fn load_conflict_fixture(path : String) -> ConflictFixture {
  let text = read_text_file(path)
  let root = @json.parse(text) catch {
    _ => fail("conflict fixture invalid JSON: \{path}")
  }
  let obj = match json_obj(root) {
    Some(o) => o
    None => fail("conflict fixture root not object")
  }
  ConflictFixture::{
    near_duplicate: load_conflict_group(obj, "near_duplicate"),
    semantic: load_conflict_group(obj, "semantic"),
  }
}

///|
fn load_extraction_gold(path : String) -> Array[ExtractionCase] {
  let text = read_text_file(path)
  let root = @json.parse(text) catch {
    _ => fail("extraction gold invalid JSON: \{path}")
  }
  let obj = match json_obj(root) {
    Some(o) => o
    None => fail("extraction gold root not object")
  }
  let arr = match json_arr_field(obj, "cases") {
    Some(a) => a
    None => fail("extraction gold missing cases[]")
  }
  let out : Array[ExtractionCase] = []
  for item in arr {
    let o = match json_obj(item) {
      Some(x) => x
      None => fail("extraction case not object")
    }
    let id = match json_str_field(o, "id") {
      Some(s) => s
      None => fail("extraction case missing id")
    }
    let t = match json_str_field(o, "text") {
      Some(s) => s
      None => fail("extraction case \{id} missing text")
    }
    let must_extract = match json_arr_field(o, "must_extract") {
      Some(a) => parse_string_array(a)
      None => []
    }
    let must_not_extract = match json_arr_field(o, "must_not_extract") {
      Some(a) => parse_string_array(a)
      None => []
    }
    out.push(
      ExtractionCase::{ id, text: t, must_extract, must_not_extract, },
    )
  }
  out
}
