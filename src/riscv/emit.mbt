///|
pub fn emit(input : @closure.Program) -> Array[AssemblyFunction] {
  // for fundef in input.fundefs {
  //   if extenv.contains(fundef.name.inner()) {
  //     continue
  //   }
  //   // if fundef.name.inner() == "loop2" {
  //   println("fundef: " + fundef.to_string())
  //   // }
  // }
  // println("minimbt_main: " + input.body.to_json().stringify())
  let functions = []
  for static_array in input.static_arrays {
    
    fn get_elems(name: String, arr : Array[@closure.LowTypeValue]) {
      let body = []
      let elems = []
      for i, elem in arr {
        match elem {
          DoubleValue(d) => elems.push(d.to_string())
          IntValue(i) => elems.push(i.to_string())
          PtrValue(a) => {
            get_elems(name + "_" + i.to_string(), a)
            elems.push(name + "_" + i.to_string())
          }
        }
      }
      if elems.length() > 0 {
        match arr[0] {
          PtrValue(_) => {
            body.push(Data(".dword", elems))
          }
          IntValue(_) => {
            body.push(Data(".word", elems))
          }
          DoubleValue(_) => {
            body.push(Data(".double", elems))
          }
        }
      }
      functions.push({
        name: name,
        asm_export: false,
        body,
      })
    }

    get_elems(static_array.label.0, static_array.elements)
  }

  // 为每个函数定义生成汇编代码
  for fundef in input.fundefs {
    if extenv.contains(fundef.name.0) {
      continue
    }
    let body = emit_fun(fundef, input.fundefs)
    functions.push({ name: fundef.name.0, asm_export: false, body })
  }

  // 主函数
  let main = []
  let main_framesize = calculate_framesize_expr(input.body) + 24 // 增加主函数的栈帧大小

  // 主函数序言
  main.push(Addi(Sp, Sp, -main_framesize)) // allocate stack frame
  main.push(Sd(Ra, { base: Sp, offset: main_framesize - 8 })) // store return address
  main.push(Sd(Fp, { base: Sp, offset: main_framesize - 16 }))
  main.push(Addi(Fp, Sp, main_framesize))

  // 编译主体
  let main_env = {
    vars: @immut/hashmap.new(),
    current_offset: -24,
    fundefs: input.fundefs,
  }
  main.append(compile_expr(input.body, main_env))

  // 主函数尾声
  main.push(Ld(Ra, { base: Sp, offset: main_framesize - 8 }))
  main.push(Ld(Fp, { base: Sp, offset: main_framesize - 16 }))
  main.push(Addi(Sp, Sp, main_framesize))
  main.push(Ret)
  functions.push({ name: "minimbt_main", asm_export: true, body: main })
  functions
}

