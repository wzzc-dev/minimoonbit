pub fn emit(input : @closure.Program) -> Array[AssemblyFunction] {
  // for fundef in input.fundefs {
  //   if extenv.contains(fundef.name._) {
  //     continue
  //   }
  //   println("fundef: " + fundef.to_string())
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
    // println("framesize: " + framesize.to_string())
    // 函数序言
    body.push(Addi(Sp, Sp, -framesize))
    body.push(Sd(Ra, { base: Sp, offset: framesize - 8 }))
    body.push(Sd(Fp, { base: Sp, offset: framesize - 16 }))
    body.push(Addi(Fp, Sp, framesize))

    // 保存参数
    let env = {
      vars: Map::new(),
      current_offset: -24, // 从-24开始，留出ra和fp的空间
      fundefs: input.fundefs,
    }
    // 如果是闭包函数，先处理自由变量
    if fundef.is_closure {
      for i, arg in fundef.formal_free_vars {
        let offset = env.current_offset
        // 从闭包对象(s11)中加载自由变量，偏移为8*i+8 (第一个8字节是函数指针)
        body.push(Ld(T0, { base: S11, offset: (i + 1) * 8 }))
        // 保存到栈上
        body.push(Sd(T0, { base: Fp, offset }))
        env.vars.set(arg.0.to_string(), offset)
        env.current_offset -= 8
      }
    }
    // 处理普通参数
    for i, arg in fundef.args {
      let offset = env.current_offset
      body.push(Sd(reg_arg_list.get(i).unwrap(), { base: Fp, offset }))
      env.vars.set(arg.0.to_string(), offset)
      env.current_offset -= 8
    }

    // 编译函数体
    body.append(compile_expr(fundef.body, env))
    body.push(Ld(Ra, { base: Sp, offset: framesize - 8 }))
    body.push(Ld(Fp, { base: Sp, offset: framesize - 16 }))
    body.push(Addi(Sp, Sp, framesize))
    body.push(Ret)
    functions.push({ name: fundef.name._, export: false, body })
  }

  // 主函数
  let main = []
  let main_framesize = calculate_framesize_expr(input.body) // 增加主函数的栈帧大小

  // 主函数序言
  main.push(Addi(Sp, Sp, -main_framesize))
  main.push(Sd(Ra, { base: Sp, offset: main_framesize - 8 }))
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
  // // 恢复调用者保存的寄存器
  // for i, reg in reg_callee_saved_list {
  //   main.push(Ld(reg, { base: Sp, offset: main_framesize - (i + 3) * 8 }))
  // }

  main.push(Ld(Ra, { base: Sp, offset: main_framesize - 8 }))
  main.push(Ld(Fp, { base: Sp, offset: main_framesize - 16 }))
  main.push(Addi(Sp, Sp, main_framesize))
  main.push(Ret)
  functions.push({ name: "minimbt_main", export: true, body: main })
  // println("functions: " + functions.to_string())
  functions
}

fn getTypeSize(ty : @closure.LowType) -> Int {
  match ty {
    Int => 8 // 整数类型占用8字节
    Double => 8 // 双精度浮点数占用8字节
    Bool => 1 // 布尔类型占用1字节
    ClosureFn(arr_t, t) => {
      let mut arr_t_size = 0
      for elem_type in arr_t {
        arr_t_size += getTypeSize(elem_type)
      }
      arr_t_size + getTypeSize(t)
    }
    DirectFn(arr_t, t) => {
      let mut arr_t_size = 0
      for elem_type in arr_t {
        arr_t_size += getTypeSize(elem_type)
      }
      arr_t_size + getTypeSize(t)
    }
    Tuple(arr_t) => {
      // 假设元组的大小是其元素大小的总和
      let mut tuple_size = 0
      for elem_type in arr_t {
        tuple_size += getTypeSize(elem_type)
      }
      tuple_size
    }
    Array(t) => {
      let element_size = getTypeSize(t)
      // 假设数组长度为 10（可以根据实际情况调整）
      let array_length = 10
      element_size * array_length
    }
    Ptr => 8
    Unit => 0 // 其他类型不占用空间
  }
}

fn calculate_framesize(fundef : @closure.FuncDef) -> Int {
  // 基础大小：返回地址 + 帧指针 + 调用者保存寄存器 + 参数 + 局部变量
  let base_size = 16 // Ra + Fp
  let callee_saved_size = reg_callee_saved_list.length() * 8
  let args_size = fundef.args.length() * 8
  let locals_size = 32 // 为局部变量预留空间
  return base_size + callee_saved_size + args_size + locals_size
}

