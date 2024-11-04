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

    // // 保存调用者保存的寄存器
    // for i, reg in reg_callee_saved_list {
    //   body.push(Sd(reg, { base: Sp, offset: framesize - (i + 3) * 8 }))
    // }

    // 保存参数
    let env = {
      vars: Map::new(),
      current_offset: -(fundef.args.length() +
      fundef.formal_free_vars.length() +
      3) *
      8,
      fundefs: input.fundefs,
    }
    let mut j = 0
    for _i, arg in fundef.formal_free_vars {
      body.push(
        Sd(reg_arg_list.get(j).unwrap(), { base: Fp, offset: -(j + 3) * 8 }),
      )
      env.vars.set(arg.0.to_string(), -(j + 3) * 8)
      j += 1
    }
    for _i, arg in fundef.args {
      // println("arg: " + arg.0.to_string())
      // println("i: " + i.to_string())
      // println("offset: " +  (-(i + 3) * 8).to_string())
      body.push(
        Sd(
          reg_arg_list.get(j).unwrap(),
          { base: Fp, offset: -(j + 3 + fundef.formal_free_vars.length()) * 8 },
        ),
      )
      env.vars.set(
        arg.0.to_string(),
        -(j + 3 + fundef.formal_free_vars.length()) * 8,
      )
      j += 1
    }
    // println("fundef.body: " + fundef.body.to_string())
    // 编译函数体
    body.append(compile_expr(fundef.body, env))

    // 函数尾声
    // 恢复调用者保存的寄存器
    // for i, reg in reg_callee_saved_list {
    //   body.push(Ld(reg, { base: Sp, offset: framesize - (i + 3) * 8 }))
    // }

    body.push(Ld(Ra, { base: Sp, offset: framesize - 8 }))
    body.push(Ld(Fp, { base: Sp, offset: framesize - 16 }))
    body.push(Addi(Sp, Sp, framesize))
    body.push(Ret)
    functions.push({ name: fundef.name._, export: false, body })
  }

  // println("functions: " + functions.to_string())

  // 主函数
  let main = []
  let main_framesize = calculate_framesize_expr(input.body) // 增加主函数的栈帧大小

  // 主函数序言
  main.push(Addi(Sp, Sp, -main_framesize))
  main.push(Sd(Ra, { base: Sp, offset: main_framesize - 8 }))
  main.push(Sd(Fp, { base: Sp, offset: main_framesize - 16 }))
  main.push(Addi(Fp, Sp, main_framesize))

  // // 保存调用者保存的寄存器
  // for i, reg in reg_callee_saved_list {
  //   main.push(Sd(reg, { base: Sp, offset: main_framesize - (i + 3) * 8 }))
  // }

  // 编译主体
  let main_env = { vars: Map::new(), current_offset: main_framesize, fundefs: input.fundefs}
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
    Let((_, _), e1, e2) => {
      let size1 = calculate_framesize_expr(e1)
      let size2 = calculate_framesize_expr(e2)
      size1 + size2
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
      let bits = @double/internal/ryu.ryu_to_string(d)
      instrs.push(Li(T0, bits))
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
      instrs.push(Sd(reg_ret, { base: Fp, offset }))
      env.vars.set(name.to_string(), offset)
      // 更新环境
      let new_env = { vars: env.vars, current_offset: offset, fundefs: env.fundefs }

      // 计算 e2,使用更新后的环境
      instrs.append(compile_expr(e2, new_env))
    }
    Var(name) =>
      // 从环境中查找变量的偏移
      match env.vars.get(name.to_string()) {
        Some(offset) => instrs.push(Ld(reg_ret, { base: Fp, offset }))
        None => instrs.push(Call(Label(name.to_string())))
      }
    MakeClosure((_name, _ty), closure, e) => {
      // println("MakeClosure: " + expr.to_string())
      // 闭包创建
      // 保存闭包对象
      let mut j = 0
      for _i, free_var in closure.actual_free_vars {
        // println("free_var: " + free_var.to_string())
        // println("env " + env.vars.to_string())
        if not(env.vars.get(free_var.to_string()).is_empty()) {
          instrs.push(
            Ld(
              reg_arg_list.get(j).unwrap(),
              { base: Fp, offset: env.vars.get(free_var.to_string()).unwrap() },
            ),
          )
          // instrs.push(Sd(T0, { base: Fp, offset: -(j + 1) * 8 }))
          j += 1
        }
      }

      // 继续编译剩余表达式
      instrs.append(compile_expr(e, env))
    }
    CallClosure(f, args) => {
      // 闭包调用
      // println("env: " + env.vars.to_string())
      // println("f: " + f.to_string())
      // println("args: " + args.to_string())
      // println("env.vars: " + env.vars.to_string())
      // let closure_free_vars_count = env.vars.get(f.to_string()).unwrap()
      let funcdef_index = env.fundefs.search_by(fn (funcdef) {  funcdef.name._ == f.to_string() }).unwrap()
      let funcdef = env.fundefs.get(funcdef_index).unwrap()
      let args_count = funcdef.args.length()
      
      // 保存参数到参数寄存器
      for i, arg in args {
        if i + args_count < reg_arg_list.length() {
          instrs.push(
            Ld(
              reg_arg_list.get(i + args_count).unwrap(),
              { base: Fp, offset: env.vars.get(arg.to_string()).unwrap() },
            ),
          )
        } else {
          // 超出寄存器数量的参数压栈
          instrs.push(
            Ld(T0, { base: Fp, offset: env.vars.get(arg.to_string()).unwrap() }),
          )
          instrs.push(
            Sw(T0, { base: Sp, offset: -(i + args_count - reg_arg_list.length() + 1) * 8 }),
          )
          env.vars.set(
            arg.to_string(),
            env.vars.get(arg.to_string()).unwrap() + 8,
          )
        }
      }
      // // 调用函数
      // instrs.push(Jalr(reg_closure))
      instrs.push(Call(f.to_string()))
    }
    CallDirect(label, args) => {
      // 直接函数调用
      // 保存参数到参数寄存器
      for i, arg in args {
        if i < reg_arg_list.length() {
          instrs.push(
            Ld(
              reg_arg_list.get(i).unwrap(),
              { base: Fp, offset: env.vars.get(arg.to_string()).unwrap() },
            ),
          )
        } else {
          instrs.push(
            Ld(T0, { base: Fp, offset: env.vars.get(arg.to_string()).unwrap() }),
          )
          instrs.push(
            Sw(T0, { base: Sp, offset: -(i - reg_arg_list.length() + 1) * 8 }),
          )
        }
      }

      // 调用函数
      instrs.push(Call(label._))
    }
    MakeTuple(elems) => {
      // 创建元组
      // 分配元组空间
      let size = elems.length() * 8
      instrs.push(Addi(reg_ret, Sp, -size))

      // 存储元素
      for i, elem in elems {
        instrs.push(
          Lw(T0, { base: Fp, offset: env.vars.get(elem.to_string()).unwrap() }),
        )
        instrs.push(Sd(T0, { base: reg_ret, offset: i * 8 }))
      }
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
      // 数组访问
      instrs.push(
        Lw(T0, { base: Fp, offset: env.vars.get(array.to_string()).unwrap() }),
      )
      instrs.push(Slli(T0, T0, 3)) // 计算偏移(乘8)
      instrs.push(
        Lw(T1, { base: Fp, offset: env.vars.get(index.to_string()).unwrap() }),
      )
      instrs.push(Add(T0, T1, T0))
      instrs.push(Ld(reg_ret, { base: T0, offset: 0 }))
      // instrs.push(Lw(A0, { base: Sp, offset: 0 })) // Load array base address
      // instrs.push(Lw(A1, { base: Sp, offset: 4 })) // Load index
      // instrs.push(Slli(A1, A1, 2)) // Multiply index by 4 (assuming 4 bytes per element)
      // instrs.push(Add(A0, A0, A1)) // Calculate address of the element
      // instrs.push(Lw(A0, { base: A0, offset: 0 })) // Load the element
    }
    ArrayPut(array, index, value) => {
      // 数组赋值
      instrs.push(
        Lw(T0, { base: Fp, offset: env.vars.get(array.to_string()).unwrap() }),
      )
      instrs.push(Slli(T0, T0, 3))
      instrs.push(
        Lw(T1, { base: Fp, offset: env.vars.get(index.to_string()).unwrap() }),
      )
      instrs.push(Add(T0, T1, T0))
      instrs.push(
        Lw(T1, { base: Fp, offset: env.vars.get(value.to_string()).unwrap() }),
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
