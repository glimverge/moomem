// 持久化层：PersistenceBackend trait + FsBackend（native，双槽快照 + head 指针）
// + MemoryBackend（测试 / wasm-js 缺省）。
//
// 共享约定：本文件是全库唯一允许出现 moonbitlang/x/fs 调用的地方（RK-03 隔离策略）。
// 后端差异（native→FsBackend，wasm/js→MemoryBackend）也只在此文件（#cfg）。
//
// 双槽快照方案（架构文档 1.4，对 PRD"追加写 JSONL"的有意偏差）：
//   <path>/moomem/slot0.jsonl   快照槽 A
//   <path>/moomem/slot1.jsonl   快照槽 B
//   <path>/moomem/head          内容 "0" 或 "1"，指向当前有效槽
//
// flush 流程：写非当前槽（完整覆盖写）→ 成功后写 head。
//   写槽中途崩溃 → head 仍指旧槽，数据无损；
//   写 head 中途崩溃 → head 损坏时回退"取能解析 header 且 gen 更大的槽"。

// ---------------------------------------------------------------------------
// 抽象
// ---------------------------------------------------------------------------

/// 持久化后端抽象。load 返回 None 表示空库（首次打开）。
pub(open) trait PersistenceBackend {
  load(self : Self) -> Result[String?, MoomemError]
  save(self : Self, snapshot : String) -> Result[Unit, MoomemError]
}

// ---------------------------------------------------------------------------
// MemoryBackend：进程内后端（测试崩溃注入 / wasm-js 缺省）
// ---------------------------------------------------------------------------

/// 进程内后端。保存完整快照字符串；支持模拟崩溃（半写 / 写失败）。
pub struct MemoryBackend {
  mut snapshot : String?
  /// 测试注入：写盘时只写入前 N 个字符（模拟进程被杀的半写状态）；None = 完整写入
  mut simulate_partial_write : Int?
  /// 测试注入：下一次 save 直接失败（模拟 IO 错误）
  mut fail_next_save : Bool
  /// 累计写入字节数（stats 的逻辑值来源）
  mut bytes_written : Int64
}

pub fn MemoryBackend::new() -> MemoryBackend {
  MemoryBackend::{
    snapshot : None,
    simulate_partial_write : None,
    fail_next_save : false,
    bytes_written : 0L,
  }
}

pub impl PersistenceBackend for MemoryBackend with load(self) {
  Ok(self.snapshot)
}

pub impl PersistenceBackend for MemoryBackend with save(self, snapshot) {
  if self.fail_next_save {
    self.fail_next_save = false
    return Err(MoomemError::IoFailure("MemoryBackend: simulated save failure"))
  }
  let stored = match self.simulate_partial_write {
    Some(n) => {
      let cut = if n < 0 {
        0
      } else if n < snapshot.length() {
        n
      } else {
        snapshot.length()
      }
      snapshot[:cut].to_owned()
    }
    None => snapshot
  }
  self.snapshot = Some(stored)
  self.bytes_written = self.bytes_written + stored.length().to_int64()
  Ok(())
}

pub extend MemoryBackend with PersistenceBackend::{save, load}

/// 当前保存的快照（测试观察用）。
pub fn MemoryBackend::peek(self : MemoryBackend) -> String? {
  self.snapshot
}

/// 测试注入：模拟进程被杀的半写状态（save 只写入前 n 个字符）；None = 完整写入。
pub fn MemoryBackend::set_simulate_partial_write(
  self : MemoryBackend,
  n : Int?
) -> Unit {
  self.simulate_partial_write = n
}

/// 测试注入：下一次 save 直接失败（模拟 IO 错误）。
pub fn MemoryBackend::set_fail_next_save(self : MemoryBackend, fail : Bool) -> Unit {
  self.fail_next_save = fail
}

// ---------------------------------------------------------------------------
// FsBackend：native 磁盘后端（双槽快照 + head 指针）
// ---------------------------------------------------------------------------

/// 磁盘后端。目录布局：
///   <path>/moomem/slot{0,1}.jsonl + <path>/moomem/head
pub struct FsBackend {
  /// 宿主给定的记忆库根目录
  base_dir : String
  /// 当前有效槽（0 / 1）
  mut slot : Int
}