fn calculate_framesize_expr(expr : @closure.Expr) -> Int {
  match expr {
    Unit => 0
    Int(_) => 8
    Double(_) => 8
    Neg(_) => 8
    Add(_, _) => 8
    Sub(_, _) => 8
    Mul(_, _) => 8
    Div(_, _) => 8
    FNeg(_) => 8
    FAdd(_, _) => 8
    FSub(_, _) => 8
    FMul(_, _) => 8
    FDiv(_, _) => 8
    IfEq(_, _, e1, e2) => {
      let size1 = calculate_framesize_expr(e1)
      let size2 = calculate_framesize_expr(e2)
      if size1 > size2 {
        size1
      } else {
        size2
      }
    }
    IfLe(_, _, e1, e2) => {
      let size1 = calculate_framesize_expr(e1)
      let size2 = calculate_framesize_expr(e2)
      if size1 > size2 {
        size1
      } else {
        size2
      }
    }
    Let((_, ty), e1, e2) => {
      let size1 = calculate_framesize_expr(e1)
      let size2 = calculate_framesize_expr(e2)
      size1 + size2 + getTypeSize(ty)
    }
    Var(_) => 8
    MakeClosure(_, _, e) => calculate_framesize_expr(e)
    CallClosure(_, _) => 8
    CallDirect(_, _) => 8
    MakeTuple(_) => 8
    LetTuple(_, _, _) => 8
    ArrayGet(_, _) => 8
    ArrayPut(_, _, _) => 8
    ExternalArray(_) => 8
  }
}

pub struct AssemblyFunction {
  name : String
  export : Bool
  body : Array[RvAsm]
}

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

