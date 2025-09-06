
///|
fn emit_make_closure(
  name : @typing.Name,
  ty : @closure.LowType,
  closure : @closure.Closure,
  e : @closure.Expr,
  instrs : Array[RvAsm],
  env : Env,
) -> Unit {
  let status = env.vars.get(name.to_string()) is Some(_) &&
    closure.actual_free_vars.is_empty()
  if status {
    // 没有自由变量，直接返回函数地址
    instrs.push(La(reg_ret, closure.name.inner()))
  } else {
    // 有自由变量，创建闭包对象
    // 1. 计算需要的内存大小 (函数指针 + 自由变量)
    let size = @cmp.maximum(16, 8 + closure.actual_free_vars.length() * 8)

    // 2. 调用 malloc 分配内存
    instrs.push(Li(A0, size.to_string()))
    instrs.push(Call(Label("minimbt_malloc")))

    // 3. 存储函数指针
    instrs.push(La(T0, closure.name.inner()))
    instrs.push(Sd(T0, { base: reg_ret, offset: 0 }))

    // 4. 存储捕获的变量
    for i, env_var in closure.actual_free_vars {
      match env.vars.get(env_var.to_string()) {
        Some((offset, _)) => {
          instrs.push(Ld(T0, { base: Fp, offset }))
          instrs.push(Sd(T0, { base: reg_ret, offset: (i + 1) * 8 }))
        }
        None =>
          @util.logger(
            "Warning: Free variable not found in environment: " +
            "name: " +
            name.to_string() +
            " env: " +
            env_var.to_string(),
          )
      }
    }
  }
  // 将函数地址保存到栈
  let offset = env.current_offset
  instrs.push(Sd(reg_ret, { base: Fp, offset }))

  // 更新环境
  let env = env.add(name.to_string(), offset, ty)
  env.current_offset -= 8

  // 编译剩余表达式
  instrs.append(compile_expr(e, env))
}
///|
fn emit_call_closure(
  f : @typing.Name,
  args : Array[@typing.Name],
  instrs : Array[RvAsm],
  env : Env,
) -> Unit {
  emit_args(args, env, instrs)
  match env.vars.get(f.to_string()) {
    Some((offset, _)) => instrs.push(Ld(S11, { base: Fp, offset }))
    None =>
      match
        env.fundefs.search_by(fn(fundef) {
          fundef.name.inner() == f.to_string()
        }) {
        Some(_) => ()
        None =>
          @util.logger("Warning: CallClosure: " + f.to_string() + " not found")
      }
  }
  instrs.push(Ld(T1, { base: S11, offset: 0 }))
  instrs.push(Jalr(T1))
}