///|
fn emit_fun(
  fundef : @closure.FuncDef,
  fundefs : Array[@closure.FuncDef],
) -> Array[RvAsm] {
  let body = []
  let framesize = calculate_framesize(fundef)
  // Ensure 16-byte stack alignment
  let aligned_framesize = (framesize + 15) / 16 * 16

  // 函数序言
  // 分配栈空间
  body.push(Addi(Sp, Sp, -aligned_framesize))
  // 保存返回地址
  body.push(Sd(Ra, { base: Sp, offset: aligned_framesize - 8 }))
  // 保存帧指针
  body.push(Sd(Fp, { base: Sp, offset: aligned_framesize - 16 }))

  // 更新帧指针
  body.push(Addi(Fp, Sp, aligned_framesize))

  let mut env = {
    // 保存参数
    vars: @immut/hashmap.new(),
    current_offset: -24,
    fundefs,
  }
  // 如果是闭包函数，先处理自由变量
  if fundef.is_closure {
    let offset = env.current_offset
    body.push(Sd(S11, { base: Fp, offset }))
    env = env.add(fundef.old_name.to_string(), offset, fundef.ty)
    env.current_offset -= 8
    for i, arg in fundef.formal_free_vars {
      // 从闭包对象(s11)中加载自由变量，偏移为8*i+8 (第一个8字节是函数指针)
      body.push(Ld(T0, { base: S11, offset: (i + 1) * 8 }))
      // 保存到栈上
      let offset = env.current_offset
      body.push(Sd(T0, { base: Fp, offset }))
      env = env.add(arg.0.to_string(), offset, arg.1)
      env.current_offset -= 8
    }
  }
  // 处理普通参数
  for i, arg in fundef.args {
    if i < reg_arg_list.length() {
      let offset = env.current_offset
      match arg.1 {
        Double =>
          // 浮点参数使用浮点寄存器和指令
          body.push(Fsd(freg_arg_list.get(i).unwrap(), { base: Fp, offset }))
        _ =>
          // 其他类型使用通用寄存器和指令
          body.push(Sd(reg_arg_list.get(i).unwrap(), { base: Fp, offset }))
      }
      env = env.add(arg.0.to_string(), offset, arg.1)
      env.current_offset -= 8
    } else {
      // 如果参数超过8个，则需要从调用者栈帧中读取
      let offset = env.current_offset
      // 修正：溢出参数位于调用者栈帧中，在当前帧指针之上
      let stack_offset = aligned_framesize + (i - reg_arg_list.length()) * 8
      
      match arg.1 {
        Double => {
          // 浮点参数使用浮点寄存器和指令
          body.push(Fld(Ft0, { base: Sp, offset: stack_offset }))
          body.push(Fsd(Ft0, { base: Fp, offset }))
        }
        _ => {
          // 其他类型使用通用寄存器和指令
          body.push(Ld(T0, { base: Sp, offset: stack_offset }))
          body.push(Sd(T0, { base: Fp, offset }))
        }
      }
      env = env.add(arg.0.to_string(), offset, arg.1)
      env.current_offset -= 8
    }
  }

  // 编译函数体
  body.append(compile_expr(fundef.body, env))
  body.push(Ld(Ra, { base: Sp, offset: aligned_framesize - 8 }))
  body.push(Ld(Fp, { base: Sp, offset: aligned_framesize - 16 }))
  body.push(Addi(Sp, Sp, aligned_framesize))
  body.push(Ret)
  body
}

///|
fn calculate_framesize(fundef : @closure.FuncDef) -> Int {
  // 基础大小：返回地址 + 帧指针 + 调用者保存寄存器 + 参数 + 局部变量
  let base_size = 24 // Ra + Fp
  let args_size = fundef.args.length() * 8
  let fv_size = fundef.formal_free_vars.length() * 8
  let locals_size = calculate_framesize_expr(fundef.body)
  return base_size + args_size + fv_size + locals_size
}

///|
fn calculate_framesize_expr(expr : @closure.Expr) -> Int {
  match expr {
    IfEq(_, _, e1, e2) => {
      let size1 = calculate_framesize_expr(e1)
      let size2 = calculate_framesize_expr(e2)
      @cmp.maximum(size1, size2)
    }
    IfLe(_, _, e1, e2) => {
      let size1 = calculate_framesize_expr(e1)
      let size2 = calculate_framesize_expr(e2)
      @cmp.maximum(size1, size2)
    }
    Let((_name, _), e1, e2) => {
      let size1 = calculate_framesize_expr(e1)
      let size2 = calculate_framesize_expr(e2)
      @cmp.maximum(size1, size2) + 8
    }
    Var(_) => 0
    MakeClosure((_name, _ty), _, e) => {
      // 需要考虑：
      // 1. malloc调用的参数空间 (48字节)
      // 2. 闭包对象本身的大小 (8 + free_vars.length * 8)
      // 3. 后续表达式e的空间
      // 4. 闭包变量存储空间 (8字节)

      let malloc_space = 48 // RISC-V调用约定
      let expr_space = calculate_framesize_expr(e)
      let var_space = 8 // 存储闭包指针的空间
      // println("MakeClosure: " + _name.to_string())
      // println("MakeClosure expr_space: " + expr_space.to_string())
      // 取malloc所需空间和表达式空间的较大值，加上闭包变量的存储空间
      @cmp.maximum(malloc_space, expr_space) + var_space
    }
    CallClosure(_, args) =>
      // RISC-V调用约定要求参数区域至少48字节
      // println("CallClosure args: " + ((args.length() + 1) * 8).to_string())
      @cmp.maximum(48, (args.length() + 1) * 8) // +1 为闭包对象本身预留空间
    CallDirect(_, args) =>
      // println("CallDirect args: " + (args.length() * 8).to_string())
      @cmp.maximum(48, args.length() * 8) // 同样遵循48字节最小值
    MakeTuple(elems) => elems.length() * 8 // 每个元素8字节
    LetTuple(names_tys, _, e) =>
      names_tys.length() * 8 + calculate_framesize_expr(e)
    ArrayGet(_, _) => 16
    ArrayPut(_, _, _) => 16
    ExternalArray(_) => 8
    _ => 0
  }
}

