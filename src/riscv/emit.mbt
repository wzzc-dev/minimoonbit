///|
pub fn emit(input : @closure.Program) -> Array[AssemblyFunction] {
  // for fundef in input.fundefs {
  //   if extenv.contains(fundef.name._) {
  //     continue
  //   }
  //   // if fundef.name._ == "loop2" {
  //   println("fundef: " + fundef.to_string())
  //   // }
  // }
  // println("minimbt_main: " + input.body.to_string())
  let functions = []

  // 为每个函数定义生成汇编代码
  for fundef in input.fundefs {
    // println("fundef: " + fundef.name._.to_string())
    if extenv.contains(fundef.name._) {
      continue
    }
    // println("fundef: " + fundef.to_string())
    let body = []
    let framesize = calculate_framesize(fundef)
    // + reg_callee_saved_list.length() * 8
    // println("framesize: " + framesize.to_string())
    // 函数序言
    // 分配栈空间
    body.push(Addi(Sp, Sp, -framesize))
    // 保存返回地址
    body.push(Sd(Ra, { base: Sp, offset: framesize - 8 }))
    // 保存帧指针
    body.push(Sd(Fp, { base: Sp, offset: framesize - 16 }))

    // 保存被调用者保存的寄存器
    for i, reg in reg_callee_saved_list {
      body.push(Sd(reg, { base: Sp, offset: framesize - (i + 3) * 8 }))
    }

    // 更新帧指针
    body.push(Addi(Fp, Sp, framesize))
    let env = {
      // 保存参数
      vars: Map::new(),
      current_offset: -24,
      // current_offset: -24 - reg_callee_saved_list.length() * 8, // 从-24开始，留出ra和fp的空间
      fundefs: input.fundefs,
    }
    // 如果是闭包函数，先处理自由变量
    if fundef.is_closure {
      for i, arg in fundef.formal_free_vars {
        // 从闭包对象(s11)中加载自由变量，偏移为8*i+8 (第一个8字节是函数指针)
        body.push(Ld(T0, { base: S11, offset: (i + 1) * 8 }))
        // 保存到栈上
        let offset = env.current_offset
        body.push(Sd(T0, { base: Fp, offset }))
        env.vars.set(arg.0.to_string(), (offset, arg.1))
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
        env.vars.set(arg.0.to_string(), (offset, arg.1))
        env.current_offset -= 8
      } else {
        // 如果参数超过8个，则需要从栈上读取
        let offset = env.current_offset
        let stack_offset = -(i - reg_arg_list.length() + 1) * 8
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
        env.vars.set(arg.0.to_string(), (offset, arg.1))
        env.current_offset -= 8
      }
    }

    // 编译函数体
    body.append(compile_expr(fundef.body, env))
    body.push(Ld(Ra, { base: Sp, offset: framesize - 8 }))
    body.push(Ld(Fp, { base: Sp, offset: framesize - 16 }))
    // 恢复被调用者保存的寄存器
    for i, reg in reg_callee_saved_list {
      body.push(Ld(reg, { base: Sp, offset: framesize - (i + 3) * 8 }))
    }
    body.push(Addi(Sp, Sp, framesize))
    body.push(Ret)
    functions.push({ name: fundef.name._, export: false, body })
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
    vars: Map::new(),
    current_offset: -24,
    fundefs: input.fundefs,
  }
  main.append(compile_expr(input.body, main_env))

  // 主函数尾声
  main.push(Ld(Ra, { base: Sp, offset: main_framesize - 8 }))
  main.push(Ld(Fp, { base: Sp, offset: main_framesize - 16 }))
  main.push(Addi(Sp, Sp, main_framesize))
  main.push(Ret)
  functions.push({ name: "minimbt_main", export: true, body: main })
  // println("functions: " + functions.to_string())
  functions
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
      @math.maximum(size1, size2)
    }
    IfLe(_, _, e1, e2) => {
      let size1 = calculate_framesize_expr(e1)
      let size2 = calculate_framesize_expr(e2)
      @math.maximum(size1, size2)
    }
    Let((_name, _), e1, e2) => {
      let size1 = calculate_framesize_expr(e1)
      let size2 = calculate_framesize_expr(e2)
      @math.maximum(size1, size2) + 8
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
      @math.maximum(malloc_space, expr_space) + var_space
    }
    CallClosure(_, args) =>
      // RISC-V调用约定要求参数区域至少48字节
      // println("CallClosure args: " + ((args.length() + 1) * 8).to_string())
      @math.maximum(48, (args.length() + 1) * 8) // +1 为闭包对象本身预留空间
    CallDirect(_, args) =>
      // println("CallDirect args: " + (args.length() * 8).to_string())
      @math.maximum(48, args.length() * 8) // 同样遵循48字节最小值
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
  export : Bool
  body : Array[RvAsm]
}

