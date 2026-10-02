// 黑盒测试：LogicalClock 递增，FixedClock 恒定。

///|
test "Clock: LogicalClock increments, FixedClock constant" {
  let clock = @src.LogicalClock::new()
  inspect(clock.now_ms(), content="1")
  inspect(clock.now_ms(), content="2")
  let resumed = @src.LogicalClock::new(start=100L)
  inspect(resumed.now_ms(), content="101")
  let fixed = @src.FixedClock::new(42L)
  inspect(fixed.now_ms(), content="42")
  inspect(fixed.now_ms(), content="42")
}