///|
pub(all) struct AssemblyFunction {
  name : String
  asm_export : Bool
  body : Array[RvAsm]
}

///|
pub fn AssemblyFunction::output(
  self : AssemblyFunction,
  logger : &Logger,
) -> Unit {
  let name = self.name
  if self.asm_export {
    logger.write_string(".global \{name}\n")
  }
  logger.write_string("\{name}:\n")
  for rv_asm in self.body {
    Show::output(rv_asm, logger)
    logger.write_string("\n")
  }
}

// 添加一个环境结构来跟踪变量位置

///|
pub struct Env {
  vars : @immut/hashmap.HashMap[String, (Int, @closure.LowType)] // 变量名到栈偏移的映射
  mut current_offset : Int // 当前可用的栈偏移
  fundefs : Array[@closure.FuncDef] // 函数定义
}

///|
fn find_type(self : Env, key : String) -> @closure.LowType {
  self.vars.get(key).unwrap().1
}

///|
fn add(
  self : Env,
  name : String,
  offset : Int,
  lowtype : @closure.LowType,
) -> Env {
  let vars = self.vars.add(name.to_string(), (offset, lowtype))
  Env::{ vars, current_offset: self.current_offset, fundefs: self.fundefs }
}

///|
fn Env::varOffset(env : Env, name : @typing.Name) -> Int {
  env.vars.get(name.to_string()).unwrap().0
}

