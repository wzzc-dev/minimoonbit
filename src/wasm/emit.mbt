pub fn emit(input : @closure.Program) -> String {
  let mut output = ""
  
  // 添加内存段声明，用于存储闭包环境
  output += "  (memory 1)\n"
  
  // 添加全局变量用于内存分配
  output += "  (global $heap (mut i32) (i32.const 0))\n"
  
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
      output += "  (func $" + fundef.name._ + " "
      
      // 如果是闭包函数，添加环境指针参数
      if fundef.is_closure {
        output += "(param $env i32) "
      }
      
      // 添加其他参数
      for name_ty in fundef.args {
        let name = name_ty.0
        let ty = name_ty.1
        output += "(param $" + name.to_string() + " " + getTy(ty) + ") "
      }
      
      // 添加返回类型（如果需要）
      output += "(result " + getTy(fundef.ty) + ")\n"
      
      // 如果是闭包函数，添加局部变量声明用于加载自由变量
      if fundef.is_closure {
        for i, name_ty in fundef.formal_free_vars {
          output += "    (local $" + name_ty  .0.to_string() + " i32)\n"
          output += "    (local.set $" + name_ty.0.to_string() + 
                   " (i32.load offset=" + (i * 4).to_string() + 
                   " (local.get $env)))\n"
        }
      }
      
      output += "    " + emit_expr(fundef.body) + "\n"
      output += "  )\n"
    }
  }
  
  output += ")\n"
  output
}

fn getTy(ty : @closure.LowType) -> String {
  match ty {
    Int => "i32"
    Double => "f64"
    _ => "i32"
  }
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
    
    // 修改闭包相关的处理
    MakeClosure((name, _ty), closure, body) => {
      let mut result = "(block\n"
      // 分配闭包环境的内存
      result += "  (local $env_ptr i32)\n"
      result += "  (local.set $env_ptr (global.get $heap))\n"
      
      // 存储环境变量
      for i, var in closure.actual_free_vars {
        result += "  (i32.store offset=" + (i * 4).to_string() + 
                 " (local.get $env_ptr) (local.get $" + var.to_string() + "))\n"
      }
      
      // 更新堆指针
      result += "  (global.set $heap (i32.add (local.get $env_ptr) " +
               "(i32.const " + (closure.actual_free_vars.length() * 4).to_string() + ")))\n"
      
      // 将环境指针绑定到名称
      result += "  (local.set $" + name.to_string() + " (local.get $env_ptr))\n"
      
      // 继续处理body
      result += "  " + emit_expr(body) + ")"
      result
    }
    
    CallClosure(func_name, args) => {
      let mut result = "(call $" + func_name.to_string()
      // 首先传递环境指针
      result += " (local.get $" + func_name.to_string() + ")"
      // 然后传递其他参数
      for arg in args {
        result += " (local.get $" + arg.to_string() + ")"
      }
      result += ")"
      result
    }
    _ => ""
  }
}
pub let extenv = [
  "read_int", "print_int", "read_char", "print_char", "print_newline", "print_endline",
  "int_of_float", "float_of_int", "truncate", "floor", "abs_float", "sqrt", "sin",
  "cos", "atan", "create_array", "create_float_array", "create_ptr_array",
]
