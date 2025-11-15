///| 函数转换模块

///|

///| 提供将闭包IR函数转换为SSA形式的功能

///|

///|
/// 转换函数定义为SSA形式（使用预构建的函数环境）
pub fn convert_function_with_env(
  block_id : Block,
  fundef : @closure.FuncDef,
  func_env : @immut/hashmap.HashMap[String, Type],
) -> Function raise {
  // 创建函数参数（包括正常参数和自由变量）
  let regular_params = fundef.args.map(fn(arg) {
    Value::{ id: new_value_id(), ty: convert_type(arg.1) }
  })
  let free_var_params = fundef.free_vars.map(fn(free_var) {
    Value::{ id: new_value_id(), ty: convert_type(free_var.1) }
  })

  // 创建基本块列表
  let blocks = []

  // 创建入口基本块
  let entry_block = BasicBlock::{
    id: block_id,
    params: [], // 函数入口块没有参数
    instructions: [],
    terminator: Terminator::Return(None), // 默认返回
  }
  blocks.push(entry_block)

  // 创建变量环境，将函数参数添加到环境中
  // 注意：由于我们改变了参数顺序，需要相应调整索引
  let mut var_env = @immut/hashmap.new()
  for i, free_var in fundef.free_vars {
    let free_var_name = free_var.0
    let free_var_value = free_var_params[i]
    var_env = var_env.add(free_var_name.to_string(), free_var_value)
  }

  // 再添加正常参数到环境中（现在在参数列表的后面）
  for i, arg in fundef.args {
    let param_name = arg.0.to_string()
    let param_value = regular_params[i]
    var_env = var_env.add(param_name, param_value)
  }

  // 添加当前函数到函数环境
  let final_func_env = func_env.add(
    fundef.name.0.to_string(),
    convert_type(fundef.ty),
  )

  let context = {
    current_block: entry_block,
    blocks,
    block_map: @immut/hashmap.new(), // 块映射，用于控制流
    var_env,
    func_env: final_func_env,
  } // 包含参数和自由变量的环境
  let result = convert_expr(context, fundef.body)
  // @util.logger("convert_expr: " + result.to_json().stringify())
  // 更新最后一个块的终止指令，使其返回表达式的结果
  let final_context = result.context
  let return_value = result.value
  let updated_final_block = BasicBlock::{
    id: final_context.current_block.id,
    params: final_context.current_block.params,
    instructions: final_context.current_block.instructions,
    terminator: Terminator::Return(return_value),
  }

  // 使用转换后的上下文更新块列表
  let updated_blocks = final_context.blocks.map(fn(b) {
    if b.id == updated_final_block.id {
      updated_final_block
    } else {
      b
    }
  })
  {
    name: fundef.name.0.to_string(),
    params: regular_params,
    closure_param: free_var_params,
    ty: convert_type(fundef.ty),
    return_type: match fundef.ty {
      @closure.LowType::Function(_, ret, _) => convert_type(ret)
      _ => @util.die("unexpected fundef type: " + fundef.ty.to_string())
    },
    blocks: updated_blocks,
  }
}

///| 转换函数定义为SSA形式
pub fn convert_function(
  block_id : Block,
  fundef : @closure.FuncDef,
  functions : Array[Function],
) -> Function raise{
  // 创建函数参数（包括正常参数和自由变量）
  let regular_params = fundef.args.map(fn(arg) {
    Value::{ id: new_value_id(), ty: convert_type(arg.1) }
  })
  let free_var_params = fundef.free_vars.map(fn(free_var) {
    Value::{ id: new_value_id(), ty: convert_type(free_var.1) }
  })

  // 创建基本块列表
  let blocks = []

  // 创建入口基本块
  let entry_block = BasicBlock::{
    id: block_id,
    params: [], // 函数入口块没有参数
    instructions: [],
    terminator: Terminator::Return(None), // 默认返回
  }
  blocks.push(entry_block)

  // 创建变量环境，将函数参数添加到环境中
  // 注意：由于我们改变了参数顺序，需要相应调整索引
  let mut var_env = @immut/hashmap.new()
  for i, free_var in fundef.free_vars {
    let free_var_name = free_var.0
    let free_var_value = free_var_params[i]
    var_env = var_env.add(free_var_name.to_string(), free_var_value)
  }

  // 再添加正常参数到环境中（现在在参数列表的后面）
  for i, arg in fundef.args {
    let param_name = arg.0.to_string()
    let param_value = regular_params[i]
    var_env = var_env.add(param_name, param_value)
  }
  let mut func_env = @immut/hashmap.new().add(
    fundef.name.0.to_string(),
    convert_type(fundef.ty),
  )
  for func in functions {
    func_env = func_env.add(func.name, func.ty)
  }
  let context = {
    current_block: entry_block,
    blocks,
    block_map: @immut/hashmap.new(), // 块映射，用于控制流
    var_env,
    func_env,
  } // 包含参数和自由变量的环境
  let result = convert_expr(context, fundef.body)
  // @util.logger("convert_expr: " + result.to_string())
  // 更新最后一个块的终止指令，使其返回表达式的结果
  let final_context = result.context
  let return_value = result.value
  let updated_final_block = BasicBlock::{
    id: final_context.current_block.id,
    params: final_context.current_block.params,
    instructions: final_context.current_block.instructions,
    terminator: Terminator::Return(return_value),
  }

  // 使用转换后的上下文更新块列表
  let updated_blocks = final_context.blocks.map(fn(b) {
    if b.id == updated_final_block.id {
      updated_final_block
    } else {
      b
    }
  })
  {
    name: fundef.name.0.to_string(),
    params: regular_params,
    closure_param: free_var_params,
    ty: convert_type(fundef.ty),
    return_type: match fundef.ty {
      @closure.LowType::Function(_, ret, _) => convert_type(ret)
      _ => @util.die("unexpected fundef type: " + fundef.ty.to_string())
    },
    blocks: updated_blocks,
  }
}

///|

///|
/// 转换主函数体为SSA形式
pub fn convert_main_function(
  body : @closure.Expr,
  functions : Array[Function],
) -> Function raise {
  let block_id = new_block_id()
  convert_function(
    block_id,
    @closure.FuncDef::{
      name: @closure.Label("minimbt_main"),
      old_name: (try? @types.Name::from_string("minimbt_main")).unwrap(),
      is_closure: false,
      ty: @closure.LowType::Function([], @closure.LowType::Unit, false),
      args: [],
      free_vars: [],
      body,
    },
    functions,
  )
}
