///|
/// 转换条件表达式为SSA指令
pub fn convert_conditional(
  context : Context,
  expr : @closure.Expr,
  x : @types.Name,
  y : @types.Name,
  e1 : @closure.Expr,
  e2 : @closure.Expr,
) -> ExprResult {
  // 先转换条件表达式的左操作数
  let result1 = convert_expr(context, @closure.Expr::Var(x))
  let context1 = result1.context
  // 转换右操作数
  let result2 = convert_expr(context1, @closure.Expr::Var(y))
  let context2 = result2.context

  // 获取两个操作数的值
  let value1 = match result1.value {
    Some(v) => v
    None => @util.die("Left operand of comparison has no value")
  }
  let value2 = match result2.value {
    Some(v) => v
    None => @util.die("Right operand of comparison has no value")
  }

  // 创建比较指令的结果值
  let cmp_result = Value::{ id: new_value_id(), ty: Type::Bool }
  let cmp_instruction = Instruction::{
    result: cmp_result,
    opcode: match expr {
      @closure.Expr::IfEq(_, _, _, _) => Opcode::Eq(value1, value2)
      @closure.Expr::IfLe(_, _, _, _) => Opcode::Le(value1, value2)
      @closure.Expr::IfLt(_, _, _, _) => Opcode::Lt(value1, value2)
      _ => @util.die("unexpected expression type")
    },
  }

  // 将比较指令添加到当前块
  context2.current_block.instructions.push(cmp_instruction)

  // 创建两个分支的块
  let then_block_id = new_block_id()
  let else_block_id = new_block_id()
  let merge_block_id = new_block_id()


  // 分析两个分支中修改的变量
  let then_modified_vars = analyze_modified_variables(e1, context2.var_env)
  let else_modified_vars = analyze_modified_variables(e2, context2.var_env)

  // 如果有变量修改，创建合并块的参数
  let merge_params = []
  let all_modified_vars = merge_modified_vars(
    then_modified_vars, else_modified_vars,
  )
  for var_name in all_modified_vars.keys() {
    match all_modified_vars.get(var_name) {
      Some(original_value) => {
        let param_value = Value::{ id: new_value_id(), ty: original_value.ty }
        merge_params.push(param_value)
      }
      None => @util.die("Failed to get modified variable value")
    }
  }

  // @util.logger("merge_params: " + merge_params.to_string())

  let merge_value = match infer_expression_type(e1, context2) {
    Unit => None
    ty => Some(Value::{ id: new_value_id(), ty })
  }

  let result_value = match merge_value {
    Some(v) => [v]
    None => []
  }
  // 如果有变量修改，将合并值作为第一个参数
  let final_merge_params = if merge_params.length() > 0 {
    result_value + merge_params
  } else {
    result_value
  }
  // println("final_merge_params: " + final_merge_params.to_string())
  // 创建then块
  let then_block = BasicBlock::{
    id: then_block_id,
    params: [],
    instructions: [],
    terminator: Terminator::Jump(merge_block_id, []), // 稍后更新
  }

  // 创建else块
  let else_block = BasicBlock::{
    id: else_block_id,
    params: [],
    instructions: [],
    terminator: Terminator::Jump(merge_block_id, []), // 稍后更新
  }

  // 创建合并块
  let merge_block = BasicBlock::{
    id: merge_block_id,
    params: final_merge_params,
    instructions: [],
    terminator: Terminator::Return(None), // 临时设置
  }

  // 更新当前块的终止指令
  let terminator = Terminator::Branch(
    cmp_result,
    then_block_id,
    [],
    else_block_id,
    [],
  )
  let updated_current_block = BasicBlock::{
    id: context2.current_block.id,
    params: context2.current_block.params,
    instructions: context2.current_block.instructions,
    terminator,
  }

  // 使用辅助函数更新块列表
  let mut context_with_blocks = add_block_to_context(
    context2, updated_current_block,
  )
  context_with_blocks = add_blocks_to_context(context_with_blocks, [
    then_block, else_block, merge_block,
  ])
  context_with_blocks = update_current_block(context_with_blocks, then_block)
  context_with_blocks = update_var_env(context_with_blocks, context2.var_env)

  // 转换then分支
  let then_result = convert_expr(context_with_blocks, e1)
  let then_context = then_result.context
  let then_args = match then_result.value {
    Some(v) => [v]
    None => []
  }

  // 添加修改变量的值
  let var_names = all_modified_vars.keys().to_array()
  for i = 0; i < var_names.length(); i = i + 1 {
    let var_name = var_names[i]
    let var_value = match then_context.var_env.get(var_name) {
      Some(current_val) => current_val
      None =>
        match all_modified_vars.get(var_name) {
          Some(original_val) => original_val
          None => merge_params[i]
        }
    }
    then_args.push(var_value)
  }
  let updated_then_block = BasicBlock::{
    id: then_context.current_block.id,
    params: then_context.current_block.params,
    instructions: then_context.current_block.instructions,
    terminator: Terminator::Jump(merge_block_id, then_args),
  }

  // 更新上下文，切换到else块
  let else_context = update_current_block(then_context, else_block)
  let else_context = update_var_env(else_context, context2.var_env)

  // 转换else分支
  let else_result = convert_expr(else_context, e2)
  let final_else_context = else_result.context
  let else_args = match else_result.value {
    Some(v) => [v]
    None => []
  }

  // 添加修改变量的值
  // let var_names = all_modified_vars.keys().to_array()
  for i = 0; i < var_names.length(); i = i + 1 {
    let var_name = var_names[i]
    let var_value = match final_else_context.var_env.get(var_name) {
      Some(current_val) => current_val
      None =>
        match all_modified_vars.get(var_name) {
          Some(original_val) => original_val
          None => merge_params[i]
        }
    }
    else_args.push(var_value)
  }
  let updated_else_block = BasicBlock::{
    id: final_else_context.current_block.id,
    params: final_else_context.current_block.params,
    instructions: final_else_context.current_block.instructions,
    terminator: Terminator::Jump(merge_block_id, else_args),
  }

  // 使用辅助函数更新最终块
  let mut final_context = add_block_to_context(
    final_else_context, updated_then_block,
  )
  final_context = add_block_to_context(final_context, updated_else_block)
  final_context = add_block_to_context(final_context, merge_block)
  final_context = update_current_block(final_context, merge_block)
  // @util.logger("final_merge_params: " + final_merge_params.to_string())
  // @util.logger("var_names: " + var_names.to_string())

  // 更新变量环境，使合并后的值可以被访问
  let mut updated_var_env = context2.var_env
  for i = 0; i < var_names.length(); i = i + 1 {
    let var_name = var_names[i]
    let param_index = if result_value.length() > 0 { i + 1 } else { i }
    // @util.logger("var_name: " + var_name + " param_index: " + param_index.to_string())
    if param_index < final_merge_params.length() {
      updated_var_env = updated_var_env.add(
        var_name,
        final_merge_params[param_index],
      )
    }
  }
  // @util.logger("updated_var_env: " + updated_var_env.to_string())
  final_context = update_var_env(final_context, updated_var_env)

  // 返回合并值作为结果
  // @util.logger("IfExpr result: " + merge_value.to_string())
  match merge_value {
    Some(v) => ExprResult::{ value: Some(v), context: final_context }
    None => ExprResult::{ value: None, context: final_context }
  }
}
