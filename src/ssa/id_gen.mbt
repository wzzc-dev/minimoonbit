///| ID生成器模块

///|

///| 为SSA转换过程提供唯一的值ID和块ID

///|

///|
/// 全局值ID计数器
let global_value_counter : Ref[Int] = Ref::new(0)

///|

///|
/// 生成新的值ID
pub fn new_value_id() -> Int {
  global_value_counter.val = global_value_counter.val + 1
  global_value_counter.val
}

///|

///|
/// 全局块ID计数器
let global_block_counter : Ref[Int] = Ref::new(0)

///|

///|
/// 生成新的块ID
pub fn new_block_id() -> Block {
  global_block_counter.val = global_block_counter.val + 1
  Block::{ id: global_block_counter.val }
}

///|

///|
/// 重置ID计数器（用于测试）
pub fn reset_counters() -> Unit {
  global_value_counter.val = 0
  global_block_counter.val = 0
}
