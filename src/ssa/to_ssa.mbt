///| 将闭包IR转换为SSA形式

///|

///| 使用基本块参数来实现SSA

///|
/// 将闭包IR程序转换为SSA程序
pub fn to_ssa(input : @closure.Program) -> Ssa {

  // @util.logger("closure ir: \n" + input.to_json().stringify())
  // 初始化SSA程序
  let functions = []

  // 预先创建函数类型环境，以支持相互递归函数
  let mut func_env = @immut/hashmap.new()
  for fundef in input.fundefs {
    if not(@typing.extenv.contains(fundef.old_name.to_string())) {
      func_env = func_env.add(
        fundef.name.0.to_string(),
        convert_type(fundef.ty),
      )
    }
  }

  // 转换每个函数定义
  for fundef in input.fundefs {
    if not(@typing.extenv.contains(fundef.old_name.to_string())) {
      let block_id = new_block_id()
      let ssa_func = try convert_function_with_env(block_id, fundef, func_env) catch {
        e => @util.die("Error converting function " + fundef.name.0.to_string() + ": " + e.to_string())
      }
      // @util.logger("convert_function: " + ssa_func.to_json().stringify())
      functions.push(ssa_func)
    }
  }

  // 转换主函数体
  let main_func = try convert_main_function(input.body, functions) catch {
    e => @util.die("Error converting main function: " + e.to_string())
  }
  functions.push(main_func)
  { program: { functions, static_arrays: input.static_arrays } }
}
