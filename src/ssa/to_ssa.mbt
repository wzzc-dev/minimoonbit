///| 将闭包IR转换为SSA形式
///|
///| 使用基本块参数来实现SSA
///|
/// 将闭包IR程序转换为SSA程序
pub fn to_ssa(input : @closure.Program) -> Ssa {

  // @util.logger("closure ir: \n" + input.to_json().stringify())
  // 初始化SSA程序
  let functions = []

  // 转换每个函数定义
  for fundef in input.fundefs {
    if not(@typing.extenv.contains(fundef.old_name.to_string())) {
      let block_id = new_block_id()
      let ssa_func = convert_function(block_id, fundef, functions)
      // @util.logger("convert_function: " + ssa_func.to_json().stringify())
      functions.push(ssa_func)
    }
  }

  // 转换主函数体
  let main_func = convert_main_function(input.body, functions)
  functions.push(main_func)

  { program: { functions, static_arrays: input.static_arrays } }
}
