// Clock 注入点。核心库不读系统时间。
// 与 Embedder 分文件，保持模块边界与文件 locality 一致。

///|
/// 时钟抽象。缺省 LogicalClock；测试可注入 FixedClock 精确断言 created_at。
pub(open) trait Clock {
  fn now_ms(self : Self) -> Int64
}

///|
/// 逻辑时钟：每次调用单调 +1ms。open 时从快照 header.clock 续接，
/// 测试确定性，生产可注入系统时钟。
pub struct LogicalClock {
  mut current : Int64
}

///|
pub fn LogicalClock::new(start? : Int64) -> LogicalClock {
  match start {
    Some(v) => LogicalClock::{ current: v, }
    None => LogicalClock::{ current: 0L, }
  }
}

///|
pub impl Clock for LogicalClock with fn now_ms(self) {
  self.current = self.current + 1L
  self.current
}

///|
pub extend LogicalClock with Clock::{now_ms}

///|
/// 固定时钟（测试用）：now_ms 恒返回初始值。
pub struct FixedClock {
  value : Int64
}

///|
pub fn FixedClock::new(value : Int64) -> FixedClock {
  FixedClock::{ value, }
}

///|
pub impl Clock for FixedClock with fn now_ms(self) {
  self.value
}

///|
pub extend FixedClock with Clock::{now_ms}
