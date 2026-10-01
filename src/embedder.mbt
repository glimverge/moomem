// 注入点一：Embedder（PRD v1.1 决议 Q1：一等注入 trait）。
// 缺省实现 HashingEmbedder：确定性词袋哈希嵌入，无网络、O(n)。
// Clock 注入点见 clock.mbt。

///|
/// 嵌入服务抽象。生产环境可注入 vcdb 等适配实现。
pub(open) trait Embedder {
  /// 批量嵌入。返回数组与输入一一对应，每条长度必须等于 dim()。
  fn embed(self : Self, texts : Array[String]) -> Result[
    Array[Array[Double]],
    MoomemError,
  ]
  /// 嵌入维度。
  fn dim(self : Self) -> Int
}

///|
/// 缺省嵌入器：小写化 → 分词（与 BM25 同一分词器 tokenize）→
/// 每 token FNV-1a 哈希到 [0, dims) 桶 → 桶内 TF 累加 → L2 归一。
/// 确定性、离线，三后端行为一致。
pub struct HashingEmbedder {
  dims : Int
}

///|
/// 构造 HashingEmbedder；dim 必须 > 0，否则返回 Err。
pub fn HashingEmbedder::new(dim : Int) -> Result[HashingEmbedder, MoomemError] {
  if dim <= 0 {
    return Err(
      MoomemError::EmbeddingFailure(
        "HashingEmbedder dim must be positive, got \{dim}",
      ),
    )
  }
  Ok(HashingEmbedder::{ dims: dim, })
}

///|
pub impl Embedder for HashingEmbedder with fn embed(self, texts) {
  let result : Array[Array[Double]] = []
  for text in texts {
    result.push(hashing_embed_one(text, self.dims))
  }
  Ok(result)
}

///|
pub impl Embedder for HashingEmbedder with fn dim(self) {
  self.dims
}

///|
pub extend HashingEmbedder with Embedder::{embed, dim}

///|
fn hashing_embed_one(text : String, dims : Int) -> Array[Double] {
  let vec = Array::make(dims, 0.0)
  let tokens = tokenize(text)
  for t in tokens {
    let bucket = (fnv1a(t) & 0x7FFFFFFF) % dims
    vec[bucket] = vec[bucket] + 1.0
  }
  // L2 归一
  let mut norm_sq = 0.0
  for v in vec {
    norm_sq = norm_sq + v * v
  }
  let norm = norm_sq.sqrt()
  if norm > 0.0 {
    for i = 0; i < dims; i = i + 1 {
      vec[i] = vec[i] / norm
    }
  }
  vec
}

///|
/// 两向量余弦相似度；长度为 0 或不相等时返回 0.0（不 panic）。
pub fn cosine_similarity(a : Array[Double], b : Array[Double]) -> Double {
  if a.length() == 0 || a.length() != b.length() {
    return 0.0
  }
  let mut dot = 0.0
  let mut na = 0.0
  let mut nb = 0.0
  for i = 0; i < a.length(); i = i + 1 {
    dot = dot + a[i] * b[i]
    na = na + a[i] * a[i]
    nb = nb + b[i] * b[i]
  }
  if na == 0.0 || nb == 0.0 {
    return 0.0
  }
  dot / (na.sqrt() * nb.sqrt())
}
