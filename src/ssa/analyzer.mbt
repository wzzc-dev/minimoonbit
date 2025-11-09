///| 表达式分析模块

///|

///| 提供分析表达式、修改变量、类型推断等功能

///|
/// SSA转换错误类型
pub enum SsaError {
  VariableNotFound(String)
} derive(Show)

///|
/// 安全地获取变量值，带错误处理
pub fn safe_get_var(
  var_env : @immut/hashmap.HashMap[String, Value],
  name : String,
) -> Result[Value, SsaError] {
  match var_env.get(name) {
    Some(value) => Ok(value)
    None => Err(SsaError::VariableNotFound("Variable not found: " + name))
  }
}

///|
/// 安全地获取函数类型，带错误处理
pub fn safe_get_func_type(
  func_env : @immut/hashmap.HashMap[String, Type],
  name : String,
) -> Result[Type, SsaError] {
  match func_env.get(name) {
    Some(func_type) => Ok(func_type)
    None =>
      // 尝试从外部环境查找
      match @typing.extenv.get(name) {
        Some(ret_type) => Ok(convert_type_from_types(ret_type))
        None => Err(SsaError::VariableNotFound("Function not found: " + name))
      }
  }
}

///|

///|
/// 分析表达式中修改的变量
pub fn analyze_modified_variables(
  expr : @closure.Expr,
  var_env : @immut/hashmap.HashMap[String, Value],
) -> @immut/hashmap.HashMap[String, Value] {
  let mut modified = @immut/hashmap.new()
  match expr {
    Assign(lhs_name, _) =>
      match var_env.get(lhs_name.to_string()) {
        Some(value) => modified = modified.add(lhs_name.to_string(), value)
        None => ()
      }
    Let((_, _), e1, e2) => {
      // 递归分析let绑定的两个表达式
      modified = merge_modified_vars(
        modified,
        analyze_modified_variables(e1, var_env),
      )
      modified = merge_modified_vars(
        modified,
        analyze_modified_variables(e2, var_env),
      )
    }
    While(_, body_expr) =>
      // 递归分析while循环体
      modified = merge_modified_vars(
        modified,
        analyze_modified_variables(body_expr, var_env),
      )
    IfEq(_, _, e1, e2) | IfLe(_, _, e1, e2) | IfLt(_, _, e1, e2) => {
      // 递归分析if的两个分支
      modified = merge_modified_vars(
        modified,
        analyze_modified_variables(e1, var_env),
      )
      modified = merge_modified_vars(
        modified,
        analyze_modified_variables(e2, var_env),
      )
    }
    MakeTuple(elements) =>
      for elem in elements {
        modified = merge_modified_vars(
          modified,
          analyze_modified_variables(@closure.Expr::Var(elem), var_env),
        )
      }
    CallDirect(_, args) =>
      for arg in args {
        modified = merge_modified_vars(
          modified,
          analyze_modified_variables(@closure.Expr::Var(arg), var_env),
        )
      }
    CallClosure(_, args) =>
      for arg in args {
        modified = merge_modified_vars(
          modified,
          analyze_modified_variables(@closure.Expr::Var(arg), var_env),
        )
      }
    MakeClosure(_, _, body_expr) =>
      modified = merge_modified_vars(
        modified,
        analyze_modified_variables(body_expr, var_env),
      )
    _ => () // 其他表达式不修改变量
  }
  modified
}

///|
/// 合并两个修改变量集合
pub fn merge_modified_vars(
  vars1 : @immut/hashmap.HashMap[String, Value],
  vars2 : @immut/hashmap.HashMap[String, Value],
) -> @immut/hashmap.HashMap[String, Value] {
  let mut result = vars1
  for key in vars2.keys() {
    match vars2.get(key) {
      Some(value) => result = result.add(key, value)
      None => ()
    }
  }
  result
}