pub fn FsBackend::new(path : String) -> FsBackend {
  FsBackend::{ base_dir : path, slot : 0 }
}

fn FsBackend::moomem_dir(self : FsBackend) -> String {
  "\{self.base_dir}/moomem"
}

fn FsBackend::slot_path(self : FsBackend, slot : Int) -> String {
  "\{self.moomem_dir()}/slot\{slot}.jsonl"
}

fn FsBackend::head_path(self : FsBackend) -> String {
  "\{self.moomem_dir()}/head"
}

/// 读取指定槽文件并校验其 header 可解析（用于槽选择）；失败返回 None。
fn FsBackend::read_slot_if_valid(
  self : FsBackend,
  slot : Int
) -> Result[String?, MoomemError] {
  let path = self.slot_path(slot)
  if !@fs.path_exists(path) {
    return Ok(None)
  }
  try {
    let content = @fs.read_file_to_string(path)
    // 校验首行 header 可解析（尾部半行损坏交给上层 store 截断处理）
    let first_line = match content.split("\n").next() {
      Some(l) => l.to_owned()
      None => ""
    }
    match parse_json_line(first_line) {
      Ok(header_json) => {
        match parse_snapshot_header(header_json) {
          Ok(_) => Ok(Some(content))
          Err(_) => Ok(None) // header 版本不符等：视为无效槽
        }
      }
      Err(_) => Ok(None)
    }
  } catch {
    e => Err(MoomemError::IoFailure(io_error_message("read '\{path}'", e)))
  }
}

/// 从快照文本解析 header 中的 gen（用于双槽歧义时取大者）。
fn snapshot_gen_of(content : String) -> Int? {
  let first_line = match content.split("\n").next() {
    Some(l) => l.to_owned()
    None => return None
  }
  match parse_json_line(first_line) {
    Ok(header_json) =>
      match parse_snapshot_header(header_json) {
        Ok((_, gen, _)) => Some(gen)
        Err(_) => None
      }
    Err(_) => None
  }
}

pub impl PersistenceBackend for FsBackend with load(self) {
  try {
    // 确保目录结构存在（FR-01：目录不存在则创建）
    mkdir_p(self.base_dir)
    mkdir_p(self.moomem_dir())
    let head_content : String? = if @fs.path_exists(self.head_path()) {
      Some(@fs.read_file_to_string(self.head_path()))
    } else {
      None
    }
    let head_slot : Int? = match head_content {
      Some(c) =>
        match c.trim() {
          "0" => Some(0)
          "1" => Some(1)
          _ => None // head 损坏（写 head 中途崩溃）
        }
      None => None
    }
    match head_slot {
      Some(primary) => {
        // head 有效：优先读所指槽；损坏则回退另一槽
        let other = 1 - primary
        let primary_slot = self.read_slot_if_valid(primary)
        let other_slot = self.read_slot_if_valid(other)
        match (primary_slot, other_slot) {
          (Ok(Some(content)), _) => {
            self.slot = primary
            Ok(Some(content))
          }
          (Ok(None), Ok(Some(content))) => {
            self.slot = other
            Ok(Some(content))
          }
          (Ok(None), Ok(None)) => {
            let base = self.base_dir
            let p0 = self.slot_path(primary)
            let p1 = self.slot_path(other)
            if @fs.path_exists(p0) || @fs.path_exists(p1) {
              // 槽文件存在但 header 均无法解析 → 双槽均损坏
              Err(
                MoomemError::StoreCorrupted(
                  "both snapshot slots exist but are unreadable (base: '\{base}')",
                ),
              )
            } else {
              Ok(None) // 空库
            }
          }
          (Err(e), _) => Err(e)
          (_, Err(e)) => Err(e)
        }
      }
      None => {
        // head 缺失或损坏：双槽歧义 → 取能完整解析 header 且 gen 更大者
        let slot0 = self.read_slot_if_valid(0)
        let slot1 = self.read_slot_if_valid(1)
        match (slot0, slot1) {
          (Ok(Some(a)), Ok(Some(b))) => {
            let gen_a = snapshot_gen_of(a)
            let gen_b = snapshot_gen_of(b)
            let pick_b = match (gen_a, gen_b) {
              (Some(ga), Some(gb)) => gb >= ga
              (None, Some(_)) => true
              (Some(_), None) => false
              (None, None) => false
            }
            if pick_b {
              self.slot = 1
              Ok(Some(b))
            } else {
              self.slot = 0
              Ok(Some(a))
            }
          }
          (Ok(Some(a)), Ok(None)) => {
            self.slot = 0
            Ok(Some(a))
          }
          (Ok(None), Ok(Some(b))) => {
            self.slot = 1
            Ok(Some(b))
          }
          (Ok(None), Ok(None)) => {
            let base = self.base_dir
            let p0 = self.slot_path(0)
            let p1 = self.slot_path(1)
            if @fs.path_exists(p0) || @fs.path_exists(p1) {
              Err(
                MoomemError::StoreCorrupted(
                  "both snapshot slots exist but are unreadable (base: '\{base}')",
                ),
              )
            } else {
              Ok(None) // 空库
            }
          }
          (Err(e), _) => Err(e)
          (_, Err(e)) => Err(e)
        }
      }
    }
  } catch {
    e => Err(
        MoomemError::IoFailure(io_error_message("load (base '\{self.base_dir}')", e)),
      )
  }
}

