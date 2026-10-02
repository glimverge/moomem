// 白盒：DedupIndex。这些符号不是宿主契约。

///|
test "DedupIndex: register / lookup / unregister per user" {
  let dedup = DedupIndex::new()
  dedup.register("user-a", "  我对花生过敏 ", "id-1")
  // 归一化后命中（大小写与首尾空白不敏感）
  inspect(
    dedup.lookup("user-a", "我对花生过敏") == Some("id-1"),
    content="true",
  )
  inspect(dedup.lookup("user-a", "I 对花生过敏") == None, content="true")
  // 跨 user 不命中（隔离）
  inspect(dedup.lookup("user-b", "我对花生过敏") == None, content="true")
  // 摘除后不命中
  dedup.unregister("user-a", "我对花生过敏")
  inspect(dedup.lookup("user-a", "我对花生过敏") == None, content="true")
}

///|
test "DedupIndex: subject-prefix / trailing-punct normalize as same fingerprint" {
  let dedup = DedupIndex::new()
  dedup.register("user-a", "用户的工号是 A1024。", "id-emp")
  // 「我的」主语与尾标点差异应命中同一指纹
  inspect(
    dedup.lookup("user-a", "我的工号是 A1024") == Some("id-emp"),
    content="true",
  )
  inspect(
    dedup.lookup("user-a", "工号是 A1024") == Some("id-emp"),
    content="true",
  )
  // 不同槽位值不应误命中
  inspect(dedup.lookup("user-a", "我的工号是 B2048") == None, content="true")
}