///|
fn compile_expr(expr : @closure.Expr, env : Env) -> Array[RvAsm] {
  let mut env = env
  let instrs = []
  match expr {
    EnumConstructor(_) => @util.die("compile_expr not supported")
    Unit => instrs.clear()
    Int(i) => instrs.push(Li(reg_ret, i.to_string()))
    Int64(i) => instrs.push(Li(reg_ret, i.to_string()))
    Double(d) => {
      let bits = d.reinterpret_as_int64()
      instrs.push(Li(T0, bits.to_string()))
      // instrs.push(FcvtDl(freg_ret, T0))
      instrs.push(FmvDX(freg_ret, T0))

    }
    Neg(x) => {
      instrs.push(Ld(T0, { base: Fp, offset: Env::varOffset(env, x) }))
      instrs.push(Neg(reg_ret, T0))
    }
    Add(x, y) | Sub(x, y) | Mul(x, y) | Div(x, y) => {
      instrs.push(Ld(T0, { base: Fp, offset: Env::varOffset(env, x) }))
      instrs.push(Ld(T1, { base: Fp, offset: Env::varOffset(env, y) }))
      match expr {
        Add(_) => instrs.push(Add(reg_ret, T0, T1))
        Sub(_) => instrs.push(Sub(reg_ret, T0, T1))
        Mul(_) => instrs.push(Mul(reg_ret, T0, T1))
        Div(_) | _ => instrs.push(Div(reg_ret, T0, T1))
      }
    }
    Mod(x, y) => {
      instrs.push(Ld(T0, { base: Fp, offset: Env::varOffset(env, x) }))
      instrs.push(Ld(T1, { base: Fp, offset: Env::varOffset(env, y) }))
      instrs.push(Rem(reg_ret, T0, T1))
    }
    FMod(_x, _y) => @util.die("FMod not supported")
    FNeg(x) => {
      instrs.push(Fld(Ft0, { base: Fp, offset: Env::varOffset(env, x) }))
      instrs.push(FnegD(freg_ret, Ft0))
    }
    FAdd(x, y) | FSub(x, y) | FMul(x, y) | FDiv(x, y) => {
      instrs.push(Fld(Ft0, { base: Fp, offset: Env::varOffset(env, x) }))
      instrs.push(Fld(Ft1, { base: Fp, offset: Env::varOffset(env, y) }))
      match expr {
        FAdd(_) => instrs.push(FaddD(freg_ret, Ft0, Ft1))
        FSub(_) => instrs.push(FsubD(freg_ret, Ft0, Ft1))
        FMul(_) => instrs.push(FmulD(freg_ret, Ft0, Ft1))
        FDiv(_) => instrs.push(FdivD(freg_ret, Ft0, Ft1))
        _ => @util.die("FDiv not supported")
      }
    }
    IfEq(x, y, e1, e2) => {
      instrs.push(Ld(T0, { base: Fp, offset: Env::varOffset(env, x) }))
      instrs.push(Ld(T1, { base: Fp, offset: Env::varOffset(env, y) }))
      // 相等比较分支
      let label_else = gen_label("else")
      let label_end = gen_label("end")
      instrs.push(Bne(T0, T1, label_else))
      instrs.append(compile_expr(e1, env))
      instrs.push(J(label_end))
      instrs.push(Label(label_else.inner()))
      instrs.append(compile_expr(e2, env))
      instrs.push(Label(label_end.inner()))
    }
    IfLe(x, y, e1, e2) => {
      instrs.push(Ld(T0, { base: Fp, offset: Env::varOffset(env, x) }))
      instrs.push(Ld(T1, { base: Fp, offset: Env::varOffset(env, y) }))
      // 小于等于比较分支
      let label_else = gen_label("else")
      let label_end = gen_label("end")
      instrs.push(Bgt(T0, T1, label_else))
      instrs.append(compile_expr(e1, env))
      instrs.push(J(label_end))
      instrs.push(Label(label_else.inner()))
      instrs.append(compile_expr(e2, env))
      instrs.push(Label(label_end.inner()))
    }
    IfLt(x, y, e1, e2) => {
      instrs.push(Ld(T0, { base: Fp, offset: Env::varOffset(env, x) }))
      instrs.push(Ld(T1, { base: Fp, offset: Env::varOffset(env, y) }))
      // 小于比较分支
      let label_else = gen_label("else")
      let label_end = gen_label("end")
      instrs.push(Bge(T0, T1, label_else))
      instrs.append(compile_expr(e1, env))
      instrs.push(J(label_end))
      instrs.push(Label(label_else.inner()))
      instrs.append(compile_expr(e2, env))
      instrs.push(Label(label_end.inner()))
    }
    While(cond, body) => {
      // @util.logger("While loop: cond:" + cond.to_string() + ", \n body: " + body.to_string())
      // Generate labels for loop control
      let label_start = gen_label("while_start")
      let label_end = gen_label("while_end")

      // Start of loop
      instrs.push(Label(label_start.inner()))

      // Compile condition expression
      instrs.append(compile_expr(cond, env))

      // Check if condition is false (assuming condition result is in reg_ret)
      // If reg_ret is 0 (false), jump to end
      instrs.push(Beq(reg_ret, Zero, label_end))

      // Compile loop body
      instrs.append(compile_expr(body, env))

      // Jump back to start of loop
      instrs.push(J(label_start))

      // End of loop label
      instrs.push(Label(label_end.inner()))

      // While loops return Unit, so set reg_ret to 0
      instrs.push(Li(reg_ret, "0"))
    }
    Let((name, ty), e1, e2) => {
      // 计算 e1
      instrs.append(compile_expr(e1, env))
      if not(name.to_string() == "_" && ty == Unit) {
        let offset = env.current_offset
        match ty {
          Double => instrs.push(Fsd(freg_ret, { base: Fp, offset }))
          _ => instrs.push(Sd(reg_ret, { base: Fp, offset }))
        }
        env = env.add(name.to_string(), offset, ty)
        // 更新环境
        env.current_offset -= 8
      }
      // 计算 e2,使用更新后的环境
      instrs.append(compile_expr(e2, env))
    }
    Var(name) =>
      // 从环境中查找变量的偏移
      match env.vars.get(name.to_string()) {
        Some((offset, ty)) =>
          match ty {
            Double => instrs.push(Fld(freg_ret, { base: Fp, offset }))
            _ => instrs.push(Ld(reg_ret, { base: Fp, offset }))
          }
        None => instrs.push(La(reg_ret, name.to_string()))
      }
    MakeClosure((name, ty), closure, e) =>
      emit_make_closure(name, ty, closure, e, instrs, env)
    CallClosure(f, args) => emit_call_closure(f, args, instrs, env)
    CallDirect(label, args) => emit_call_direct(label, args, instrs, env)
    MakeTuple(elems) => emit_make_tuple(elems, instrs, env)
    LetTuple(names, tuple, e) => emit_let_tuple(names, tuple, e, instrs, env)
    TupleGet(tuple, ty, index) => emit_tuple_get(tuple, ty, index, instrs, env)
    ArrayGet(array, index) => emit_array_get(array, index, instrs, env)
    ArrayPut(array, index, value) =>
      emit_array_put(array, index, value, instrs, env)
    ExternalArray(label) => instrs.push(La(reg_ret, label.0))
    StaticArrayRef(label) => instrs.push(La(reg_ret, label.0))
    ExternalFunctionApplication(label, xs) => {
      emit_args(xs, env, instrs)
      instrs.push(Call(Label(label.0)))
    }
    Assign(x, y) => {
      instrs.push(Ld(T0, { base: Fp, offset: Env::varOffset(env, y) }))
      instrs.push(Sd(T0, { base: Fp, offset: Env::varOffset(env, x) }))
    }
  }
  instrs
}

