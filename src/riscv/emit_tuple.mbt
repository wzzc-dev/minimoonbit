///|
fn emit_make_tuple(
  elems : Array[@typing.Name],
  instrs : Array[RvAsm],
  env : Env,
) -> Unit {
  instrs.push(Comment("emit_make_tuple:" + elems.to_string()))
  // 1. 分配元组空间
  let size = elems.length() * 8
  instrs.push(Li(A0, size.to_string()))
  instrs.push(Call(Label("minimbt_malloc"))) // 使用堆分配

  // 2. 存储元素
  for i, elem in elems {
    instrs.push(Comment("start : 存储元素：" + i.to_string() + "; name:" + elem.to_string()))
    instrs.push(Ld(T1, { base: Fp, offset: Env::varOffset(env, elem) }))
    // @util.logger("emit_make_tuple:" + elem.to_string())
    // debug(T1, instrs)
    instrs.push(Sd(T1, { base: A0, offset: i * 8 }))
    instrs.push(Comment("end : 存储元素：" + i.to_string() + "; name:" + elem.to_string()))
  }
}

///|
fn emit_let_tuple(
  names : Array[(@typing.Name, @closure.LowType)],
  tuple : @typing.Name,
  e : @closure.Expr,
  instrs : Array[RvAsm],
  env : Env,
) -> Unit {
  let mut env = env
  // 元组解构
  // 从元组加载各个字段
  instrs.push(Ld(T0, { base: Fp, offset: Env::varOffset(env, tuple) }))
  for i, name_ty in names {
    instrs.push(Ld(T1, { base: T0, offset: i * 8 }))
    instrs.push(Sd(T1, { base: Fp, offset: env.current_offset }))
    env = env.add(name_ty.0.to_string(), env.current_offset, name_ty.1)
    env.current_offset -= 8
  }
  instrs.append(compile_expr(e, env))
}

///|
fn emit_tuple_get(
  tuple : @typing.Name,
  index : Int,
  instrs : Array[RvAsm],
  env : Env,
) -> Unit {
  instrs.push(Ld(T0, { base: Fp, offset: Env::varOffset(env, tuple) }))
  instrs.push(Ld(reg_ret, { base: T0, offset: index * 8 }))
}

///|
fn _debug(reg : Reg, instrs : Array[RvAsm]) -> Unit {
  instrs.push(Comment("debug: 元组元素 start print"))
  instrs.push(Mv(T6, A0))
  
  instrs.push(Lw(A0, { base: reg, offset: 0 }))
  instrs.push(Call("minimbt_print_int"))
  instrs.push(Lw(A0, { base: reg, offset: 4 }))
  instrs.push(Call("minimbt_print_int"))
  instrs.push(Lw(A0, { base: reg, offset: 8 }))
  instrs.push(Call("minimbt_print_int"))
  instrs.push(Mv(A0, T6))
  instrs.push(Comment("debug: 元组元素 end print"))
}
