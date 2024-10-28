pub fn emit(input : @closure.Program) -> Array[AssemblyFunction] {
  // println("emit: " + input.to_string())
  let functions = []

  // 为每个函数定义生成汇编代码
  for fundef in input.fundefs {
    let body = []

    // 函数序言（Function Prologue）
    // 保存返回地址(ra)和帧指针(fp)
    body.push(Sw(Ra, { base: Sp, offset: -4 }))
    body.push(Sw(Fp, { base: Sp, offset: -8 }))
    // 设置新的帧指针并调整栈指针
    body.push(Addi(Fp, Sp, -8))
    body.push(Addi(Sp, Sp, -16)) // 根据栈帧大小调整

    // 保存被调用者保存的寄存器（callee-saved registers）
    // TODO: 只保存实际使用的寄存器
    for i, reg in reg_callee_saved_list {
      body.push(Sw(reg, { base: Fp, offset: -4 * (i + 3) }))
    }

    // 函数主体
    // TODO: 实现表达式编译

    body.append(compile_expr(fundef.body))

    // 函数收尾（Function Epilogue）
    // 恢复被调用者保存的寄存器
    for i, reg in reg_callee_saved_list {
      body.push(Lw(reg, { base: Fp, offset: -4 * (i + 3) }))
    }

    // 恢复帧指针和返回地址
    body.push(Lw(Ra, { base: Fp, offset: 4 }))
    body.push(Lw(Fp, { base: Fp, offset: 0 }))
    body.push(Addi(Sp, Fp, 8))
    body.push(Jr(Ra))
    functions.push(
      {
        name: fundef.name._,
        export: false, // 对于导出的函数设为 true
        body,
      },
    )
  }
  // 编译主程序体
  functions.push(
    { name: "minimbt_main", export: true, body: compile_expr(input.body) },
  )
  functions
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

fn compile_expr(expr : @closure.Expr) -> Array[RvAsm] {
  let instrs = []
  match expr {
    Unit => instrs
    Int(i) => [Li(A0, i.to_string())]
    Double(d) => {
      let str_d = d.to_string()
      [Li(A0, str_d)]
    }
    Neg(i) => {
      instrs.push(Li(A0, i.to_string()))
      instrs.push(Neg(A0, A0))
      instrs
    }
    Add(name1, name2) => {
      instrs.push(Li(A0, name1.to_string()))
      instrs.push(Li(A1, name2.to_string()))
      instrs.push(Add(A0, A0, A1))
      instrs
    }
    Sub(name1, name2) => {
      instrs.push(Li(A0, name1.to_string()))
      instrs.push(Li(A1, name2.to_string()))
      instrs.push(Sub(A0, A0, A1))
      instrs
    }
    Mul(name1, name2) => {
      instrs.push(Li(A0, name1.to_string()))
      instrs.push(Li(A1, name2.to_string()))
      instrs.push(Mul(A0, A0, A1))
      instrs
    }
    Div(name1, name2) => {
      instrs.push(Li(A0, name1.to_string()))
      instrs.push(Li(A1, name2.to_string()))
      instrs.push(Div(A0, A0, A1))
      instrs
    }
    FNeg(name) => {
      instrs.push(Li(A0, name.to_string()))
      instrs.push(FnegD(Fa0, Fa0))
      instrs
    }
    FAdd(name1, name2) => {
      instrs.push(Li(A0, name1.to_string()))
      instrs.push(Li(A1, name2.to_string()))
      instrs.push(FaddD(Fa0, Fa0, Fa0))
      instrs
    }
    FSub(name1, name2) => {
      instrs.push(Li(A0, name1.to_string()))
      instrs.push(Li(A1, name2.to_string()))
      instrs.push(FsubD(Fa0, Fa0, Fa0))
      instrs
    }
    FMul(name1, name2) => {
      instrs.push(Li(A0, name1.to_string()))
      instrs.push(Li(A1, name2.to_string()))
      instrs.push(FmulD(Fa0, Fa0, Fa0))
      instrs
    }
    FDiv(name1, name2) => {
      instrs.push(Li(A0, name1.to_string()))
      instrs.push(Li(A1, name2.to_string()))
      instrs.push(FdivD(Fa0, Fa0, Fa0))
      instrs
    }
    IfEq(lhs, rhs, expr1, expr2) => {
      let label_true = gen_label()
      let label_end = gen_label()

      // 加载两个比较操作数
      instrs.push(Li(A0, lhs.name.to_string()))
      instrs.push(Li(A1, rhs.name.to_string()))

      // 比较 A0 和 A1 的值，如果相等则跳转到 label_true
      instrs.push(Beq(A0, A1, label_true))

      // 否则执行 expr2
      instrs.append(compile_expr(expr2))
      // 跳转到 label_end 跳过 true 分支
      instrs.push(J(label_end._))

      // label_true: 执行 expr1
      instrs.push(Label(label_true._))
      instrs.append(compile_expr(expr1))

      // label_end:
      instrs.push(Label(label_end._))
      instrs
    }
    IfLe(lhs, rhs, expr1, expr2) => {
      let label_true = gen_label()
      let label_end = gen_label()

      // 加载两个比较操作数
      instrs.push(Li(A0, lhs.name.to_string()))
      instrs.push(Li(A1, rhs.name.to_string()))

      // 如果 A0 <= A1，跳转到 label_true
      instrs.push(Ble(A0, A1, label_true._))

      // 否则执行 expr2
      instrs.append(compile_expr(expr2))
      // 跳转到 label_end 跳过 true 分支
      instrs.push(J(label_end._))

      // label_true: 执行 expr1
      instrs.push(Label(label_true._))
      instrs.append(compile_expr(expr1))

      // label_end:
      instrs.push(Label(label_end._))
      instrs
    }
    Let((name, low_type), expr1, expr2) => {
      // Step 1: Compile expr1 and get the instructions
      instrs.append(compile_expr(expr1))

      // Step 2: Store the result of expr1 in the stack
      // Assuming the result of expr1 is in A0
      instrs.push(Sw(A0, { base: Sp, offset: -4 })) // Store the value at the top of the stack

      // Step 3: Compile expr2
      instrs.append(compile_expr(expr2))

      // Step 4: Clean up the stack (optional if you only push and pop on the stack)
      instrs.push(Addi(Sp, Sp, 4)) // Adjust the stack pointer back
      instrs
    }
    Var(name) => [Li(A0, name.to_string())]
    MakeClosure((name, low_type), closure, expr) => {
      // 假设 `closure` 包含捕获变量的列表，将它们逐一存储
      for i, var in closure.actual_free_vars {
        instrs.push(Li(A0, var.to_string()))
        instrs.push(Sw(A0, { base: Sp, offset: -4 * (i + 1) }))
      }
      // 将闭包的环境地址（起始地址）放入 A0，并为后续表达式提供访问
      instrs.push(Addi(A0, Sp, -16))
      // 编译 expr，将生成的汇编添加到指令集
      instrs.append(compile_expr(expr))
      instrs
    }
    CallClosure(name, arg_names) => {
      // 处理闭包调用相关的汇编生成
      // 加载参数等操作
      for arg_name in arg_names {
        instrs.push(Li(A0, arg_name.to_string()))
      }
      instrs.push(Call(name.name.unwrap()))
      instrs
    }
    CallDirect(label, arg_names) => {
      // 处理直接调用相关的汇编生成
      // 加载参数等操作
      for arg_name in arg_names {
        instrs.push(Li(A0, arg_name.to_string()))
      }
      instrs.push(Call(label._))
      instrs
    }
    MakeTuple(names) => {
      // 处理元组创建相关的汇编（可能需要根据具体架构处理数据存储等）
      for name in names {
        instrs.push(Li(A0, name.to_string()))
      }
      instrs
    }
    LetTuple(names, name, expr) => {
      // 处理元组解构相关的汇编
      instrs.append(compile_expr(expr))
      for n, _ in names {
        instrs.push(Li(A0, n.to_string()))
      }
      instrs
    }
    ArrayGet(array_name, index_name) => {
      // 处理数组获取元素相关的汇编
      instrs.push(Li(A0, array_name.to_string()))
      instrs.push(Li(A1, index_name.to_string()))
      // 这里假设存在加载数组元素的指令，可能需要更多处理
      instrs
    }
    ArrayPut(array_name, index_name, value_name) => {
      // 处理数组设置元素相关的汇编
      instrs.push(Li(A0, array_name.to_string()))
      instrs.push(Li(A1, index_name.to_string()))
      instrs.push(Li(A2, value_name.to_string()))
      // 这里假设存在存储数组元素的指令，可能需要更多处理
      instrs
    }
    ExternalArray(label) => {
      // 处理外部数组相关的汇编（可能涉及外部函数调用等）
      instrs.push(Call(label._))
      instrs
    }
  }
}

let default_counter : Ref[Int] = { val: 0 }

fn gen_label(~counter : Ref[Int] = default_counter) -> Label {
  counter.val = counter.val + 1
  Label("label_" + counter.val.to_string())
}