///|
/// 推断表达式的类型
pub fn infer_expression_type(expr : @closure.Expr, context : Context) -> Type {
  // @util.logger("infer_expression_type expr: " + expr.to_string())
  match expr {
    Unit => Type::Unit
    Int(_) | Int64(_) => Type::Int
    Double(_) => Type::Float
    Var(name) =>
      match context.var_env.get(name.to_string()) {
        Some(value) => value.ty
        None =>
          match context.func_env.get(name.to_string()) {
            Some(func_type) => func_type
            None => Type::Int // 默认类型，应该报错
          }
      }
    Add(_, _) | Sub(_, _) | Mul(_, _) | Div(_, _) | Mod(_) => Type::Int
    FAdd(_, _) | FSub(_, _) | FMul(_, _) | FDiv(_, _) | FMod(_) => Type::Float
    IfEq(_, _, e1, _) | IfLe(_, _, e1, _) | IfLt(_, _, e1, _) =>
      infer_expression_type(e1, context)
    Let(_, e2, _) => infer_expression_type(e2, context)
    While(_, _) => Type::Unit
    MakeTuple(elements) => {
      let element_types = []
      for elem in elements {
        element_types.push(
          infer_expression_type(@closure.Expr::Var(elem), context),
        )
      }
      Type::Tuple(element_types)
    }
    CallDirect(label, _) =>
      match context.func_env.get(label.0) {
        Some(ty) => ty
        None => {
          // 从外部环境查找
          let name = match label.0.strip_prefix("minimbt_") {
            Some(name) => name.to_string()
            None => label.0.to_string()
          }
          match @typing.extenv.get(name) {
            Some(ret_type) =>
              // @util.logger("infer_expression_type CallDirect ret_type: " + ret_type.to_string())
              convert_type_from_types(ret_type)
            None =>
              match @typing.extenv.get(name.to_string()) {
                Some(ret_type) => convert_type_from_types(ret_type)
                None =>
                  match context.var_env.get(name.to_string()) {
                    Some(value) => value.ty
                    None =>
                      @util.die(
                        "infer_expression_type CallClosure variable not found: " +
                        name.to_string(),
                      )
                  }
              }
          }
        }
      }
    CallClosure(name, _) => {
      // @util.logger(
      //   "infer_expression_type CallClosure name: " + name.to_string(),
      // )
      // @util.logger(
      //   "infer_expression_type CallClosure context.func_env: " +
      //   context.func_env.to_string(),
      // )
      // @util.logger(
      //   "infer_expression_type CallClosure  context.var_env: " +
      //   context.var_env.to_string(),
      // )
      match context.func_env.get(name.to_string()) {
        Some(ret_type) => ret_type
        None =>
          // 从外部环境查找
          match @typing.extenv.get(name.to_string()) {
            Some(ret_type) => convert_type_from_types(ret_type)
            None =>
              match context.var_env.get(name.to_string()) {
                Some(value) => value.ty
                None =>
                  @util.die(
                    "infer_expression_type CallClosure variable not found: " +
                    name.to_string(),
                  )
              }
          }
      }
    }
    MakeClosure((_, ty), _, _) => convert_type(ty) // 闭包值的类型需要更精确的推断
    Neg(_) => Type::Int
    Bool(_) => Type::Bool
    FNeg(_) => Type::Float
    TupleGet(_, ty, _) => convert_type(ty)
    LetTuple(_, _, _) => Type::Unit
    ArrayGet(_, _) => Type::Int
    ExternalArray(Label(_)) => Type::Int
    ArrayPut(_, _, _) => Type::Unit
    Assign(_, _) => Type::Unit
    StaticArrayRef(Label(_)) => Type::Int
  }
}

///|
/// 简单的LRU类型缓存，避免重复类型推断
let type_cache : Ref[@immut/hashmap.HashMap[String, Type]] = Ref::new(
  @immut/hashmap.new(),
)

///|
/// 带缓存的类型推断
pub fn cached_infer_type(expr : @closure.Expr, context : Context) -> Type {
  // @util.logger("cached_infer_type expr: " + expr.to_string())
  // @util.logger(
  //   "cached_infer_type type_cache.val: " + type_cache.val.to_string(),
  // )
  let expr_key = expr.to_string()
  // @util.logger("cached_infer_type expr_key: " + expr_key)
  // @util.logger(
  //   "cached_infer_type type_cache.val.get(expr_key): " +
  //   type_cache.val.get(expr_key).to_string(),
  // )
  match type_cache.val.get(expr_key) {
    Some(cached_type) => cached_type
    None => {
      let inferred_type = infer_expression_type(expr, context)
      // @util.logger(
      //   "cached_infer_type inferred_type: " + inferred_type.to_string(),
      // )
      type_cache.val = type_cache.val.add(expr_key, inferred_type)
      inferred_type
    }
  }
}
