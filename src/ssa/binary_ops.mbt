///| 二元运算模块

///|

///| 提供创建二元运算指令的功能

///|
/// 二元运算类型
pub enum BinaryOpType {
  Add
  Sub
  Mul
  Div
  Mod
  FAdd
  FSub
  FMul
  FDiv
  FMod
}

///|
/// 创建二元运算指令
pub fn create_binary_op(
  context : Context,
  op_type : BinaryOpType,
  left : Value,
  right : Value,
  result_type : Type,
) -> (Value, Context) {
  let result_value = Value::{ id: new_value_id(), ty: result_type }
  let opcode = match op_type {
    BinaryOpType::Add => Opcode::Add(left, right)
    BinaryOpType::Sub => Opcode::Sub(left, right)
    BinaryOpType::Mul => Opcode::Mul(left, right)
    BinaryOpType::Div => Opcode::Div(left, right)
    BinaryOpType::Mod => Opcode::Mod(left, right)
    BinaryOpType::FAdd => Opcode::FAdd(left, right)
    BinaryOpType::FSub => Opcode::FSub(left, right)
    BinaryOpType::FMul => Opcode::FMul(left, right)
    BinaryOpType::FDiv => Opcode::FDiv(left, right)
    BinaryOpType::FMod => Opcode::FMod(left, right)
  }
  let instruction = Instruction::{ result: result_value, opcode }
  context.current_block.instructions.push(instruction)
  (result_value, context)
}

///|
/// 创建GetElement指令
pub fn create_get_element(
  context : Context,
  tuple_value : Value,
  index : Int,
  element_type : Type,
) -> (Value, Context) {
  let element_value = Value::{ id: new_value_id(), ty: element_type }
  let instruction = Instruction::{
    result: element_value,
    opcode: Opcode::GetElement(tuple_value, index),
  }
  context.current_block.instructions.push(instruction)
  (element_value, context)
}
