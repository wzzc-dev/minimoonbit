///| 上下文管理模块

///|

///| 提供SSA转换过程中的上下文管理功能

///|

///|
/// 转换上下文
pub struct Context {
  current_block : BasicBlock
  blocks : Array[BasicBlock]
  block_map : @immut/hashmap.HashMap[Int, BasicBlock]
  // 添加变量环境：Name到Value的映射
  var_env : @immut/hashmap.HashMap[String, Value]
  // 添加函数环境：函数名到函数类型的映射
  func_env : @immut/hashmap.HashMap[String, Type]
} derive(Show)

///|
/// 更新上下文中的当前块
pub fn update_current_block(context : Context, block : BasicBlock) -> Context {
  let updated_blocks = context.blocks.map(fn(b) {
    if b.id == block.id {
      block
    } else {
      b
    }
  })
  Context::{
    current_block: block,
    blocks: updated_blocks,
    block_map: context.block_map,
    var_env: context.var_env,
    func_env: context.func_env,
  }
}

///|
/// 更新上下文中的变量环境
pub fn update_var_env(
  context : Context,
  var_env : @immut/hashmap.HashMap[String, Value],
) -> Context {
  Context::{
    current_block: context.current_block,
    blocks: context.blocks,
    block_map: context.block_map,
    var_env,
    func_env: context.func_env,
  }
}

///|
/// 更新上下文中的块列表
pub fn update_blocks(context : Context, blocks : Array[BasicBlock]) -> Context {
  Context::{
    current_block: context.current_block,
    blocks,
    block_map: context.block_map,
    var_env: context.var_env,
    func_env: context.func_env,
  }
}

///|
/// 安全地添加块到上下文，避免重复
pub fn add_block_to_context(context : Context, block : BasicBlock) -> Context {
  let existing_ids = context.blocks.map(fn(b) { b.id })
  if existing_ids.contains(block.id) {
    // 替换现有块
    let updated_blocks = context.blocks.map(fn(b) {
      if b.id == block.id {
        block
      } else {
        b
      }
    })
    update_blocks(context, updated_blocks)
  } else {
    // 添加新块
    let new_blocks = context.blocks.copy()
    new_blocks.push(block)
    update_blocks(context, new_blocks)
  }
}

///|
/// 添加多个块到上下文
pub fn add_blocks_to_context(
  context : Context,
  blocks : Array[BasicBlock],
) -> Context {
  let mut result_context = context
  for block in blocks {
    result_context = add_block_to_context(result_context, block)
  }
  result_context
}

///|
pub fn update_current_terminator(
  context : Context,
  terminator : Terminator,
) -> Context {
  let updated_current_block = BasicBlock::{
    id: context.current_block.id,
    params: context.current_block.params,
    instructions: context.current_block.instructions,
    terminator,
  }
  update_current_block(context, updated_current_block)
}