fn compile_expr(expr : @closure.Expr, env : Env) -> Array[RvAsm] {
  // println("compile_expr: " + expr.to_string())
  // println("env: " + env.vars.to_string())
  // println("env.current_offset: " + env.current_offset.to_string())
  let instrs = []
  match expr {
    Unit => instrs.clear()
    Int(i) => instrs.push(Li(reg_ret, i.to_string()))
    Double(d) => {
      let bits = d.reinterpret_as_u64()
      instrs.push(Li(T0, bits.to_string()))
      instrs.push(FmvDX(Fa0, T0))
    }
    Neg(x) => {
      instrs.push(
        Ld(A0, { base: Fp, offset: env.vars.get(x.to_string()).unwrap() }),
      )
      instrs.push(Neg(reg_ret, reg_ret))
    }
    Add(x, y) => {
      // println("Add: " + x.to_string() + " " + y.to_string())
      // println("env x: " + env.vars.get(x.to_string()).to_string())
      // println("env y: " + env.vars.get(y.to_string()).to_string())
      instrs.push(
        Ld(A0, { base: Fp, offset: env.vars.get(x.to_string()).unwrap() }),
      )
      instrs.push(
        Ld(A1, { base: Fp, offset: env.vars.get(y.to_string()).unwrap() }),
      )
      instrs.push(Add(reg_ret, A0, A1))
    }
    Sub(x, y) => {
      instrs.push(
        Ld(A0, { base: Fp, offset: env.vars.get(x.to_string()).unwrap() }),
      )
      instrs.push(
        Ld(A1, { base: Fp, offset: env.vars.get(y.to_string()).unwrap() }),
      )
      instrs.push(Sub(reg_ret, A0, A1))
    }
    Mul(x, y) => {
      instrs.push(
        Ld(A0, { base: Fp, offset: env.vars.get(x.to_string()).unwrap() }),
      )
      instrs.push(
        Ld(A1, { base: Fp, offset: env.vars.get(y.to_string()).unwrap() }),
      )
      instrs.push(Mul(reg_ret, A0, A1))
    }
    Div(x, y) => {
      instrs.push(
        Ld(A0, { base: Fp, offset: env.vars.get(x.to_string()).unwrap() }),
      )
      instrs.push(
        Ld(A1, { base: Fp, offset: env.vars.get(y.to_string()).unwrap() }),
      )
      instrs.push(Div(reg_ret, A0, A1))
    }
    FNeg(x) => {
      instrs.push(
        Fld(Fa0, { base: Fp, offset: env.vars.get(x.to_string()).unwrap() }),
      )
      instrs.push(FnegD(Fa0, Fa0))
    }
    FAdd(x, y) => {
      instrs.push(
        Fld(Fa0, { base: Fp, offset: env.vars.get(x.to_string()).unwrap() }),
      )
      instrs.push(
        Fld(Fa1, { base: Fp, offset: env.vars.get(y.to_string()).unwrap() }),
      )
      instrs.push(FaddD(Fa0, Fa0, Fa1))
    }
    FSub(x, y) => {
      instrs.push(
        Fld(Fa0, { base: Fp, offset: env.vars.get(x.to_string()).unwrap() }),
      )
      instrs.push(
        Fld(Fa1, { base: Fp, offset: env.vars.get(y.to_string()).unwrap() }),
      )
      instrs.push(FsubD(Fa0, Fa0, Fa1))
    }
    FMul(x, y) => {
      instrs.push(
        Fld(Fa0, { base: Fp, offset: env.vars.get(x.to_string()).unwrap() }),
      )
      instrs.push(
        Fld(Fa1, { base: Fp, offset: env.vars.get(y.to_string()).unwrap() }),
      )
      instrs.push(FmulD(Fa0, Fa0, Fa1))
    }
    FDiv(x, y) => {
      instrs.push(
        Fld(Fa0, { base: Fp, offset: env.vars.get(x.to_string()).unwrap() }),
      )
      instrs.push(
        Fld(Fa1, { base: Fp, offset: env.vars.get(y.to_string()).unwrap() }),
      )
      instrs.push(FdivD(Fa0, Fa0, Fa1))
    }
    IfEq(x, y, e1, e2) => {
      instrs.push(
        Ld(A0, { base: Fp, offset: env.vars.get(x.to_string()).unwrap() }),
      )
      instrs.push(
        Ld(A1, { base: Fp, offset: env.vars.get(y.to_string()).unwrap() }),
      )
      // 相等比较分支
      let label_else = gen_label("else")
      let label_end = gen_label("end")
      instrs.push(Bne(A0, A1, label_else))
      instrs.append(compile_expr(e1, env))
      instrs.push(J(label_end))
      instrs.push(Label(label_else._))
      instrs.append(compile_expr(e2, env))
      instrs.push(Label(label_end._))
    }
    IfLe(x, y, e1, e2) => {
      // println("IfLe: " + x.to_string() + " " + y.to_string() + " " + e1.to_string() + " " + e2.to_string())
      // println("env: " + env.vars.to_string())
      instrs.push(
        Ld(A0, { base: Fp, offset: env.vars.get(x.to_string()).unwrap() }),
      )
      instrs.push(
        Ld(A1, { base: Fp, offset: env.vars.get(y.to_string()).unwrap() }),
      )
      // println("A0: " + A0.to_string() + " A1: " + A1.to_string())
      // 小于等于比较分支
      let label_else = gen_label("else")
      let label_end = gen_label("end")
      instrs.push(Bgt(A0, A1, label_else))
      instrs.append(compile_expr(e1, env))
      instrs.push(J(label_end))
      instrs.push(Label(label_else._))
      instrs.append(compile_expr(e2, env))
      instrs.push(Label(label_end._))
    }
    Let((name, ty), e1, e2) => {
      // println("Let: " + expr.to_string())
      // println("Let: " + name.to_string() + " " + ty.to_string() + " " + e1.to_string() + " " + e2.to_string())
      // 计算 e1
      instrs.append(compile_expr(e1, env))
      let size = getTypeSize(ty)
      // println("size: " + size.to_string())
      let offset = env.current_offset - size

      // 为新变量分配栈空间

      // println("env.current_offset: " + env.current_offset.to_string() + " size: " + size.to_string())
      // println("offset = env.current_offset - size: " + offset.to_string())
      // 保存结果到栈上
      match ty {
        Double => instrs.push(Fsd(Fa0, { base: Fp, offset }))
        _ => instrs.push(Sd(reg_ret, { base: Fp, offset }))
      }
      env.vars.set(name.to_string(), offset)
      // 更新环境
      let new_env = {
        vars: env.vars,
        current_offset: offset,
        fundefs: env.fundefs,
      }

      // 计算 e2,使用更新后的环境
      instrs.append(compile_expr(e2, new_env))
    }
    Var(name) =>
      // 从环境中查找变量的偏移
      match env.vars.get(name.to_string()) {
        Some(offset) =>
          match get_var_type(name, env) {
            Double => instrs.push(Fld(Fa0, { base: Fp, offset }))
            _ => instrs.push(Ld(reg_ret, { base: Fp, offset }))
          }
        None => instrs.push(Call(Label(name.to_string())))
      }
    MakeClosure((name, _ty), closure, e) => {
      // 1. 计算需要的内存大小 (函数指针 + 自由变量)
      let size = 8 + closure.actual_free_vars.length() * 8

      // 2. 调用 malloc 分配内存
      instrs.push(Li(A0, size.to_string()))
      instrs.push(Call(Label("minimbt_malloc")))
      instrs.push(Mv(T0, A0)) // 保存闭包指针到 t0

      // 3. 存储函数指针
      instrs.push(La(T1, closure.name._))
      instrs.push(Sd(T1, { base: T0, offset: 0 }))

      // 4. 存储捕获的变量
      for i, var in closure.actual_free_vars {
        instrs.push(
          Ld(T1, { base: Fp, offset: env.vars.get(var.to_string()).unwrap() }),
        )
        instrs.push(Sd(T1, { base: T0, offset: (i + 1) * 8 }))
      }

      // 5. 将闭包指针移到返回寄存器
      instrs.push(Mv(reg_ret, T0))
      let offset = env.current_offset - 8
      instrs.push(Sd(reg_ret, { base: Fp, offset }))

      // 6. 更新环境
      env.vars.set(name.to_string(), offset)
      env.current_offset = offset

      // 7. 编译剩余表达式，使用新环境
      // if e != Var(name) { // 避免重复处理
      instrs.append(compile_expr(e, env))
      // }
    }
    CallClosure(f, args) => {
      // println("CallClosure: " + f.to_string() + " " + args.to_string())
      // println("env: " + env.vars.to_string())
      match env.vars.get(f.to_string()) {
        Some(offset) =>
          // 1. 加载闭包指针到 s11
          instrs.push(Ld(S11, { base: Fp, offset }))
        None => println("CallClosure: " + f.to_string() + " not found")
      }

      // 2. 准备参数
      for i, arg in args {
        if i < reg_arg_list.length() {
          // 使用参数寄存器
          instrs.push(
            Ld(
              reg_arg_list.get(i).unwrap(),
              { base: Fp, offset: env.vars.get(arg.to_string()).unwrap() },
            ),
          )
        } else {
          // 超出寄存器数量的参数存入栈
          instrs.push(
            Ld(T0, { base: Fp, offset: env.vars.get(arg.to_string()).unwrap() }),
          )
          instrs.push(
            Sd(T0, { base: Sp, offset: -(i - reg_arg_list.length() + 1) * 8 }),
          )
        }
      }

      // 3. 加载函数指针并调用
      instrs.push(Ld(T1, { base: S11, offset: 0 })) // 加载函数指针
      instrs.push(Jalr(T1)) // 调用闭包函数
    }
    CallDirect(label, args) => {
      // 直接函数调用
      // 保存参数到参数寄存器
      for i, arg in args {
        if i < reg_arg_list.length() {
          // instrs.push(
          //   Ld(
          //     reg_arg_list.get(i).unwrap(),
          //     { base: Fp, offset: env.vars.get(arg.to_string()).unwrap() },
          //   ),
          // )
          match env.vars.get(arg.to_string()) {
            Some(offset) =>
              instrs.push(
                Ld(reg_arg_list.get(i).unwrap(), { base: Fp, offset }),
              )
            None => {
              // 检查是否是函数名
              let def_index = env.fundefs.search_by(
                fn(fundef) { fundef.name._ == arg.to_string() }
              )

              match def_index {
                Some(index) => {
                  let fundef = env.fundefs.get(index).unwrap()
                  // 计算闭包大小
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
                    instrs.push(
                      Ld(T1, { base: S11, offset: (j + 1) * 8 }), // 从当前闭包加载
                    )
                    instrs.push(Sd(T1, { base: T0, offset: (j + 1) * 8 }))
                  }

                  // 将闭包指针移到参数寄存器
                  instrs.push(Mv(reg_arg_list.get(i).unwrap(), T0))
                }
                None => println("CallDirect: " + arg.to_string() + " not found")
              }
            }
          }
        } else {
          instrs.push(
            Ld(T0, { base: Fp, offset: env.vars.get(arg.to_string()).unwrap() }),
          )
          instrs.push(
            Sd(T0, { base: Sp, offset: -(i - reg_arg_list.length() + 1) * 8 }),
          )
        }
      }

      // 调用函数
      instrs.push(Call(label._))
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
        instrs.push(
          Ld(T1, { base: Fp, offset: env.vars.get(elem.to_string()).unwrap() }),
        )
        // 存储到元组中
        instrs.push(Sd(T1, { base: T0, offset: i * 8 }))
      }

      // 3. 将元组地址放入返回寄存器
      instrs.push(Mv(reg_ret, T0))
    }
    LetTuple(names, tuple, e) => {
      // println("LetTuple: " + names.to_string() + " " + tuple.to_string() + " " + e.to_string())
      // 元组解构
      // 从元组加载各个字段
      for i, _name_ty in names {
        instrs.push(
          Lw(T0, { base: Fp, offset: env.vars.get(tuple.to_string()).unwrap() }),
        )
        instrs.push(Ld(T0, { base: T0, offset: i * 8 }))
        instrs.push(Sd(T0, { base: Fp, offset: -(i + 1) * 8 }))
      }
      instrs.append(compile_expr(e, env))
    }
    ArrayGet(array, index) => {
      // 1. 加载数组基地址
      instrs.push(
        Ld(T0, { base: Fp, offset: env.vars.get(array.to_string()).unwrap() }),
      )

      // 2. 计算索引偏移

      // 加载索引值
      instrs.push(
        Ld(T1, { base: Fp, offset: env.vars.get(index.to_string()).unwrap() }),
      )
      instrs.push(Slli(T1, T1, 3)) // 乘以8 (左移3位)

      // 3. 计算元素地址并加载值
      instrs.push(Add(T0, T0, T1)) // 基地址 + 偏移
      instrs.push(Ld(reg_ret, { base: T0, offset: 0 }))
    }
    ArrayPut(array, index, value) => {
      // 数组赋值
      instrs.push(
        Ld(T0, { base: Fp, offset: env.vars.get(array.to_string()).unwrap() }),
      )
      instrs.push(Slli(T0, T0, 3))
      instrs.push(
        Ld(T1, { base: Fp, offset: env.vars.get(index.to_string()).unwrap() }),
      )
      instrs.push(Add(T0, T1, T0))
      instrs.push(
        Ld(T1, { base: Fp, offset: env.vars.get(value.to_string()).unwrap() }),
      )
      instrs.push(Sd(T1, { base: T0, offset: 0 }))
      // instrs.push(Mv(reg_ret, Unit)) // 返回Unit
      // instrs.push(Lw(A0, { base: Sp, offset: 0 })) // Load array base address
      // instrs.push(Lw(A1, { base: Sp, offset: 4 })) // Load index
      // instrs.push(Lw(A2, { base: Sp, offset: 8 })) // Load value to store
      // instrs.push(Slli(A1, A1, 2)) // Multiply index by 4 (assuming 4 bytes per element)
      // instrs.push(Add(A0, A0, A1)) // Calculate address of the element
      // instrs.push(Sw(A2, { base: A0, offset: 0 })) // Store the value
    }
    ExternalArray(label) =>
      // 外部数组
      instrs.push(La(reg_ret, label._))
  }
  // println("instrs: " + instrs.to_string())
  instrs
}

fn get_var_type(name : @typing.Name, env : Env) -> @closure.LowType {
  // 在函数定义中查找变量类型
  for fundef in env.fundefs {
    // 检查参数
    for _index, arg in fundef.args {
      if arg.0 == name {
        return arg.1
      }
    }
    // 检查自由变量
    for _index, free_var in fundef.formal_free_vars {
      if free_var.0 == name {
        return free_var.1
      }
    }
  }
  // 默认返回整数类型
  Int
}

pub let extenv = [
  "read_int", "print_int", "read_char", "print_char", "print_newline", "print_endline",
  "int_of_float", "float_of_int", "truncate", "floor", "abs_float", "sqrt", "sin",
  "cos", "atan", "create_array", "create_float_array", "create_ptr_array",
]

let _default_counter : Ref[Int] = { val: 0 }

fn gen_label(name : String, ~counter : Ref[Int] = _default_counter) -> Label {
  counter.val = counter.val + 1
  Label("label_" + name + "_" + counter.val.to_string())
}

// 添加一个环境结构来跟踪变量位置
struct Env {
  vars : Map[String, Int] // 变量名到栈偏移的映射
  mut current_offset : Int // 当前可用的栈偏移
  fundefs : Array[@closure.FuncDef] // 函数定义
}
