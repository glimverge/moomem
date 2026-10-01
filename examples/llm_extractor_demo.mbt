// moomem W2 示例：LLM 事实提取注入演示。
//
// 运行（无网络，脚本化 mock 驱动）：
//   moon run examples --target native
//
// 生产接线（需要真实 LLM，本示例不编译该路径以保持四后端零网络可跑）：
//
//   import "mizchi/llm/openai"  // 该子包经 ffi 走真实 HTTP，按宿主后端选择
//
//   // OpenAI 兼容端点（OpenAI / OpenRouter / Ollama / 自建网关均可）：
//   let provider = @openai.OpenAIProvider::new(
//     "sk-...",                                   // api_key
//     endpoint=OpenAIEndpoint::OpenAI,            // 或 Custom(base_url="https://...")
//     model="gpt-4o-mini",
//   )
//   let extractor = @llm_extractor.LlmExtractor::new(provider)
//   let judge = @llm_extractor.LlmConflictJudge::new(provider)
//   let cfg = @src.Config::{ extractor: Some(extractor as &@src.Extractor), .. }
//   let store = @src.MemoryStore::open("./my-memories", config=cfg)?

/// 演示用脚本化 Provider：模拟一次成功的 LLM 提取响应。
struct DemoProvider {
  replies : Array[String]
  mut calls : Int
}

impl @llm.Provider for DemoProvider with stream(
  self,
  _messages,
  _tools,
  handler
) {
  let idx = self.calls
  self.calls = self.calls + 1
  if idx < self.replies.length() {
    (handler.on_event)(@llm.StreamEvent::TextDelta(self.replies[idx]))
  }
}

impl @llm.Provider for DemoProvider with name(_) {
  "demo-mock-llm"
}

fn main {
  println("=== moomem W2: LLM 事实提取注入演示（mock 驱动，零网络） ===")
  println("")
  // 1) 注入 LLM 提取器与 LLM 冲突判定器（生产换真实 Provider 即可）
  let provider = DemoProvider::{
    replies : [
      "{\"facts\":[]}", // 纯闲聊 → 过滤，不入库
      "{\"facts\":[{\"content\":\"用户对花生过敏\",\"kind\":\"fact\",\"span\":\"我对花生过敏\"},{\"content\":\"偏好清淡的粤菜\",\"kind\":\"preference\",\"span\":\"我喜欢清淡的粤菜\"}]}",
      "{\"verdicts\":[]}", // 无冲突裁决（两条并存）
    ],
    calls : 0,
  }
  let p : &@llm.Provider = provider
  let extractor = @llm_extractor.LlmExtractor::new(p)
  let judge = @llm_extractor.LlmConflictJudge::new(p)
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let cfg : @src.Config = @src.Config::{
    embedder : None,
    extractor : Some(extractor as &@src.Extractor),
    judge : Some(judge as &@src.ConflictJudge),
    persistence : Some(backend),
    clock : None,
    dim : @src.DEFAULT_DIM,
    rrf_k : @src.DEFAULT_RRF_K,
    recall_candidates : 0,
    supersede_threshold : @src.DEFAULT_SUPERSEDE_THRESHOLD,
  }
  let store = match @src.MemoryStore::open("memory://demo", config=cfg) {
    Ok(s) => s
    Err(e) => {
      println("open failed: \{e.message()}")
      return
    }
  }
  // 2) 闲聊被过滤（AC-03）
  println("[add] 今天天气真不错呀~")
  match store.add("user-42", "今天天气真不错呀~") {
    Ok(s) => println("  -> extracted=\{s.extracted} inserted=\{s.inserted}（闲聊不入库）")
    Err(e) => println("  -> error: \{e.message()}")
  }
  // 3) 结构化事实入库（kind/span 可解释）
  println("[add] 你好！我对花生过敏，平时喜欢清淡的粤菜。")
  match store.add("user-42", "你好！我对花生过敏，平时喜欢清淡的粤菜。") {
    Ok(s) => {
      println("  -> extracted=\{s.extracted} inserted=\{s.inserted}")
      match store.list_entries("user-42") {
        Ok(entries) =>
          for e in entries {
            println("  -> [kind=\{e.kind}] \{e.content}")
          }
        Err(_) => ()
      }
    }
    Err(e) => println("  -> error: \{e.message()}")
  }
  // 4) 检索
  println("[recall] 查询「花生过敏」")
  match store.recall("user-42", "花生过敏") {
    Ok(hits) =>
      for h in hits {
        println("  -> 命中: [kind=\{h.kind}] \{h.content}")
      }
    Err(e) => println("  -> error: \{e.message()}")
  }
  // 5) 观测指标：LLM 调用预算（单次提取 ≤ 2 次，PRD 13.3）
  println("[观测] LLM 总调用次数: \{extractor.llm_call_count()} + \{judge.llm_call_count()} (judge)")
  let last_failure = match extractor.last_failure_reason() {
    Some(r) => r
    None => "None"
  }
  println("[观测] 最近提取失败: \{last_failure}")
  ignore(store.close())
  println("")
  println("=== 演示结束。生产环境请注入真实 Provider（见文件头注释）。 ===")
}
