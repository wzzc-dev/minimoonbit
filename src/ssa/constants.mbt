///| 常量创建模块
///|
///| 提供创建各种类型常量值的功能

///| 创建常量值并添加到当前块
pub fn create_const_int(context : Context, value : Int) -> (Value, Context) {
  let const_value = Value::{ id: new_value_id(), ty: Type::Int }
  let instruction = Instruction::{
    result: const_value,
    opcode: Opcode::ConstInt(value),
  }
  context.current_block.instructions.push(instruction)
  (const_value, context)
}

///| 创建浮点常量值并添加到当前块
pub fn create_const_float(context : Context, value : Double) -> (Value, Context) {
  let const_value = Value::{ id: new_value_id(), ty: Type::Float }
  let instruction = Instruction::{
    result: const_value,
    opcode: Opcode::ConstFloat(value),
  }
  context.current_block.instructions.push(instruction)
  (const_value, context)
}

///| 创建布尔常量值并添加到当前块
pub fn create_const_bool(context : Context, value : Bool) -> (Value, Context) {
  let const_value = Value::{ id: new_value_id(), ty: Type::Bool }
  let instruction = Instruction::{
    result: const_value,
    opcode: Opcode::ConstBool(value),
  }
  context.current_block.instructions.push(instruction)
  (const_value, context)
}
