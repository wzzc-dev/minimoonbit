///|
fn emit_args(
  args : Array[@typing.Name],
  env : Env,
  instrs : Array[RvAsm],
) -> Unit {
  for i, arg in args {
    if i < reg_arg_list.length() {
      match env.vars.get(arg.to_string()) {
        Some((offset, Double)) =>
          instrs.push(Fld(freg_arg_list.get(i).unwrap(), { base: Fp, offset }))
        Some((offset, _)) =>
          instrs.push(Ld(reg_arg_list.get(i).unwrap(), { base: Fp, offset }))
        None => {
          // 如果是函数名，需要特殊处理
          let def_index = env.fundefs.search_by(fn(fundef) {
            fundef.name.inner() == arg.to_string()
          })
          match def_index {
            Some(index) => {
              let fundef = env.fundefs.get(index).unwrap()
              instrs.push(La(reg_arg_list.get(i).unwrap(), fundef.name.inner()))
            }
            None =>
              // 如果找不到函数定义，可能是外部函数
              instrs.push(La(reg_arg_list.get(i).unwrap(), arg.to_string()))
          }
        }
      }
    } else {
      let offset = env.vars.get(arg.to_string()).unwrap().0
      let stack_offset = (i - reg_arg_list.length()) * 8
      // 超出寄存器数量的参数存入栈
      match env.find_type(arg.to_string()) {
        Double => {
          instrs.push(Fld(Ft0, { base: Fp, offset }))
          instrs.push(Fsd(Ft0, { base: Sp, offset: stack_offset }))
        }
        _ => {
          instrs.push(Ld(T0, { base: Fp, offset }))
          instrs.push(Sd(T0, { base: Sp, offset: stack_offset }))
        }
      }
    }
  }
}
