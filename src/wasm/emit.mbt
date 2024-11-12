pub fn emit(input : @closure.Program) -> String {
  // for fundef in input.fundefs {
  //   if extenv.contains(fundef.name._) {
  //     continue
  //   }
  //   println("fundef: " + fundef.to_string())
  // }
  // println("minimbt_main: " + input.body.to_string())
  let mut output = ""
  
  // 添加主函数声明
  output += "(module\n"
  
  // 添加start section
  output += "  (start $minimbt_main)\n"
  
  // 添加主函数定义
  output += "  (func $minimbt_main\n"
  output += "    " + emit_expr(input.body) + "\n"
  output += "  )\n"
  
  // 处理所有函数定义
  for fundef in input.fundefs {
    if not(extenv.contains(fundef.name._)) {
      output += "  (func $" + fundef.name._ + "\n"
      output += "    " + emit_expr(fundef.body) + "\n"
      output += "  )\n"
    }
  }
  
  output += ")\n"
  output
}

fn emit_expr(expr : @closure.Expr) -> String {
  match expr {
    // 数值类型
    Int(n) => "(i32.const " + n.to_string() + ")"
    Double(n) => "(f64.const " + n.to_string() + ")"
    
    // 算术运算 - 整数
    Neg(i) => "(i32.sub (i32.const 0) " + i.to_string() + ")"
    Add(i1, i2) => "(i32.add " + i1.to_string() + " " + i2.to_string() + ")"
    Sub(i1, i2) => "(i32.sub " + i1.to_string() + " " + i2.to_string() + ")"
    Mul(i1, i2) => "(i32.mul " + i1.to_string() + " " + i2.to_string() + ")"
    Div(i1, i2) => "(i32.div_s " + i1.to_string() + " " + i2.to_string() + ")"
    
    // 算术运算 - 浮点数
    FNeg(d) => "(f64.neg " + d.to_string() + ")"
    FAdd(d1, d2) => "(f64.add " + d1.to_string() + " " + d2.to_string() + ")"
    FSub(d1, d2) => "(f64.sub " + d1.to_string() + " " + d2.to_string() + ")"
    FMul(d1, d2) => "(f64.mul " + d1.to_string() + " " + d2.to_string() + ")"
    FDiv(d1, d2) => "(f64.div " + d1.to_string() + " " + d2.to_string() + ")"
    
    // 条件分支
    IfEq(e1, e2, e3, e4) =>
      "(if (i32.eq " + e1.to_string() + " " + e2.to_string() + ")\n" +
      "  (then " + emit_expr(e3) + ")\n" +
      "  (else " + emit_expr(e4) + "))"
    IfLe(i1, i2, e3, e4) =>
      "(if (i32.le_s " + i1.to_string() + " " + i2.to_string() + ")\n" +
      "  (then " + emit_expr(e3) + ")\n" +
      "  (else " + emit_expr(e4) + "))"
    
    // 变量引用
    Var(name) => "(local.get $" + name.to_string() + ")"
    
    // 函数调用
    CallDirect(func, args) => {
      let mut result = "(call $" + func._ 
      for arg in args {
        result += " " + arg.to_string()
      }
      result += ")"
      result
    }
    
    // 内存操作
    ArrayGet(e1, e2) => 
      "(i32.load (i32.add " + e1.to_string() + " " +
      "(i32.mul " + e2.to_string() + " (i32.const 4))))"
    ArrayPut(e1, e2, e3) =>
      "(i32.store (i32.add " + e1.to_string() + " " +
      "(i32.mul " + e2.to_string() + " (i32.const 4))) " +
      e3.to_string() + ")"
    
    // 其他情况暂时返回空值
    Unit => "(i32.const 0)"
    _ => "(i32.const 0)" // 其他情况需要进一步实现
  }
}
pub let extenv = [
  "read_int", "print_int", "read_char", "print_char", "print_newline", "print_endline",
  "int_of_float", "float_of_int", "truncate", "floor", "abs_float", "sqrt", "sin",
  "cos", "atan", "create_array", "create_float_array", "create_ptr_array",
]
