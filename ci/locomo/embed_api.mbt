// Opt-in OpenAI-compatible /embeddings embedder (W4-C). Native HTTP via mizchi/llm/ffi.

///|
struct ApiEmbedder {
  api_key : String
  base_url : String
  model : String
  batch : Int
  mut dim : Int
}

///|
fn build_embed_headers(api_key : String) -> String {
  let headers : Map[String, Json] = Map([])
  headers["Content-Type"] = Json::string("application/json")
  headers["Authorization"] = Json::string("Bearer \{api_key}")
  Json::object(headers).stringify()
}

///|
fn build_embed_body(model : String, inputs : Array[String]) -> String {
  let arr : Array[Json] = []
  for s in inputs {
    arr.push(Json::string(s))
  }
  let body : Map[String, Json] = Map([])
  body["model"] = Json::string(model)
  body["input"] = Json::array(arr)
  Json::object(body).stringify()
}

///|
fn parse_embeddings_response(body : String) -> Array[(Int, Array[Double])] {
  let root = @json.parse(body) catch { e => fail("embed JSON parse: \{e}") }
  let data = match root.value("data") {
    Some(v) =>
      match v.as_array() {
        Some(a) => a
        None => fail("embed response data is not array")
      }
    None => fail("embed response missing data")
  }
  let out : Array[(Int, Array[Double])] = []
  for item in data {
    let obj = match item.as_object() {
      Some(o) => o
      None => fail("embed data item not object")
    }
    let idx = match obj.get("index") {
      Some(v) =>
        match v.as_number() {
          Some(n) => n.to_int()
          None => 0
        }
      None => out.length()
    }
    let emb_j = match obj.get("embedding") {
      Some(v) => v
      None => fail("embed item missing embedding")
    }
    let emb_a = match emb_j.as_array() {
      Some(a) => a
      None => fail("embedding is not array")
    }
    let vec : Array[Double] = []
    for n in emb_a {
      match n.as_number() {
        Some(d) => vec.push(d)
        None => fail("embedding dim not number")
      }
    }
    out.push((idx, vec))
  }
  // sort by index
  let mut i = 0
  while i < out.length() {
    let mut j = i + 1
    while j < out.length() {
      if out[j].0 < out[i].0 {
        let tmp = out[i]
        out[i] = out[j]
        out[j] = tmp
      }
      j = j + 1
    }
    i = i + 1
  }
  out
}

///|
fn api_embed_once(
  self : ApiEmbedder,
  inputs : Array[String],
) -> Result[Array[Array[Double]], @src.MoomemError] {
  let url = "\{self.base_url}/embeddings"
  let headers = build_embed_headers(self.api_key)
  let body = build_embed_body(self.model, inputs)
  let ok_body : Array[String] = []
  let err_body : Array[String] = []
  @ffi.fetch(
    url,
    "POST",
    headers,
    body,
    60,
    fn(s) { ok_body.push(s) },
    fn(e) { err_body.push(e) },
  )
  if err_body.length() > 0 {
    return Err(
      @src.MoomemError::EmbeddingFailure("transport: \{err_body[0]}"),
    )
  }
  if ok_body.length() == 0 {
    return Err(@src.MoomemError::EmbeddingFailure("empty embed response"))
  }
  let parsed = parse_embeddings_response(ok_body[0])
  let vecs : Array[Array[Double]] = []
  for pair in parsed {
    vecs.push(pair.1)
  }
  if vecs.length() != inputs.length() {
    return Err(
      @src.MoomemError::EmbeddingFailure(
        "embed count mismatch: want \{inputs.length()} got \{vecs.length()}",
      ),
    )
  }
  Ok(vecs)
}

///|
fn ApiEmbedder::probe_dim(self : ApiEmbedder) -> Int {
  match api_embed_once(self, ["probe"]) {
    Ok(vs) => {
      if vs.length() == 0 || vs[0].length() == 0 {
        fail("embed probe returned empty vector")
      }
      self.dim = vs[0].length()
      self.dim
    }
    Err(e) => fail("embed probe failed: \{e.message()}")
  }
}

///|
fn ApiEmbedder::from_env() -> ApiEmbedder {
  let api_key = require_env("MOOMEM_EMBED_API_KEY")
  let base_raw = match @env.get_env_var("MOOMEM_EMBED_BASE_URL") {
    Some(v) => {
      let t = v.trim().to_owned()
      if t.length() > 0 { t } else { "https://api.openai.com/v1" }
    }
    None => "https://api.openai.com/v1"
  }
  let base_url = normalize_base_url(base_raw)
  // keep /v1 for embeddings path: normalize strips /v1 — re-append
  let base_url = if base_url.has_suffix("/v1") {
    base_url
  } else {
    "\{base_url}/v1"
  }
  let model = match @env.get_env_var("MOOMEM_EMBED_MODEL") {
    Some(v) => {
      let t = v.trim().to_owned()
      if t.length() > 0 { t } else { "text-embedding-3-small" }
    }
    None => "text-embedding-3-small"
  }
  let batch = match @env.get_env_var("MOOMEM_EMBED_BATCH") {
    Some(v) => {
      let t = v.trim().to_owned()
      if t.length() == 0 {
        32
      } else {
        parse_int_arg(t, "MOOMEM_EMBED_BATCH")
      }
    }
    None => 32
  }
  ApiEmbedder::{ api_key, base_url, model, batch, dim: 0, }
}

///|
pub impl @src.Embedder for ApiEmbedder with fn embed(self, texts) {
  if texts.length() == 0 {
    return Ok([])
  }
  let all : Array[Array[Double]] = []
  let mut i = 0
  while i < texts.length() {
    let end0 = i + self.batch
    let end = if end0 > texts.length() { texts.length() } else { end0 }
    let batch : Array[String] = []
    let mut j = i
    while j < end {
      batch.push(texts[j])
      j = j + 1
    }
    match api_embed_once(self, batch) {
      Ok(vs) => {
        for v in vs {
          all.push(v)
        }
      }
      Err(e) => return Err(e)
    }
    i = end
  }
  Ok(all)
}

///|
pub impl @src.Embedder for ApiEmbedder with fn dim(self) {
  self.dim
}

///|
pub extend ApiEmbedder with @src.Embedder::{embed, dim}
