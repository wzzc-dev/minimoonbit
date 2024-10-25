pub fn emit(
  input : @closure.Program
) -> Array[AssemblyFunction] {
  println("emit: " + input.to_string())
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
    body.push(Addi(Sp, Sp, -16))  // 根据栈帧大小调整
    
    // 保存被调用者保存的寄存器（callee-saved registers）
    // TODO: 只保存实际使用的寄存器
    for i, reg in reg_callee_saved_list {
      body.push(Sw(reg,  { base: Fp, offset: -4 * (i + 3) }))
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
    
    functions.push({
      name: fundef.name.to_string(),
      export: false, // 对于导出的函数设为 true
      body: body,
    })
  }
  // 编译主程序体
  functions.push({
    name: "main",
    export: true,
    body: compile_expr(input.body),
  })
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


fn compile_expr(expr: @closure.Expr) -> Array[RvAsm] {
  let instrs = []
  match expr {
    Unit => instrs
    Int(i) => [Addi(A0, Zero, i)]
    Neg(i) => []
  }
}