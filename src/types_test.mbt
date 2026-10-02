// 黑盒测试：user_id 校验。

///|
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

///|
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

///|
test "user_id: illegal ids rejected (empty / path / charset / dot)" {
  let bad_ids = [
    "", "..", ".", "user/42", "user\\42", "user 42", "user\t42", "用户甲", "user@42",
    "user#1", "user/../../etc",
  ]
  for id in bad_ids {
    let rejected = match @src.validate_user_id(id) {
      Err(InvalidUserId(_)) => true
      _ => false
    }
    inspect(rejected, content="true")
  }
}
