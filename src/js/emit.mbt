///|
pub fn emit(input : @closure.Program) -> String {
  // for fundef in input.fundefs {
  //   if extenv.contains(fundef.name._) {
  //     continue
  //   }
  //   println("fundef: " + fundef.to_string())
  // }
  // println("minimbt_main: " + input.body.to_string())
  let mut output = ""

  // 生成所有函数
  for func in input.fundefs {
    let name = func.name
    if extenv.contains(func.name._) {
      continue
    }
    if func.is_closure {
      output += "function \{name._.to_string()}(env, "

      // 添加函数参数
      output += String::concat(
        func.args.map(fn(arg) { arg.0.to_string() }),
        separator=", ",
      )
      output += ") {\n"
      // 从环境变量中获取闭包
      for i, fv in func.formal_free_vars {
        output += " const \{fv.0.to_string()} = env[\{i}];\n"
      }
      output += " return "
      // 生成函数体
      output += emit_expr(func.body)
      output += "\n}\n\n"
    } else {
      output += "function \{name._.to_string()}("
      output += String::concat(
        func.args.map(fn(arg) { arg.0.to_string() }),
        separator=",",
      )
      output += ") {\n"
      output += "  return "
      output += emit_expr(func.body)
      output += "\n}\n\n"
    }
  }

  // 添加 export default
  output += "export default function() {\n"
  output += "  return "
  output += emit_expr(input.body)
  output += "}\n"
  output
}

///|
fn emit_expr(expr : @closure.Expr) -> String {
  match expr {
    Int(n) => n.to_string()
    Double(n) => n.to_string()
    Neg(name) => "-" + name.to_string()
    Var(name) => name.to_string()
    Add(e1, e2) => e1.to_string() + " + " + e2.to_string()
    Sub(e1, e2) => e1.to_string() + " - " + e2.to_string()
    Mul(e1, e2) => e1.to_string() + " * " + e2.to_string()
    Div(e1, e2) => e1.to_string() + " / " + e2.to_string()
    FNeg(name) => "-" + name.to_string()
    FAdd(e1, e2) => e1.to_string() + " + " + e2.to_string()
    FSub(e1, e2) => e1.to_string() + " - " + e2.to_string()
    FMul(e1, e2) => e1.to_string() + " * " + e2.to_string()
    FDiv(e1, e2) => e1.to_string() + " / " + e2.to_string()
    IfEq(e1, e2, e3, e4) =>
      "if (" +
      e1.to_string() +
      " === " +
      e2.to_string() +
      ") {\n  " +
      emit_expr(e3) +
      "\n} else {\n  " +
      emit_expr(e4) +
      "\n}"
    IfLe(e1, e2, e3, e4) =>
      "if (" +
      e1.to_string() +
      " <= " +
      e2.to_string() +
      ") {\n  " +
      emit_expr(e3) +
      "\n} else {\n  " +
      emit_expr(e4) +
      "\n}"
    Let((name, _), e1, e2) => // 先生成绑定，然后继续处理剩余表达式
      "(() => {\n  " +
      "const \{name} = " +
      emit_expr(e1) +
      ";\n  " +
      "return " +
      emit_expr(e2) +
      ";\n" +
      "})()"
    MakeClosure((func, _), env, e) =>
      if env.actual_free_vars.length() == 0 {
        emit_expr(e)
      } else {
        // 生成 bind 调用来创建闭包
        let free_vars = String::concat(
          env.actual_free_vars.map(fn(v) { v.name.to_string() }),
          separator=",",
        )
        "  \{func.to_string()}.bind(null, [\{free_vars}])"
      }
    CallClosure(func, args) => {
      let mut result = func.to_string() + "("
      // 添加参数
      for i, arg in args {
        if i > 0 {
          result += ", "
        }
        result += arg.to_string()
      }
      result += ")"
      result
    }
    CallDirect(func, args) => {
      let mut result = func._ + "("
      for i, arg in args {
        if i > 0 {
          result += ", "
        }
        result += arg.to_string()
      }
      result += ")"
      result
    }
    MakeTuple(es) => {
      let mut result = "["
      for i, e in es {
        if i > 0 {
          result += ", "
        }
        result += e.to_string()
      }
      result += "]"
      result
    }
    LetTuple(names_tys, e1, e2) =>
      "(() => {\n  " +
      "const " +
      String::concat(
        names_tys.map(fn(name) { name.0.to_string() }),
        separator=",",
      ) +
      " = " +
      e1.to_string() +
      ";\n  " +
      "return " +
      emit_expr(e2) +
      ";\n" +
      "})()"
    ArrayGet(e1, e2) => e1.to_string() + "[" + e2.to_string() + "]"
    ArrayPut(e1, e2, e3) =>
      e1.to_string() + "[" + e2.to_string() + "] = " + e3.to_string()
    ExternalArray(e) => e.to_string()
    Unit => "undefined"
  }
}

///|
pub let extenv = [
  "read_int", "print_int", "read_char", "print_char", "print_newline", "print_endline",
  "int_of_float", "float_of_int", "truncate", "floor", "abs_float", "sqrt", "sin",
  "cos", "atan", "create_array", "create_float_array", "create_ptr_array",
]
