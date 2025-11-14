///|
/// 转换While循环表达式为SSA指令
pub fn convert_while(
  context : Context,
  cond_expr : @closure.Expr,
  body_expr : @closure.Expr,
) -> ExprResult raise {
  // 创建While循环需要的块
  let loop_header_block_id = new_block_id() // 循环头块（条件检查）
  let modified_vars = analyze_modified_variables(body_expr, context.var_env)

  // 为循环头块创建参数，用于接收循环体中更新的变量
  let loop_header_params = []
  for var_name in modified_vars.keys() {
    match modified_vars.get(var_name) {
      Some(original_value) => {
        let param_value = Value::{ id: new_value_id(), ty: original_value.ty }
        loop_header_params.push(param_value)
      }
      None => ()
    }
  }

  // 更新当前变量环境，将修改的变量映射到新的参数
  let mut updated_var_env_for_header = context.var_env
  let var_names = modified_vars.keys().to_array()
  for i = 0
      i < var_names.length() && i < loop_header_params.length()
      i = i + 1 {
    let var_name = var_names[i]
    updated_var_env_for_header = updated_var_env_for_header.add(
      var_name,
      loop_header_params[i],
    )
  }
  let terminator = Terminator::Jump(
    loop_header_block_id,
    modified_vars.values().to_array(),
  )
  let context = update_current_terminator(context, terminator)
  let loop_body_block_id = new_block_id() // 循环体块
  let loop_exit_block_id = new_block_id() // 循环退出块

  // 创建循环头块，用于判断循环条件
  let loop_header_block = BasicBlock::{
    id: loop_header_block_id,
    params: loop_header_params, // 循环头块接收修改的变量作为参数
    instructions: [],
    terminator: Terminator::Return(None), // 临时设置
  }

  // 将循环头块添加到上下文
  let context_with_header = add_block_to_context(context, loop_header_block)

  // 切换到循环头块进行条件表达式的转换
  let header_context = update_current_block(
    context_with_header, loop_header_block,
  )
  let header_context_with_var_env = update_var_env(
    header_context, updated_var_env_for_header,
  ) // 使用更新后的变量环境

  // 转换条件表达式
  let cond_result = convert_expr(header_context_with_var_env, cond_expr)
  let header_context_final = cond_result.context
  let cond_value = match cond_result.value {
    Some(v) => v
    None => @util.die("Condition expression has no value")
  }

  // 更新循环头块的终止指令，使其根据条件跳转到循环体或退出块
  // 当跳转到退出块时，需要传递当前的循环变量值
  let current_var_values = []
  for var_name in modified_vars.keys() {
    match header_context_final.var_env.get(var_name) {
      Some(current_value) => current_var_values.push(current_value)
      None =>
        // 如果在当前环境中找不到，使用原始值
        match modified_vars.get(var_name) {
          Some(original_value) => current_var_values.push(original_value)
          None => ()
        }
    }
  }

  // 为false分支（退出块）准备当前的变量值
  let current_values_for_exit = []
  for var_name in modified_vars.keys() {
    match header_context_final.var_env.get(var_name) {
      Some(current_value) => current_values_for_exit.push(current_value)
      None =>
        // 如果在当前环境中找不到，使用原始值
        match modified_vars.get(var_name) {
          Some(original_value) => current_values_for_exit.push(original_value)
          None => ()
        }
    }
  }
  let updated_loop_header_block = BasicBlock::{
    id: header_context_final.current_block.id,
    params: header_context_final.current_block.params,
    instructions: header_context_final.current_block.instructions,
    terminator: Terminator::Branch(
      cond_value,
      loop_body_block_id,
      [],
      loop_exit_block_id,
      current_values_for_exit,
    ),
  }

  // 将更新后的循环头块添加回上下文
  let context_with_updated_header = add_block_to_context(
    header_context_final, updated_loop_header_block,
  )

  // 创建循环体块
  let loop_body_block = BasicBlock::{
    id: loop_body_block_id,
    params: [],
    instructions: [],
    terminator: Terminator::Jump(loop_header_block_id, []), // 跳回循环头块进行条件检查
  }

  // 将循环体块添加到上下文
  let context_with_body = add_block_to_context(
    context_with_updated_header, loop_body_block,
  )

  // 切换到循环体块进行转换
  let body_context = update_current_block(context_with_body, loop_body_block)
  // 循环体应该使用循环头块的参数值，而不是原始值
  let body_context_with_var_env = update_var_env(
    body_context, updated_var_env_for_header,
  ) // 使用更新后的变量环境

  // 转换循环体
  let body_result = convert_expr(body_context_with_var_env, body_expr)
  let body_context_final = body_result.context

  // 收集循环体中修改的变量的最新值
  let body_modified_vars = analyze_modified_variables(
    body_expr,
    context.var_env,
  )
  let body_updated_values = []
  for var_name in body_modified_vars.keys() {
    match body_context_final.var_env.get(var_name) {
      Some(updated_value) => body_updated_values.push(updated_value)
      None =>
        // 如果在循环体中没有找到更新的值，使用原始值
        match modified_vars.get(var_name) {
          Some(original_value) => body_updated_values.push(original_value)
          None => ()
        }
    }
  }

  // 更新循环体块的终止指令，使其跳回循环头块并传递更新后的变量值
  let updated_loop_body_block = BasicBlock::{
    id: body_context_final.current_block.id,
    params: body_context_final.current_block.params,
    instructions: body_context_final.current_block.instructions,
    terminator: Terminator::Jump(loop_header_block_id, body_updated_values), // 跳回循环头块并传递更新后的值
  }

  // 将更新后的循环体块添加回上下文
  let context_with_updated_body = add_block_to_context(
    body_context_final, updated_loop_body_block,
  )

  // 创建循环退出块 - 接收循环结束时变量的最终值
  let loop_exit_params = []
  for var_name in modified_vars.keys() {
    match modified_vars.get(var_name) {
      Some(original_value) => {
        let param_value = Value::{ id: new_value_id(), ty: original_value.ty }
        loop_exit_params.push(param_value)
      }
      None => ()
    }
  }
  let loop_exit_block = BasicBlock::{
    id: loop_exit_block_id,
    params: loop_exit_params, // 接收循环结束时变量的最终值
    instructions: [],
    terminator: Terminator::Return(None), // 临时设置
  }

  // 将循环退出块添加到上下文
  let context_with_exit = add_block_to_context(
    context_with_updated_body, loop_exit_block,
  )

  // 为退出块创建变量环境映射
  let mut exit_var_env = context_with_updated_body.var_env
  let var_names = modified_vars.keys().to_array()
  for i = 0; i < var_names.length() && i < loop_exit_params.length(); i = i + 1 {
    let var_name = var_names[i]
    exit_var_env = exit_var_env.add(var_name, loop_exit_params[i])
  }

  // 切换到循环退出块，准备继续后续代码
  let final_context = update_current_block(context_with_exit, loop_exit_block)
  let final_context_with_var_env = update_var_env(final_context, exit_var_env) // 使用退出块的变量环境

  // While循环返回Unit类型
  ExprResult::{ value: None, context: final_context_with_var_env }
}