///|
fn emit_call_direct(
  label : @closure.Label,
  args : Array[@typing.Name],
  instrs : Array[RvAsm],
  env : Env,
) -> Unit {
  emit_args(args, env, instrs)
  instrs.push(Call(Label(label.0)))
}

///|
fn emit_make_tuple(
  elems : Array[@typing.Name],
  instrs : Array[RvAsm],
  env : Env,
) -> Unit {
  // 1. 分配元组空间
  let size = elems.length() * 8
  instrs.push(Li(A0, size.to_string()))
  instrs.push(Call(Label("minimbt_malloc"))) // 使用堆分配

  // 2. 存储元素
  for i, elem in elems {
    // instrs.push(Comment("start : 存储元素：" + i.to_string() + "; name:" + elem.to_string()))
    instrs.push(Ld(T1, { base: Fp, offset: Env::varOffset(env, elem) }))
    // @util.logger("emit_make_tuple:" + elem.to_string())
    instrs.push(Sd(T1, { base: A0, offset: i * 8 }))
    // instrs.push(Comment("end : 存储元素：" + i.to_string() + "; name:" + elem.to_string()))
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
  ty : @closure.LowType,
  index : Int,
  instrs : Array[RvAsm],
  env : Env,
) -> Unit {
  instrs.push(Ld(T0, { base: Fp, offset: Env::varOffset(env, tuple) }))
  match ty {
    Double => {
      instrs.push(Fld(freg_ret, { base: T0, offset: index * 8 }))
    }
    _ => {
      instrs.push(Ld(reg_ret, { base: T0, offset: index * 8 }))
    }
  }
}



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
    instrs.push(La(reg_ret, closure.name.0))
  } else {
    // 有自由变量，创建闭包对象
    // 1. 计算需要的内存大小 (函数指针 + 自由变量)
    let size = @cmp.maximum(16, 8 + closure.actual_free_vars.length() * 8)

    // 2. 调用 malloc 分配内存
    instrs.push(Li(A0, size.to_string()))
    instrs.push(Call(Label("minimbt_malloc")))

    // 3. 存储函数指针
    instrs.push(La(T0, closure.name.0))
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
          fundef.name.0 == f.to_string()
        }) {
        Some(_) => ()
        None =>
          @util.logger("Warning: CallClosure: " + f.to_string() + " not found")
      }
  }
  instrs.push(Ld(T1, { base: S11, offset: 0 }))
  instrs.push(Jalr(T1))
}

