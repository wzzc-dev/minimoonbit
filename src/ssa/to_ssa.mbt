///| 将闭包IR转换为SSA形式
///| 使用基本块参数而非phi函数来实现SSA

///| 将闭包IR程序转换为SSA程序
pub fn to_ssa(input : @closure.Program) -> Ssa {
  // 初始化SSA程序
  let functions = []
  
  // 转换每个函数定义
  for fundef in input.fundefs {
    if not(@util.extenv.contains(fundef.old_name.to_string())) {
      let ssa_func = convert_function(fundef)
      functions.push(ssa_func)
    }
  }
  
  // 转换主函数体
  let main_func = convert_main_function(input.body)
  functions.push(main_func)
  
  { program: { functions, } }
}

///| 转换函数定义为SSA形式
fn convert_function(fundef : @closure.FuncDef) -> Function {
  // 创建函数参数
  let params = fundef.args.map(fn(arg) {
    // 为每个参数创建SSA值
    (Value::{ id: new_value_id() }, convert_type(arg.1))
  })
  
  // 创建基本块列表
  let blocks = []
  
  // 创建入口基本块
  let entry_block = BasicBlock::{
    id: Block::{ id: new_block_id() },
    params: [],  // 函数入口块没有参数
    instructions: [],
    terminator: Terminator::Return(None)  // 默认返回
  }
  
  // TODO: 实现完整的函数体转换逻辑
  // 这里需要将闭包IR表达式转换为SSA指令
  // 目前只是占位实现，实际需要遍历函数体并生成SSA指令
  // 需要处理闭包IR表达式到SSA指令的转换
  
  blocks.push(entry_block)
  
  {
    name: fundef.name.0.to_string(),
    params,
    return_type: convert_type(fundef.ty),
    blocks
  }
}

///| 转换主函数体为SSA形式
fn convert_main_function(_body : @closure.Expr) -> Function {
  // 创建主函数参数（通常为空）
  let params = []
  
  // 创建基本块列表
  let blocks = []
  
  // 创建入口基本块
  let entry_block = BasicBlock::{
    id: Block::{ id: new_block_id() },
    params: [],  // 主函数入口块没有参数
    instructions: [],
    terminator: Terminator::Return(None)  // 默认返回
  }
  
  // TODO: 实现主函数体转换逻辑
  // 这里需要将闭包IR表达式转换为SSA指令
  
  blocks.push(entry_block)
  
  {
    name: "minimbt_main",
    params,
    return_type: Type::Unit,
    blocks
  }
}

///| 转换类型
fn convert_type(ty : @closure.LowType) -> Type {
  match ty {
    Unit => Type::Unit
    Bool => Type::Bool
    Int => Type::Int
    Double => Type::Float
    DirectFn(args, ret) => Type::Function(args.map(convert_type), convert_type(ret))
    ClosureFn(args, ret) => Type::Function(args.map(convert_type), convert_type(ret))
    Tuple(elements) => Type::Tuple(elements.map(convert_type))
    Array(element) => Type::Array(convert_type(element))
    Ptr => Type::Pointer(Type::Int)
  }
}

///| 全局值ID计数器
let global_value_counter : Ref[Int] = Ref::new(0)

///| 生成新的值ID
fn new_value_id() -> Int {
  global_value_counter.val = global_value_counter.val + 1
  global_value_counter.val
}

///| 全局块ID计数器
let global_block_counter : Ref[Int] = Ref::new(0)

///| 生成新的块ID
fn new_block_id() -> Int {
  global_block_counter.val = global_block_counter.val + 1
  global_block_counter.val
}