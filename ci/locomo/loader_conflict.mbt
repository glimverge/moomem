// Conflict fixture loading (top-level helpers; MoonBit disallows nested fn).

///|
fn load_conflict_group(
  obj : Map[String, Json],
  key : String,
) -> Array[ConflictPairCase] {
  let arr = match json_arr_field(obj, key) {
    Some(a) => a
    None => fail("conflict fixture missing \{key}[]")
  }
  let out : Array[ConflictPairCase] = []
  for item in arr {
    let o = match item.as_object() {
      Some(x) => x
      None => fail("conflict pair not object")
    }
    let id = match json_str_field(o, "id") {
      Some(s) => s
      None => fail("conflict pair missing id")
    }
    let old_text = match json_str_field(o, "old") {
      Some(s) => s
      None => fail("conflict pair \{id} missing old")
    }
    let new_text = match json_str_field(o, "new") {
      Some(s) => s
      None => fail("conflict pair \{id} missing new")
    }
    out.push(ConflictPairCase::{ id, old_text, new_text, })
  }
  out
}