///|
pub fn AssemblyFunction::output(
  self : AssemblyFunction,
  logger : Logger
) -> Unit {
  let name = self.name
  if self.export {
    logger.write_string(".global \{name}\n")
  }
  logger.write_string("\{name}:\n")
  for asm in self.body {
    Show::output(asm, logger)
    logger.write_string("\n")
  }
}

// 添加一个环境结构来跟踪变量位置
///|
struct Env {
  vars : Map[String, (Int, @closure.LowType)] // 变量名到栈偏移的映射
  mut current_offset : Int // 当前可用的栈偏移
  fundefs : Array[@closure.FuncDef] // 函数定义
}

///|
fn Env::varOffset(env : Env, name : @typing.Name) -> Int {
  env.vars.get(name.to_string()).unwrap().0
}

///|
fn compile_expr(expr : @closure.Expr, env : Env) -> Array[RvAsm] {
  let instrs = [Comment(expr.to_string())]
  match expr {
    Unit => instrs.clear()
    Int(i) => instrs.push(Li(reg_ret, i.to_string()))
    Double(d) => {
      let bits = d.reinterpret_as_int64()
      instrs.push(Li(T0, bits.to_string()))
      instrs.push(FmvDX(freg_ret, T0))
    }
    Neg(x) => {
      instrs.push(Ld(T0, { base: Fp, offset: varOffset(env, x) }))
      instrs.push(Neg(reg_ret, T0))
    }
    Add(x, y) | Sub(x, y) | Mul(x, y) | Div(x, y) => {
      instrs.push(Ld(T0, { base: Fp, offset: varOffset(env, x) }))
      instrs.push(Ld(T1, { base: Fp, offset: varOffset(env, y) }))
      match expr {
        Add(_) => instrs.push(Add(reg_ret, T0, T1))
        Sub(_) => instrs.push(Sub(reg_ret, T0, T1))
        Mul(_) => instrs.push(Mul(reg_ret, T0, T1))
        Div(_) | _ => instrs.push(Div(reg_ret, T0, T1))
      }
    }
    FNeg(x) => {
      instrs.push(Fld(Ft0, { base: Fp, offset: varOffset(env, x) }))
      instrs.push(FnegD(freg_ret, Ft0))
    }
    FAdd(x, y) | FSub(x, y) | FMul(x, y) | FDiv(x, y) => {
      instrs.push(Fld(Ft0, { base: Fp, offset: varOffset(env, x) }))
      instrs.push(Fld(Ft1, { base: Fp, offset: varOffset(env, y) }))
      match expr {
        FAdd(_) => instrs.push(FaddD(freg_ret, Ft0, Ft1))
        FSub(_) => instrs.push(FsubD(freg_ret, Ft0, Ft1))
        FMul(_) => instrs.push(FmulD(freg_ret, Ft0, Ft1))
        FDiv(_) | _ => instrs.push(FdivD(freg_ret, Ft0, Ft1))
      }
    }
    IfEq(x, y, e1, e2) => {
      instrs.push(Ld(T0, { base: Fp, offset: varOffset(env, x) }))
      instrs.push(Ld(T1, { base: Fp, offset: varOffset(env, y) }))
      // 相等比较分支
      let label_else = gen_label("else")
      let label_end = gen_label("end")
      instrs.push(Bne(T0, T1, label_else))
      instrs.append(compile_expr(e1, env))
      instrs.push(J(label_end))
      instrs.push(Label(label_else._))
      instrs.append(compile_expr(e2, env))
      instrs.push(Label(label_end._))
    }
    IfLe(x, y, e1, e2) => {
      instrs.push(Ld(T0, { base: Fp, offset: varOffset(env, x) }))
      instrs.push(Ld(T1, { base: Fp, offset: varOffset(env, y) }))
      // println("A0: " + A0.to_string() + " A1: " + A1.to_string())
      // 小于等于比较分支
      let label_else = gen_label("else")
      let label_end = gen_label("end")
      instrs.push(Bgt(T0, T1, label_else))
      instrs.append(compile_expr(e1, env))
      instrs.push(J(label_end))
      instrs.push(Label(label_else._))
      instrs.append(compile_expr(e2, env))
      instrs.push(Label(label_end._))
    }
    Let((name, ty), e1, e2) => {
      // 计算 e1
      instrs.append(compile_expr(e1, env))
      if not(name.to_string() == "_" && ty == Unit) {
        // let size = getTypeSize(ty) // TODO: 计算需要优化
        let offset = env.current_offset
        match ty {
          Double => instrs.push(Fsd(freg_ret, { base: Fp, offset }))
          DirectFn(_, _) => instrs.push(Sd(reg_ret, { base: Fp, offset }))
          ClosureFn(_, _) => instrs.push(Sd(reg_ret, { base: Fp, offset }))
          _ => instrs.push(Sd(reg_ret, { base: Fp, offset }))
        }
        env.vars.set(name.to_string(), (offset, ty))
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
            Double =>
              // println("Var Double: " + name.to_string())
              instrs.push(Fld(freg_ret, { base: Fp, offset }))
            _ => instrs.push(Ld(reg_ret, { base: Fp, offset }))
          }
        None =>
          // 如果在环境中找不到，可能是外部函数或全局函数
          instrs.push(La(reg_ret, name.to_string()))
      }
    MakeClosure((name, _ty), closure, e) => {

      // 1. 计算需要的内存大小 (函数指针 + 自由变量)
      let size = 8 + closure.actual_free_vars.length() * 8

      // 2. 调用 malloc 分配内存
      instrs.push(Li(A0, size.to_string()))
      instrs.push(Call(Label("minimbt_malloc")))

      // 3. 存储函数指针
      instrs.push(La(T0, closure.name._))
      instrs.push(Sd(T0, { base: reg_ret, offset: 0 }))

      // 4. 存储捕获的变量
      for i, var in closure.actual_free_vars {
        match env.vars.get(var.to_string()) {
          Some((offset, _)) => {
            instrs.push(Ld(T0, { base: Fp, offset }))
            instrs.push(Sd(T0, { base: reg_ret, offset: (i + 1) * 8 }))
          }
          None =>
            println(
              "Warning: Free variable not found in environment: " +
              var.to_string(),
            )
        }
      }

      // 5. 将闭包指针保存到栈
      let offset = env.current_offset
      instrs.push(Sd(reg_ret, { base: Fp, offset }))

      // 6. 更新环境
      env.vars.set(name.to_string(), (offset, _ty))
      env.current_offset -= 8

      // 7. 编译剩余表达式，使用新环境
      instrs.append(compile_expr(e, env))
    }
    CallClosure(f, args) => {
      for i, arg in args {
        let arg_type = get_var_type(arg, env)
        match env.vars.get(arg.to_string()) {
          Some((offset, _)) =>
            if i < reg_arg_list.length() {
              match arg_type {
                Double =>
                  instrs.push(
                    Fld(freg_arg_list.get(i).unwrap(), { base: Fp, offset }),
                  )
                _ =>
                  instrs.push(
                    Ld(reg_arg_list.get(i).unwrap(), { base: Fp, offset }),
                  )
              }
            } else {
              // 处理溢出参数
              let stack_offset = -(i - reg_arg_list.length() + 1) * 8
              match arg_type {
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
          None =>
            println("Warning: Arg not found in environment: " + arg.to_string())
        }
      }
      match env.vars.get(f.to_string()) {
        Some((offset, _)) => {
          // 3. 加载函数指针并调用
          instrs.push(Ld(S11, { base: Fp, offset }))
          instrs.push(Ld(T1, { base: S11, offset: 0 })) // 加载函数指针
          instrs.push(Jalr(T1)) // 调用闭包函数
          instrs.push(Ld(S11, { base: Fp, offset }))
        }
        None =>
          match
            env.fundefs.search_by(fn(fundef) { fundef.name._ == f.to_string() }) {
            Some(offset) => {
              let func = env.fundefs.get(offset).unwrap()
              if func.is_closure {
                // println("CallClosure: " + f.to_string() + " is closure")

                // 保存当前闭包指针到栈上
                let closure_save_offset = env.current_offset
                instrs.push(Sd(S11, { base: Fp, offset: closure_save_offset }))
                env.current_offset -= 8
                instrs.push(Ld(T1, { base: S11, offset: 0 })) // 加载函数指针
                instrs.push(Jalr(T1)) // 调用闭包函数
                instrs.push(Ld(S11, { base: Fp, offset: closure_save_offset }))
              } else {
                instrs.push(Call(Label(func.name._)))
              }
            }
            None =>
              println("Warning: CallClosure: " + f.to_string() + " not found")
          }
      }
    }
    CallDirect(label, args) => {
      for i, arg in args {
        if i < reg_arg_list.length() {
          match env.vars.get(arg.to_string()) {
            Some((offset, ty)) =>
              match ty {
                Double =>
                  instrs.push(
                    Fld(freg_arg_list.get(i).unwrap(), { base: Fp, offset }),
                  )
                _ =>
                  // 其他类型使用通用寄存器
                  instrs.push(
                    Ld(reg_arg_list.get(i).unwrap(), { base: Fp, offset }),
                  )
              }
            None => {
              // 如果是函数名，需要特殊处理
              let def_index = env.fundefs.search_by(
                fn(fundef) { fundef.name._ == arg.to_string() },
              )
              match def_index {
                Some(index) => {
                  let fundef = env.fundefs.get(index).unwrap()
                  if fundef.is_closure {
                    // 如果是闭包函数，需要创建闭包对象
                    let size = 8 + fundef.formal_free_vars.length() * 8

                    // 分配闭包内存
                    instrs.push(Li(A0, size.to_string()))
                    instrs.push(Call(Label("minimbt_malloc")))
                    instrs.push(Mv(T0, A0))

                    // 存储函数指针
                    instrs.push(La(T1, fundef.name._))
                    instrs.push(Sd(T1, { base: T0, offset: 0 }))

                    // 存储自由变量
                    for j, _free_var in fundef.formal_free_vars {
                      instrs.push(Ld(T1, { base: S11, offset: (j + 1) * 8 }))
                      instrs.push(Sd(T1, { base: T0, offset: (j + 1) * 8 }))
                    }

                    // 将闭包指针移到参数寄存器
                    instrs.push(Mv(reg_arg_list.get(i).unwrap(), T0))
                  } else {
                    // 如果是直接函数，只需要加载函数地址
                    instrs.push(La(reg_arg_list.get(i).unwrap(), fundef.name._))
                  }
                }
                None =>
                  // 如果找不到函数定义，可能是外部函数
                  instrs.push(La(reg_arg_list.get(i).unwrap(), arg.to_string()))
              }
            }
          }
        } else {
          let offset = env.vars.get(arg.to_string()).unwrap().0
          let stack_offset = -(i - reg_arg_list.length() + 1) * 8
          // 超出寄存器数量的参数存入栈
          match get_var_type(arg, env) {
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
      match env.fundefs.search_by(fn(fundef) { fundef.name._ == label._ }) {
        Some(_) => instrs.push(Call(Label(label._)))
        None =>
          match env.vars.get(label._) {
            Some((offset, _)) => {
              // 3. 加载函数指针并调用
              instrs.push(Ld(S11, { base: Fp, offset }))
              instrs.push(Ld(T1, { base: S11, offset: 0 })) // 加载函数指针
              instrs.push(Jalr(T1)) // 调用闭包函数
            }
            None => instrs.push(Call(Label(label._)))
          }
      }
      // 恢复参数寄存器 - 使用保存时的偏移量
      // let restore_offset = save_area_offset
      // for i = 0; i < args_to_save; i = i + 1 {
      //   // println(restore_offset - (i * 8))
      //   instrs.push(
      //     Ld(reg_arg_list.get(i).unwrap(), { base: Fp, offset: restore_offset - (i * 8) }),
      //   )
      // }
      // println("\n")
    }
    MakeTuple(elems) => {
      // 1. 分配元组空间
      let size = elems.length() * 8
      instrs.push(Li(A0, size.to_string()))
      instrs.push(Call("minimbt_malloc")) // 使用堆分配
      instrs.push(Mv(T0, A0)) // 保存元组地址

      // 2. 存储元素
      for i, elem in elems {
        // 加载元素值（使用Ld而不是Lw）
        instrs.push(Ld(T1, { base: Fp, offset: varOffset(env, elem) }))
        // 存储到元组中
        instrs.push(Sd(T1, { base: T0, offset: i * 8 }))
      }

      // 3. 将元组地址放入返回寄存器
      instrs.push(Mv(reg_ret, T0))
    }
    LetTuple(names, tuple, e) => {
      // 元组解构
      // 从元组加载各个字段
      instrs.push(Ld(T0, { base: Fp, offset: varOffset(env, tuple) }))
      for i, name_ty in names {
        instrs.push(Ld(T1, { base: T0, offset: i * 8 }))
        instrs.push(Sd(T1, { base: Fp, offset: env.current_offset }))
        env.vars.set(name_ty.0.to_string(), (env.current_offset, name_ty.1))
        env.current_offset -= 8
      }
      instrs.append(compile_expr(e, env))
    }
    ArrayGet(array, index) => {
      // 1. 加载数组基地址
      instrs.push(Ld(T0, { base: Fp, offset: varOffset(env, array) }))

      // 2. 加载索引值并根据类型计算偏移
      instrs.push(Ld(T1, { base: Fp, offset: varOffset(env, index) }))
      match get_array_element_type(array, env) {
        Double => instrs.push(Slli(T1, T1, 3)) // 浮点数: 8字节
        Int => instrs.push(Slli(T1, T1, 2)) // 整数: 4字节
        DirectFn(_, _) | ClosureFn(_, _) | Ptr => instrs.push(Slli(T1, T1, 3)) // 指针类型: 8字节
        _ => instrs.push(Slli(T1, T1, 3)) // 默认: 4字节
      }

      // 3. 计算最终地址
      instrs.push(Add(T0, T0, T1))

      // 4. 根据数组元素类型选择加载指令
      match get_array_element_type(array, env) {
        Double => instrs.push(Fld(freg_ret, { base: T0, offset: 0 }))
        Int => instrs.push(Lw(reg_ret, { base: T0, offset: 0 }))
        Array(_) => instrs.push(Ld(reg_ret, { base: T0, offset: 0 }))
        DirectFn(_, _) => instrs.push(Mv(reg_ret, T0)) // 函数指针用 Ld
        ClosureFn(_, _) => instrs.push(Mv(reg_ret, T0)) // 闭包函数指针也用 Ld
        Ptr => instrs.push(Ld(reg_ret, { base: T0, offset: 0 })) // 指针类型用 Ld
        _ => instrs.push(Ld(reg_ret, { base: T0, offset: 0 })) // 其他类型默认用 Lw
      }
    }
    ArrayPut(array, index, value) => {
      // 1. 加载数组基地址
      instrs.push(Ld(T0, { base: Fp, offset: varOffset(env, array) }))

      // 2. 加载并计算索引偏移
      instrs.push(Ld(T1, { base: Fp, offset: varOffset(env, index) }))
      instrs.push(Slli(T1, T1, 3))

      // 3. 安全地计算目标地址
      instrs.push(Add(T0, T0, T1))

      // 4. 加载并存储值
      let value_offset = env.vars.get(value.to_string()).unwrap().0
      match get_array_element_type(array, env) {
        Double => {
          instrs.push(Fld(Fa0, { base: Fp, offset: value_offset }))
          instrs.push(Fsd(Fa0, { base: T0, offset: 0 }))
        }
        Int => {
          instrs.push(Lw(T1, { base: Fp, offset: value_offset }))
          instrs.push(Sw(T1, { base: T0, offset: 0 }))
        }
        _ => {
          instrs.push(Ld(T1, { base: Fp, offset: value_offset }))
          instrs.push(Sd(T1, { base: T0, offset: 0 }))
        }
      }
    }
    ExternalArray(label) =>
      // 外部数组
      instrs.push(La(reg_ret, label._))
  }
  // println("instrs: " + instrs.to_string())
  instrs
}

///|
fn get_var_type(name : @typing.Name, env : Env) -> @closure.LowType {
  for var in env.vars {
    if var.0 == name.to_string() {
      // println("var: " + var.0.to_string())
      // println("var type: " + var.1.1.to_string())
      return var.1.1
    }
  }
  // 在函数定义中查找变量类型
  // println("get_var_type: " + name.to_string())
  for fundef in env.fundefs {
    // 检查参数
    for _index, arg in fundef.args {
      // println("arg: " + arg.0.to_string())
      // println("name: " + name.to_string())
      if arg.0 == name {
        // println("arg type: " + arg.1.to_string())
        return arg.1
      }
    }
    // 检查自由变量
    for _index, free_var in fundef.formal_free_vars {
      if free_var.0 == name {
        // println("free_var: " + free_var.0.to_string())
        // println("free_var type: " + free_var.1.to_string())
        return free_var.1
      }
    }
  }
  // 默认返回整数类型
  Ptr
}

// 添加一个辅助函数来获取数组元素类型
///|
fn get_array_element_type(array : @typing.Name, env : Env) -> @closure.LowType {
  match get_var_type(array, env) {
    Array(elem_type) => {
      let _ = elem_type
      elem_type
    }
    _ => Ptr // 默认类型
  }
}

///|
pub let extenv = [
  "read_int", "print_int", "read_char", "print_char", "print_newline", "print_endline",
  "int_of_float", "float_of_int", "truncate", "floor", "abs_float", "sqrt", "sin",
  "cos", "atan", "create_array", "create_float_array", "create_ptr_array",
]

///|
let _default_counter : Ref[Int] = { val: 0 }

///|
fn gen_label(name : String, counter~ : Ref[Int] = _default_counter) -> Label {
  counter.val = counter.val + 1
  Label("label_" + name + "_" + counter.val.to_string())
}