///|
fn emit_array_get(
  array : @typing.Name,
  index : @typing.Name,
  instrs : Array[RvAsm],
  env : Env,
) -> Unit {
  // @util.logger("emit_array_get: " + array.to_string()+ ", env: " +  env.vars.to_string())
  // 1. 加载数组基地址 里面保存的是数组的指针
  instrs.push(Ld(T0, { base: Fp, offset: Env::varOffset(env, array) }))
  // 2. 加载索引值并根据类型计算偏移
  instrs.push(Ld(T1, { base: Fp, offset: Env::varOffset(env, index) }))
  let arr_ty = get_array_element_type(array, env)
  match arr_ty {
    Int(_) => {
      instrs.push(Slli(T1, T1, 2))
    }
    _ => {
      instrs.push(Slli(T1, T1, 3))
    }
  }
  // 3. 计算最终地址
  instrs.push(Add(T0, T0, T1))
  // 4. 根据数组元素类型选择加载指令
  match get_array_element_type(array, env) {
    Double => instrs.push(Fld(freg_ret, { base: T0, offset: 0 }))
    Int => instrs.push(Lw(reg_ret, { base: T0, offset: 0 }))
    DirectFn(_, _) | ClosureFn(_, _) => instrs.push(Mv(reg_ret, T0)) // 函数指针用 Mv
    _ => instrs.push(Ld(reg_ret, { base: T0, offset: 0 })) // 其他类型默认用 Ld
  }
  // @util.logger("emit_array_get end")
}

///|
fn emit_array_put(
  array : @typing.Name,
  index : @typing.Name,
  value : @typing.Name,
  instrs : Array[RvAsm],
  env : Env
) -> Unit {
  // instrs.push(Comment("emit_array_put:" + array.to_string() + " " + index.to_string() + " " + value.to_string()))
  // - 1. 从栈上加载数组的基地址（这个地址是指向堆上数组的指针）
  instrs.push(Ld(T0, { base: Fp, offset: Env::varOffset(env, array) }))

  // - 2. 计算元素的偏移量
  instrs.push(Ld(T1, { base: Fp, offset: Env::varOffset(env, index) }))
  let arr_ty = get_array_element_type(array, env)
  match arr_ty {
    Int(_) => {
      instrs.push(Slli(T1, T1, 2))
    }
    _ => {
      instrs.push(Slli(T1, T1, 3))
    }
  }
  // - 3. 计算元素在堆上的实际地址
  instrs.push(Add(T0, T0, T1))
  // 4. 加载并存储值
  let value_offset = env.vars.get(value.to_string()).unwrap().0
  match arr_ty {
    Double => {
      instrs.push(Fld(Ft0, { base: Fp, offset: value_offset }))
      instrs.push(Fsd(Ft0, { base: T0, offset: 0 }))
    }
    Int => {
      instrs.push(Lw(T2, { base: Fp, offset: value_offset }))
      instrs.push(Sw(T2, { base: T0, offset: 0 }))
    }
    _ => {
      instrs.push(Ld(T2, { base: Fp, offset: value_offset }))
      instrs.push(Sd(T2, { base: T0, offset: 0 }))
    }
  }
  // instrs.push(Comment("emit_array_put end"))
}

// 添加一个辅助函数来获取数组元素类型
///|
fn get_array_element_type(array : @typing.Name, env : Env) -> @closure.LowType {
  match env.find_type(array.to_string()) {
    Array(elem_type) => elem_type
    Ptr => Ptr
    _ =>
      @util.die(
        "get array element type error " +
        array.to_string() +
        "\n " +
        env.find_type(array.to_string()).to_string(),
      )
  }
}

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
            fundef.name.0 == arg.to_string()
          })
          match def_index {
            Some(index) => {
              let fundef = env.fundefs.get(index).unwrap()
              instrs.push(La(reg_arg_list.get(i).unwrap(), fundef.name.0))
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

///|
pub let extenv = [
  "read_int", "print_int", "print_float", "read_char", "print_char", "print_newline", "print_endline",
  "int_of_float", "float_of_int", "truncate", "floor", "abs_float", "sqrt", "sin",
  "cos", "atan", "create_array", "create_float_array", "create_ptr_array",
]

///|
let default_counter : Ref[Int] = { val: 0 }

///|
fn gen_label(name : String, counter? : Ref[Int] = default_counter) -> Label {
  counter.val = counter.val + 1
  Label("label_" + name + "_" + counter.val.to_string())
}
