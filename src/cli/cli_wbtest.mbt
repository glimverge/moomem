// QA 对抗性测试(Edward):CLI 参数解析(白盒,访问包内 parse_options)。
// 依据:main.mbt 自身 help 文档的用法约定(FR-07)。
// native-only:CLI 为本地可执行入口;wasm/js 下 @fs/@env 链接不可用。

#cfg(target="native")
test "QA cli: documented trailing --all usage must be accepted" {
  // 帮助文本原文:"moomem list --db <dir> --user <id> [--all]" —— --all 位于末尾。
  // 帮助文本展示的标准用法必须可解析。
  let ok = match parse_options(["--all"], default_options()) {
    Ok(opts) => opts.show_all
    Err(_) => false
  }
  inspect(ok, content="true")
}

#cfg(target="native")
test "QA cli: --all before other options is accepted" {
  let ok = match parse_options(
      ["--all", "--db", "/tmp/qa-cli", "--user", "alice"],
      default_options(),
    ) {
    Ok(o) => o.show_all && o.db == "/tmp/qa-cli" && o.user == "alice"
    Err(_) => false
  }
  inspect(ok, content="true")
}

#cfg(target="native")
test "QA cli: standard add/recall option sets parse" {
  let add_ok = match parse_options(
      ["--db", "d1", "--user", "alice", "--text", "我对花生过敏"],
      default_options(),
    ) {
    Ok(o) => o.db == "d1" &&
      o.user == "alice" &&
      o.text == "我对花生过敏" &&
      o.top_k == 5 &&
      o.show_all == false &&
      o.file == None
    Err(_) => false
  }
  inspect(add_ok, content="true")
  let recall_ok = match parse_options(
      ["--db", "d1", "--user", "alice", "--query", "花生", "--top-k", "7"],
      default_options(),
    ) {
    Ok(o) => o.query == "花生" && o.top_k == 7
    Err(_) => false
  }
  inspect(recall_ok, content="true")
}

#cfg(target="native")
test "QA cli: bad --top-k / unknown option / missing value rejected" {
  let bad_topk = match parse_options(["--top-k", "abc"], default_options()) {
    Err(_) => true
    Ok(_) => false
  }
  inspect(bad_topk, content="true")
  let unknown = match parse_options(["--nope", "x"], default_options()) {
    Err(_) => true
    Ok(_) => false
  }
  inspect(unknown, content="true")
  let missing = match parse_options(["--user"], default_options()) {
    Err(_) => true
    Ok(_) => false
  }
  inspect(missing, content="true")
}