pub impl PersistenceBackend for FsBackend with save(self, snapshot) {
  try {
    mkdir_p(self.base_dir)
    mkdir_p(self.moomem_dir())
    let target = 1 - self.slot
    // 1. 完整写非当前槽
    @fs.write_string_to_file(self.slot_path(target), snapshot)
    // 2. 成功后写 head（内容仅 1 字节，实践上近原子）
    @fs.write_string_to_file(self.head_path(), "\{target}")
    self.slot = target
    Ok(())
  } catch {
    e => Err(MoomemError::IoFailure(io_error_message("save (base '\{self.base_dir}')", e)))
  }
}

pub extend FsBackend with PersistenceBackend::{save, load}

/// 将 @fs 的 IOError 转为可读消息。
fn io_error_message(op : String, e : @fs.IOError) -> String {
  let detail : String = match e {
    @fs.IOError(msg) => msg
  }
  "\{op} failed: \{detail}"
}

/// 逐级创建目录（x/fs 的 create_dir 在 native 不支持嵌套路径）。
/// 已存在的层级跳过；绝对路径以 "/" 起始。
fn mkdir_p(path : String) -> Unit raise @fs.IOError {
  if @fs.path_exists(path) {
    return
  }
  let segments : Array[String] = []
  for seg in path.split("/") {
    segments.push(seg.to_owned())
  }
  let mut acc = ""
  for i = 0; i < segments.length(); i = i + 1 {
    let seg = segments[i]
    if acc.length() == 0 {
      if seg.length() == 0 {
        acc = "/" // 绝对路径起始
        continue
      }
      acc = seg // 相对路径首段
    } else {
      if seg.length() == 0 || seg == "." {
        continue
      }
      if acc == "/" {
        acc = "/" + seg
      } else {
        acc = acc + "/" + seg
      }
    }
    if seg.length() > 0 && seg != "." && !@fs.path_exists(acc) {
      @fs.create_dir(acc)
    }
  }
}

// ---------------------------------------------------------------------------
// 缺省后端选择（架构文档 1.5：native→FsBackend；wasm/js→MemoryBackend）
// ---------------------------------------------------------------------------

#cfg(target="native")
pub fn default_backend(path : String) -> Result[&PersistenceBackend, MoomemError] {
  let backend = FsBackend::new(path)
  Ok(backend as &PersistenceBackend)
}

#cfg(not(target="native"))
pub fn default_backend(_path : String) -> Result[&PersistenceBackend, MoomemError] {
  // wasm/js 无本地文件系统：缺省进程内后端；宿主可通过 config.persistence
  // 注入自己的持久化适配（如浏览器 IndexedDB 胶水）。
  let backend = MemoryBackend::new()
  Ok(backend as &PersistenceBackend)
}
