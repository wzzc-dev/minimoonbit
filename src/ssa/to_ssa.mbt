///| 将闭包IR转换为SSA形式

///| 使用基本块参数来实现SSA
///|
/// 将闭包IR程序转换为SSA程序
pub fn to_ssa(input : @closure.Program) -> Ssa {

  // @util.logger("closure ir: " + input.to_json().stringify())
  // 初始化SSA程序
  let functions = []

  // 转换每个函数定义
  for fundef in input.fundefs {
    if not(@typing.extenv.contains(fundef.old_name.to_string())) {
      let ssa_func = convert_function(fundef, functions)
      // @util.logger("convert_function: " + ssa_func.to_json().stringify())
      functions.push(ssa_func)
    }
  }

  // 转换主函数体
  let main_func = convert_main_function(input.body, functions)
  functions.push(main_func)

  { program: { functions, } }
}

///|
/// 转换函数定义为SSA形式
fn convert_function(
  fundef : @closure.FuncDef,
  functions : Array[Function],
) -> Function {
  // 创建函数参数（包括正常参数和自由变量）
  let regular_params = fundef.args.map(fn(arg) {
    Value::{ id: new_value_id(), ty: convert_type(arg.1) }
  })
  let free_var_params = fundef.formal_free_vars.map(fn(free_var) {
    Value::{ id: new_value_id(), ty: convert_type(free_var.1) }
  })

  // 创建基本块列表
  let blocks = []

  // 创建入口基本块
  let entry_block = BasicBlock::{
    id: new_block_id(),
    params: [], // 函数入口块没有参数
    instructions: [],
    terminator: Terminator::Return(None), // 默认返回
  }
  blocks.push(entry_block)

  // 创建变量环境，将函数参数添加到环境中
  // 注意：由于我们改变了参数顺序，需要相应调整索引
  let mut var_env = @immut/hashmap.new()
  for i, free_var in fundef.formal_free_vars {
    let free_var_name = free_var.0
    let free_var_value = free_var_params[i]
    var_env = var_env.add(free_var_name.to_string(), free_var_value)
  }

  // 再添加正常参数到环境中（现在在参数列表的后面）
  for i, arg in fundef.args {
    let param_name = arg.0.to_string()
    let param_value = regular_params[i]
    var_env = var_env.add(param_name, param_value)
  }
  let mut func_env = @immut/hashmap.new().add(
    fundef.name.0.to_string(),
    convert_type(fundef.ty),
  )
  for func in functions {
    func_env = func_env.add(func.name, func.return_type)
  }
  let context = {
    current_block: entry_block,
    blocks,
    block_map: @immut/hashmap.new(), // 块映射，用于控制流
    var_env,
    func_env,
  } // 包含参数和自由变量的环境
  let result = convert_expr(context, fundef.body)
  // @util.logger("convert_expr: " + result.to_string())
  // 更新最后一个块的终止指令，使其返回表达式的结果
  let final_context = result.context
  let return_value = result.value
  let updated_final_block = BasicBlock::{
    id: final_context.current_block.id,
    params: final_context.current_block.params,
    instructions: final_context.current_block.instructions,
    terminator: Terminator::Return(return_value),
  }

  // 使用转换后的上下文更新块列表
  let updated_blocks = final_context.blocks.map(fn(b) {
    if b.id == updated_final_block.id {
      updated_final_block
    } else {
      b
    }
  })
  {
    name: fundef.name.0.to_string(),
    params: regular_params,
    closure_param: free_var_params,
    return_type: match fundef.ty {
      @closure.LowType::DirectFn(_, ret) => convert_type(ret)
      @closure.LowType::ClosureFn(_, ret) => convert_type(ret)
      _ => @util.die("unexpected fundef type: " + fundef.ty.to_string())
    },
    blocks: updated_blocks,
  }
}

///|
/// 转换主函数体为SSA形式
fn convert_main_function(
  body : @closure.Expr,
  functions : Array[Function],
) -> Function {
  convert_function(
    @closure.FuncDef::{
      name: @closure.Label("minimbt_main"),
      old_name: (try? @types.Name::from_string("minimbt_main")).unwrap(),
      is_closure: false,
      ty: @closure.LowType::DirectFn([], @closure.LowType::Unit),
      args: [],
      formal_free_vars: [],
      body,
    },
    functions,
  )
}

///|
/// 转换上下文
priv struct Context {
  current_block : BasicBlock
  blocks : Array[BasicBlock]
  block_map : @immut/hashmap.HashMap[Int, BasicBlock]
  // 添加变量环境：Name到Value的映射
  var_env : @immut/hashmap.HashMap[String, Value]
  // 添加函数环境：函数名到函数类型的映射
  func_env : @immut/hashmap.HashMap[String, Type]
} derive(Show)

///| 更新上下文中的当前块
fn update_current_block(context : Context, block : BasicBlock) -> Context {
  Context::{
    current_block: block,
    blocks: context.blocks,
    block_map: context.block_map,
    var_env: context.var_env,
    func_env: context.func_env,
  }
}

///| 更新上下文中的变量环境
fn update_var_env(context : Context, var_env : @immut/hashmap.HashMap[String, Value]) -> Context {
  Context::{
    current_block: context.current_block,
    blocks: context.blocks,
    block_map: context.block_map,
    var_env: var_env,
    func_env: context.func_env,
  }
}

///| 更新上下文中的块列表
fn update_blocks(context : Context, blocks : Array[BasicBlock]) -> Context {
  Context::{
    current_block: context.current_block,
    blocks: blocks,
    block_map: context.block_map,
    var_env: context.var_env,
    func_env: context.func_env,
  }
}

///| 安全地添加块到上下文，避免重复
fn add_block_to_context(context : Context, block : BasicBlock) -> Context {
  let existing_ids = context.blocks.map(fn(b) { b.id })
  if existing_ids.contains(block.id) {
    // 替换现有块
    let updated_blocks = context.blocks.map(fn(b) {
      if b.id == block.id { block } else { b }
    })
    update_blocks(context, updated_blocks)
  } else {
    // 添加新块
    let new_blocks = context.blocks.copy()
    new_blocks.push(block)
    update_blocks(context, new_blocks)
  }
}

///| 添加多个块到上下文
fn add_blocks_to_context(context : Context, blocks : Array[BasicBlock]) -> Context {
  let mut result_context = context
  for block in blocks {
    result_context = add_block_to_context(result_context, block)
  }
  result_context
}

///| SSA转换错误类型
priv enum SsaError {
  VariableNotFound(String)
  // TypeInferenceFailed(String)
  // UnsupportedConstruct(String)
  // InternalError(String)
} derive(Show)

///| 安全地获取变量值，带错误处理
fn safe_get_var(var_env : @immut/hashmap.HashMap[String, Value], name : String) -> Result[Value, SsaError] {
  match var_env.get(name) {
    Some(value) => Ok(value)
    None => Err(SsaError::VariableNotFound("Variable not found: " + name))
  }
}

///| 安全地获取函数类型，带错误处理
fn safe_get_func_type(func_env : @immut/hashmap.HashMap[String, Type], name : String) -> Result[Type, SsaError] {
  match func_env.get(name) {
    Some(func_type) => Ok(func_type)
    None => {
      // 尝试从外部环境查找
      match @typing.extenv.get(name) {
        Some(@types.Type::Fun(_, ret_type)) => Ok(convert_type_from_types(ret_type))
        Some(_) => Err(SsaError::VariableNotFound("Not a function: " + name))
        None => Err(SsaError::VariableNotFound("Function not found: " + name))
      }
    }
  }
}

///|
/// 表达式转换结果
priv struct ExprResult {
  value : Value?
  context : Context
} derive(Show)

///| 创建常量值并添加到当前块
fn create_const_int(context : Context, value : Int) -> (Value, Context) {
  let const_value = Value::{ id: new_value_id(), ty: Type::Int }
  let instruction = Instruction::{
    result: const_value,
    opcode: Opcode::ConstInt(value),
  }
  context.current_block.instructions.push(instruction)
  (const_value, context)
}

///| 创建浮点常量值并添加到当前块
fn create_const_float(context : Context, value : Double) -> (Value, Context) {
  let const_value = Value::{ id: new_value_id(), ty: Type::Float }
  let instruction = Instruction::{
    result: const_value,
    opcode: Opcode::ConstFloat(value),
  }
  context.current_block.instructions.push(instruction)
  (const_value, context)
}

///| 创建二元运算指令
fn create_binary_op(
  context : Context,
  op_type : BinaryOpType,
  left : Value,
  right : Value,
  result_type : Type
) -> (Value, Context) {
  let result_value = Value::{ id: new_value_id(), ty: result_type }
  let opcode = match op_type {
    BinaryOpType::Add => Opcode::Add(left, right)
    BinaryOpType::Sub => Opcode::Sub(left, right)
    BinaryOpType::Mul => Opcode::Mul(left, right)
    BinaryOpType::Div => Opcode::Div(left, right)
    BinaryOpType::Mod => Opcode::Mod(left, right)
    BinaryOpType::FAdd => Opcode::FAdd(left, right)
    BinaryOpType::FSub => Opcode::FSub(left, right)
    BinaryOpType::FMul => Opcode::FMul(left, right)
    BinaryOpType::FDiv => Opcode::FDiv(left, right)
    BinaryOpType::FMod => Opcode::FMod(left, right)
  }

  let instruction = Instruction::{ result: result_value, opcode }
  context.current_block.instructions.push(instruction)
  (result_value, context)
}

///| 二元运算类型
priv enum BinaryOpType {
  Add
  Sub
  Mul
  Div
  Mod
  FAdd
  FSub
  FMul
  FDiv
  FMod
}

///| 创建GetElement指令
fn create_get_element(
  context : Context,
  tuple_value : Value,
  index : Int,
  element_type : Type
) -> (Value, Context) {
  let element_value = Value::{ id: new_value_id(), ty: element_type }
  let instruction = Instruction::{
    result: element_value,
    opcode: Opcode::GetElement(tuple_value, index),
  }
  context.current_block.instructions.push(instruction)
  (element_value, context)
}


///| 分析表达式中修改的变量
fn analyze_modified_variables(expr : @closure.Expr, var_env : @immut/hashmap.HashMap[String, Value]) -> @immut/hashmap.HashMap[String, Value] {
  let mut modified = @immut/hashmap.new()

  match expr {
    Assign(lhs_name, _) => {
      match var_env.get(lhs_name.to_string()) {
        Some(value) => modified = modified.add(lhs_name.to_string(), value)
        None => ()
      }
    }
    Let((_, _), e1, e2) => {
      // 递归分析let绑定的两个表达式
      modified = merge_modified_vars(modified, analyze_modified_variables(e1, var_env))
      modified = merge_modified_vars(modified, analyze_modified_variables(e2, var_env))
    }
    While(_, body_expr) => {
      // 递归分析while循环体
      modified = merge_modified_vars(modified, analyze_modified_variables(body_expr, var_env))
    }
    IfEq(_, _, e1, e2) | IfLe(_, _, e1, e2) | IfLt(_, _, e1, e2) => {
      // 递归分析if的两个分支
      modified = merge_modified_vars(modified, analyze_modified_variables(e1, var_env))
      modified = merge_modified_vars(modified, analyze_modified_variables(e2, var_env))
    }
    MakeTuple(elements) => {
      for elem in elements {
        modified = merge_modified_vars(modified, analyze_modified_variables(@closure.Expr::Var(elem), var_env))
      }
    }
    CallDirect(_, args) => {
      for arg in args {
        modified = merge_modified_vars(modified, analyze_modified_variables(@closure.Expr::Var(arg), var_env))
      }
    }
    CallClosure(_, args) => {
      for arg in args {
        modified = merge_modified_vars(modified, analyze_modified_variables(@closure.Expr::Var(arg), var_env))
      }
    }
    MakeClosure(_, _, body_expr) => {
      modified = merge_modified_vars(modified, analyze_modified_variables(body_expr, var_env))
    }
    _ => () // 其他表达式不修改变量
  }

  modified
}

///| 合并两个修改变量集合
fn merge_modified_vars(
  vars1 : @immut/hashmap.HashMap[String, Value],
  vars2 : @immut/hashmap.HashMap[String, Value]
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

///| 推断表达式的类型
fn infer_expression_type(expr : @closure.Expr, context : Context) -> Type {
  match expr {
    Unit => Type::Unit
    Int(_) | Int64(_) => Type::Int
    Double(_) => Type::Float
    Var(name) => {
      match context.var_env.get(name.to_string()) {
        Some(value) => value.ty
        None => {
          match context.func_env.get(name.to_string()) {
            Some(func_type) => func_type
            None => Type::Int // 默认类型，应该报错
          }
        }
      }
    }
    Add(_, _) | Sub(_, _) | Mul(_, _) | Div(_, _) | Mod(_) => Type::Int
    FAdd(_, _) | FSub(_, _) | FMul(_, _) | FDiv(_, _) | FMod(_) => Type::Float
    IfEq(_, _, e1, _) | IfLe(_, _, e1, _) | IfLt(_, _, e1, _) => infer_expression_type(e1, context)
    Let(_, e2, _) => infer_expression_type(e2, context)
    While(_, _) => Type::Unit
    MakeTuple(elements) => {
      let element_types = []
      for elem in elements {
        element_types.push(infer_expression_type(@closure.Expr::Var(elem), context))
      }
      Type::Tuple(element_types)
    }
    CallDirect(label, _) => {
      match context.func_env.get(label.0) {
        Some(Type::Function(_, ret_type)) => ret_type
        Some(_) => Type::Int
        None => {
          // 从外部环境查找
          match @typing.extenv.get(label.0) {
            Some(@types.Type::Fun(_, ret_type)) => convert_type_from_types(ret_type)
            Some(_) => Type::Int
            None => Type::Int
          }
        }
      }
    }
    CallClosure(name, _) => {
      match context.func_env.get(name.to_string()) {
        Some(Type::Function(_, ret_type)) => ret_type
        Some(_) => Type::Int
        None => {
          // 从外部环境查找
          match @typing.extenv.get(name.to_string()) {
            Some(@types.Type::Fun(_, ret_type)) => convert_type_from_types(ret_type)
            Some(_) => Type::Int
            None => Type::Int
          }
        }
      }
    }
    MakeClosure((_, ty), _, _) => convert_type(ty) // 闭包值的类型需要更精确的推断
    _ => Type::Int // 默认类型
  }
}

///|
/// 转换闭包IR表达式为SSA指令
fn convert_expr(context : Context, expr : @closure.Expr) -> ExprResult {
  // @util.logger("convert_expr: " + expr.to_string())
  match expr {
    Unit =>
      // Unit值，不产生实际值
      ExprResult::{ value: None, context }
    MakeTuple(elements) => {
      // 元组创建
      let mut current_context = context
      let element_values = []

      // 转换所有元素
      for elem in elements {
        let elem_result = convert_expr(
          current_context,
          @closure.Expr::Var(elem),
        )
        current_context = elem_result.context
        match elem_result.value {
          Some(val) => element_values.push(val)
          None => () // 跳过Unit元素
        }
      }

      // 创建元组值
      let result_value = Value::{
        id: new_value_id(),
        ty: Type::Tuple(element_values.map(fn(v) { v.ty })),
      }
      let instruction = Instruction::{
        result: result_value,
        opcode: Opcode::Tuple(element_values),
      }

      // 更新当前块
      current_context.current_block.instructions.push(instruction)
      ExprResult::{ value: Some(result_value), context: current_context }
    }
    LetTuple(pattern_vars, tuple_name, body_expr) => {
      // 元组解构：let (x1, x2, ...) = tuple_name in body_expr
      // 获取元组值
      let tuple_value = context.var_env.get(tuple_name.to_string()).unwrap()

      // 为每个模式变量创建元组获取指令
      let mut current_context = context
      let mut updated_var_env = current_context.var_env

      // 为每个变量创建GetElement指令
      let len = pattern_vars.length()
      for i = 0; i < len; i = i + 1 {
        let (var_name, var_type) = pattern_vars[i]
        let element_value = Value::{
          id: new_value_id(),
          ty: convert_type(var_type),
        }
        let instruction = Instruction::{
          result: element_value,
          opcode: Opcode::GetElement(tuple_value, i),
        }

        // 添加指令到当前块
        current_context.current_block.instructions.push(instruction)

        // 更新变量环境
        updated_var_env = updated_var_env.add(
          var_name.to_string(),
          element_value,
        )

        // 更新上下文
        current_context = Context::{
          current_block: current_context.current_block,
          blocks: current_context.blocks,
          block_map: current_context.block_map,
          var_env: updated_var_env,
          func_env: current_context.func_env,
        }
      }

      // 使用更新后的环境转换body表达式
      convert_expr(current_context, body_expr)
    }
    TupleGet(tuple_name, tuple_type, index) => {
      // 元组访问：tuple_name.index
      let tuple_value = context.var_env.get(tuple_name.to_string()).unwrap()

      // 从元组类型中推断元素类型
      let element_type = match convert_type(tuple_type) {
        Type::Tuple(types) => types[index]
        _ => @util.die("Expected tuple type in TupleGet")
      }

      let (result_value, new_context) = create_get_element(context, tuple_value, index, element_type)
      ExprResult::{ value: Some(result_value), context: new_context }
    }
    ExternalArray(label) => {
      // 外部数组引用：创建一个指向外部数组的值
      let array_value = Value::{
        id: new_value_id(),
        ty: Type::Array(Type::Int),
      } // 默认Int数组

      // 创建外部数组引用指令（使用Call指令）
      let instruction = Instruction::{
        result: array_value,
        opcode: Opcode::Call(Func::Label(label.0), []),
      }

      context.current_block.instructions.push(instruction)
      ExprResult::{ value: Some(array_value), context }
    }
    Assign(lhs_name, rhs_name) => {
      // 变量赋值：lhs = rhs
      let rhs_name_str = rhs_name.to_string()
      match safe_get_var(context.var_env, rhs_name_str) {
        Ok(rhs_value) => {
          // 在SSA中，赋值操作实际上是更新变量环境
          let updated_var_env = context.var_env.add(lhs_name.to_string(), rhs_value)
          let updated_context = update_var_env(context, updated_var_env)

          // 赋值表达式返回Unit类型
          ExprResult::{ value: None, context: updated_context }
        }
        Err(err) => {
          @util.logger("Error in Assign: " + err.to_string())
          ExprResult::{ value: None, context }
        }
      }
    }
    While(cond_expr, body_expr) => {
      // While循环：使用基本块参数实现SSA
      @util.logger("While: cond=" + cond_expr.to_string() + " body=" + body_expr.to_string())

      // 分析循环体内修改的变量
      let modified_vars = analyze_modified_variables(body_expr, context.var_env)

      // 创建新的块ID
      let loop_header_id = new_block_id()
      let body_block_id = new_block_id()
      let exit_block_id = new_block_id()

      // 1. 创建循环头块参数 - 使用优化的批量创建
      let var_names_array = []
      for var_name in modified_vars.keys() {
        var_names_array.push(var_name)
      }
      let loop_params = create_block_params_with_types(var_names_array, context.var_env)

      let mut updated_var_env = context.var_env
      for i, var_name in var_names_array {
        updated_var_env = updated_var_env.add(var_name, loop_params[i])
      }

      let loop_header = BasicBlock::{
        id: loop_header_id,
        params: loop_params,
        instructions: [],
        terminator: Terminator::Return(None),
      }

      // 2. 在循环头中转换条件表达式
      let loop_header_context = Context::{
        current_block: loop_header,
        blocks: context.blocks,
        block_map: context.block_map,
        var_env: updated_var_env, // 使用包含循环参数的环境
        func_env: context.func_env,
      }

      let cond_result = convert_expr(loop_header_context, cond_expr)
      let cond_context = cond_result.context
      @util.logger("While: cond_result.value=" + cond_result.value.to_string())

      let cond_value = match cond_result.value {
        Some(val) => val
        None => {
          let (default_val, _) = create_const_int(cond_context, 0)
          default_val
        }
      }

      // 3. 更新循环头块，包含条件分支
      let updated_loop_header = BasicBlock::{
        id: loop_header_id,
        params: [],
        instructions: cond_context.current_block.instructions,
        terminator: Terminator::Branch(cond_value, body_block_id, exit_block_id),
      }

      // 4. 创建循环体块
      let body_start_block = BasicBlock::{
        id: body_block_id,
        params: [],
        instructions: [],
        terminator: Terminator::Jump(loop_header_id, []), // 跳回循环头
      }

      // 5. 在循环体中转换body表达式
      // 关键修复：确保body_context的blocks包含body_start_block
      let body_blocks = {
        let blocks = []
        for block in cond_context.blocks {
          blocks.push(block)
        }
        blocks.push(body_start_block) // 添加循环体块
        blocks
      }

      let body_context = Context::{
        current_block: body_start_block,
        blocks: body_blocks,
        block_map: cond_context.block_map,
        var_env: cond_context.var_env, // 继承条件评估后的环境
        func_env: cond_context.func_env,
      }
      let body_result = convert_expr(body_context, body_expr)
      let body_final_context = body_result.context

      // 6. 收集循环变量的最终值并更新循环体块
      let loop_args = []
      for var_name in var_names_array {
        match body_final_context.var_env.get(var_name) {
          Some(value) => loop_args.push(value)
          None => loop_args.push(context.var_env.get(var_name).unwrap())
        }
      }

      let updated_body_block = BasicBlock::{
        id: body_block_id,
        params: [],
        instructions: body_final_context.current_block.instructions,
        terminator: Terminator::Jump(loop_header_id, loop_args), // 传递循环变量值
      }

      // 7. 创建循环退出块
      let exit_block = BasicBlock::{
        id: exit_block_id,
        params: [],
        instructions: [],
        terminator: Terminator::Return(None), // 临时终止符
      }

      // 8. 更新当前块，跳转到循环头
      let initial_loop_args = []
      for var_name in var_names_array {
        match context.var_env.get(var_name) {
          Some(value) => initial_loop_args.push(value)
          None => initial_loop_args.push(Value::{ id: new_value_id(), ty: Type::Int }) // 默认值
        }
      }

      let updated_current_block = BasicBlock::{
        id: context.current_block.id,
        params: context.current_block.params,
        instructions: context.current_block.instructions,
        terminator: Terminator::Jump(loop_header_id, initial_loop_args),
      }

        // 9. 使用辅助函数构建最终块列表
      let mut final_context = add_block_to_context(context, updated_current_block)
      final_context = add_block_to_context(final_context, updated_loop_header)
      final_context = add_block_to_context(final_context, updated_body_block)
      final_context = add_block_to_context(final_context, exit_block)

      // 添加body_final_context中的新块
      for block in body_final_context.blocks {
        final_context = add_block_to_context(final_context, block)
      }

      let final_blocks = final_context.blocks

      // 10. 创建最终上下文
      // 循环退出后，循环变量保持最后一次迭代的值
      let final_var_env = context.var_env
      let mut updated_final_var_env = final_var_env
      for var_name in var_names_array {
        match body_final_context.var_env.get(var_name) {
          Some(value) => updated_final_var_env = updated_final_var_env.add(var_name, value)
          None => ()
        }
      }

      let final_context = Context::{
        current_block: exit_block,
        blocks: final_blocks,
        block_map: context.block_map,
        var_env: updated_final_var_env, // 包含循环修改后的值
        func_env: context.func_env,
      }

      // While循环返回Unit类型
      ExprResult::{ value: None, context: final_context }
    }
    StaticArrayRef(label) => {
      // 静态数组引用：类似于ExternalArray，但引用的是静态数据段中的数组
      let array_value = Value::{
        id: new_value_id(),
        ty: Type::Array(Type::Int),
      } // 默认Int数组

      // 创建静态数组引用指令
      let instruction = Instruction::{
        result: array_value,
        opcode: Opcode::Call(Func::Label("static_array_" + label.0), []), // 使用特殊的函数名标识静态数组
      }

      context.current_block.instructions.push(instruction)
      ExprResult::{ value: Some(array_value), context }
    }
    ArrayPut(array_name, index_name, value_name) => {
      // 数组赋值：array[index] = value
      // 获取数组、索引和值的Value
      let array_value = context.var_env.get(array_name.to_string()).unwrap()
      let index_value = context.var_env.get(index_name.to_string()).unwrap()
      let value_to_store = context.var_env.get(value_name.to_string()).unwrap()

      // 验证数组类型
      match array_value.ty {
        Type::Array(_) => () // 验证确实是数组类型
        _ => @util.die("Expected array type in ArrayPut")
      }

      // 创建ArrayPut指令
      let instruction = Instruction::{
        result: Value::{ id: new_value_id(), ty: Type::Unit }, // ArrayPut返回Unit
        opcode: Opcode::ArrayPut(array_value, index_value, value_to_store),
      }

      // 更新当前块的指令列表
      context.current_block.instructions.push(instruction)
      // ArrayPut是表达式，返回Unit类型
      ExprResult::{ value: None, context }
    }
    ArrayGet(array_name, index_name) => {
      // 数组访问：array[index]
      // 获取数组和索引的值
      let array_value = context.var_env.get(array_name.to_string()).unwrap()
      let index_value = context.var_env.get(index_name.to_string()).unwrap()

      // 创建结果值 - 数组元素的类型需要从数组类型中推断
      let element_type = match array_value.ty {
        Type::Array(elem_type) => elem_type
        _ => @util.die("Expected array type in ArrayGet")
      }
      let result_value = Value::{ id: new_value_id(), ty: element_type }
      let instruction = Instruction::{
        result: result_value,
        opcode: Opcode::ArrayGet(array_value, index_value),
      }

      // 更新当前块的指令列表
      context.current_block.instructions.push(instruction)
      ExprResult::{ value: Some(result_value), context }
    }
    Int(i) => {
      let (value, new_context) = create_const_int(context, i)
      ExprResult::{ value: Some(value), context: new_context }
    }
    Int64(i) => {
      let (value, new_context) = create_const_int(context, i.to_int())
      ExprResult::{ value: Some(value), context: new_context }
    }
    Neg(x) => {
      // 转换操作数
      let result = convert_expr(context, @closure.Expr::Var(x))
      let context1 = result.context
      let operand_value = result.value.unwrap()

      // 整数取负: 0 - x
      let (zero_value, context2) = create_const_int(context1, 0)
      let (result_value, final_context) = create_binary_op(context2, BinaryOpType::Sub, zero_value, operand_value, Type::Int)
      ExprResult::{ value: Some(result_value), context: final_context }
    }
    FNeg(x) => {
      // 转换操作数
      let result = convert_expr(context, @closure.Expr::Var(x))
      let context1 = result.context
      let operand_value = result.value.unwrap()

      // 浮点取负: 0.0 - x
      let (zero_value, context2) = create_const_float(context1, 0.0)
      let (result_value, final_context) = create_binary_op(context2, BinaryOpType::FSub, zero_value, operand_value, Type::Float)
      ExprResult::{ value: Some(result_value), context: final_context }
    }
    Double(d) => {
      let (value, new_context) = create_const_float(context, d)
      ExprResult::{ value: Some(value), context: new_context }
    }
    Add(x, y)
    | Sub(x, y)
    | Mul(x, y)
    | Div(x, y)
    | Mod(x, y)
    | FAdd(x, y)
    | FSub(x, y)
    | FMul(x, y)
    | FDiv(x, y)
    | FMod(x, y) => {
      // 获取两个操作数的值
      let value1 = context.var_env.get(x.to_string()).unwrap()
      let value2 = context.var_env.get(y.to_string()).unwrap()

      // 确定运算类型和结果类型
      let (op_type, result_type) = match expr {
        Add(_, _) => (BinaryOpType::Add, Type::Int)
        Sub(_, _) => (BinaryOpType::Sub, Type::Int)
        Mul(_, _) => (BinaryOpType::Mul, Type::Int)
        Div(_, _) => (BinaryOpType::Div, Type::Int)
        Mod(_, _) => (BinaryOpType::Mod, Type::Int)
        FAdd(_, _) => (BinaryOpType::FAdd, Type::Float)
        FSub(_, _) => (BinaryOpType::FSub, Type::Float)
        FMul(_, _) => (BinaryOpType::FMul, Type::Float)
        FDiv(_, _) => (BinaryOpType::FDiv, Type::Float)
        FMod(_, _) => (BinaryOpType::FMod, Type::Float)
        _ => @util.die("unexpected expression type")
      }

      let (result_value, new_context) = create_binary_op(context, op_type, value1, value2, result_type)
      ExprResult::{ value: Some(result_value), context: new_context }
    }
    IfEq(x, y, e1, e2) | IfLe(x, y, e1, e2) | IfLt(x, y, e1, e2) => {
      // 先转换条件表达式的左操作数
      let result1 = convert_expr(context, @closure.Expr::Var(x))
      let context1 = result1.context
      // 转换右操作数
      let result2 = convert_expr(context1, @closure.Expr::Var(y))
      let context2 = result2.context

      // 获取两个操作数的值
      let value1 = result1.value.unwrap()
      let value2 = result2.value.unwrap()

      // 创建比较指令的结果值
      let cmp_result = Value::{ id: new_value_id(), ty: Type::Bool }
      let cmp_instruction = Instruction::{
        result: cmp_result,
        opcode: match expr {
          IfEq(_, _, _, _) => Opcode::Eq(value1, value2)
          IfLe(_, _, _, _) => Opcode::Le(value1, value2)
          IfLt(_, _, _, _) => Opcode::Lt(value1, value2)
          _ => @util.die("unexpected expression type")
        },
      }

      // 将比较指令添加到当前块
      context2.current_block.instructions.push(cmp_instruction)

      // 创建两个分支的块
      let then_block_id = new_block_id()
      let else_block_id = new_block_id()
      let merge_block_id = new_block_id()

      // 创建then块
      let then_block = BasicBlock::{
        id: then_block_id,
        params: [],
        instructions: [],
        terminator: Terminator::Jump(merge_block_id, []),
      }

      // 创建else块
      let else_block = BasicBlock::{
        id: else_block_id,
        params: [],
        instructions: [],
        terminator: Terminator::Jump(merge_block_id, []),
      }

      // 创建合并块 - 修复无限循环问题，应该返回到调用者
      let merge_block = BasicBlock::{
        id: merge_block_id,
        params: [],
        instructions: [],
        terminator: Terminator::Return(None), // 临时设置，后续会被正确的终止指令替换
      }

      // 更新当前块的终止指令 - 使用比较结果作为分支条件
      let terminator = Terminator::Branch(
        cmp_result, then_block_id, else_block_id,
      )
      let updated_current_block = BasicBlock::{
        id: context2.current_block.id,
        params: context2.current_block.params,
        instructions: context2.current_block.instructions,
        terminator,
      }

      // 使用辅助函数更新块列表
      let mut context_with_blocks = add_block_to_context(context2, updated_current_block)
      context_with_blocks = add_blocks_to_context(context_with_blocks, [then_block, else_block, merge_block])
      context_with_blocks = update_current_block(context_with_blocks, then_block)
      context_with_blocks = update_var_env(context_with_blocks, context2.var_env)

      // 转换then分支
      let then_result = convert_expr(context_with_blocks, e1)
      let then_context = then_result.context
      let then_value = then_result.value

      // 更新then块的终止指令，跳转到合并块并传递值
      let then_args = match then_value {
        Some(v) => [v]
        None => []
      }
      let updated_then_block = BasicBlock::{
        id: then_context.current_block.id,
        params: then_context.current_block.params,
        instructions: then_context.current_block.instructions,
        terminator: Terminator::Jump(merge_block_id, then_args),
      }

      // 更新上下文，切换到else块
      let else_context = update_current_block(then_context, else_block)
      let else_context = update_var_env(else_context, context2.var_env)

      // 转换else分支
      let else_result = convert_expr(else_context, e2)
      let final_else_context = else_result.context
      let else_value = else_result.value

      // 更新else块的终止指令，跳转到合并块并传递值
      let else_args = match else_value {
        Some(v) => [v]
        None => []
      }
      let updated_else_block = BasicBlock::{
        id: final_else_context.current_block.id,
        params: final_else_context.current_block.params,
        instructions: final_else_context.current_block.instructions,
        terminator: Terminator::Jump(merge_block_id, else_args),
      }

      // 创建合并块的参数（用于接收then/else分支的值）
      let merge_param = match (then_value, else_value) {
        (Some(t_val), Some(_)) => {
          // 使用then分支的类型，两个分支应该类型一致
          let param_value = Value::{ id: new_value_id(), ty: t_val.ty }
          [param_value]
        }
        _ => []
      }

      // 更新合并块设置参数
      let updated_merge_block = BasicBlock::{
        id: merge_block_id,
        params: merge_param,
        instructions: [],
        terminator: Terminator::Return(None), // 临时设置
      }

      // 使用辅助函数更新最终块
      let mut final_context = add_block_to_context(final_else_context, updated_then_block)
      final_context = add_block_to_context(final_context, updated_else_block)
      final_context = add_block_to_context(final_context, updated_merge_block)
      final_context = update_current_block(final_context, updated_merge_block)
      final_context = update_var_env(final_context, context2.var_env)

      // 获取合并后的结果值
      let result_value = match merge_param {
        [param_val] => Some(param_val)
        _ => None
      }
      ExprResult::{ value: result_value, context: final_context }
    }
    Var(name) => {
      let var_name = name.to_string()
      // @util.logger("Var: " + var_name + " context.func_env: " + context.func_env.to_string())

      // 安全地查找变量
      match safe_get_var(context.var_env, var_name) {
        Ok(value) => ExprResult::{ value: Some(value), context }
        Err(_) => {
          // 尝试从函数环境中查找
          match safe_get_func_type(context.func_env, var_name) {
            Ok(func_type) => {
              // 找到函数，创建一个函数引用值
              let result_value = Value::{ id: new_value_id(), ty: func_type }
              let instruction = Instruction::{
                result: result_value,
                opcode: Opcode::CallRef(var_name, []),
              }

              // 更新当前块的指令列表
              context.current_block.instructions.push(instruction)
              ExprResult::{ value: Some(result_value), context }
            }
            Err(_) => {
              // 变量未找到，返回None并记录警告
              @util.logger("Warning: Variable or function not found: " + var_name)
              ExprResult::{ value: None, context }
            }
          }
        }
      }
    }
    Let((name, _ty), e1, e2) => {

      // Let绑定：先计算e1
      let result1 = convert_expr(context, e1)
      let context1 = result1.context
      // 将e1的结果绑定到name
      match result1.value {
        Some(value) => {
          // 更新环境，将name映射到value
          let updated_var_env = context1.var_env.add(name.to_string(), value)
          let updated_context = Context::{
            current_block: context1.current_block,
            blocks: context1.blocks,
            block_map: context1.block_map,
            var_env: updated_var_env,
            func_env: context1.func_env,
          }

          // 计算e2，使用更新后的环境
          let result2 = convert_expr(updated_context, e2)
          result2
        }
        None => {
          // 如果e1没有返回值，直接计算e2
          let result2 = convert_expr(context1, e2)
          result2
        }
      }
    }
    CallDirect(label, args) => {
      // @util.logger("CallDirect: " + label.0)
      // @util.logger("CallDirect args: " + args.to_string())
      // @util.logger(
      //   "CallDirect var: " +
      //   context.var_env.to_string() +
      //   " func_env: " +
      //   context.func_env.to_string(),
      // )
      // 直接函数调用
      // 先转换所有参数
      let mut current_context = context
      let arg_values = []

      // 依次转换每个参数
      for arg in args {
        // @util.logger("CallDirect arg: " + arg.to_string())
        let arg_result = convert_expr(current_context, @closure.Expr::Var(arg))
        current_context = arg_result.context
        let _debug = arg_result.to_string()
        // @util.logger("CallDirect arg: " + _debug)
        match arg_result.value {
          Some(val) => arg_values.push(val)
          None => () // 参数可能为Unit类型
        }
      }

      // 使用缓存的类型推断函数确定返回类型
      let return_type = cached_infer_type(@closure.Expr::CallDirect(label, args), current_context)
      let opcode = match context.var_env.get(label.0.to_string()) {
        Some(v) => Opcode::Call(Func::Call(v), arg_values)
        None => Opcode::Call(Func::Label(label.0), arg_values)
      }
      let result_value = Value::{ id: new_value_id(), ty: return_type }
      let instruction = Instruction::{ result: result_value, opcode }

      // 更新当前块的指令列表
      context.current_block.instructions.push(instruction)
      ExprResult::{ value: Some(result_value), context }
    }
    MakeClosure((name, ty), c, e) => {
      // 闭包创建
      // 创建闭包值
      let closure_value = Value::{ id: new_value_id(), ty: convert_type(ty) }

      // 创建闭包创建指令
      let instruction = Instruction::{
        result: closure_value,
        opcode: Opcode::MakeClosure(
          name.to_string(),
          c.actual_free_vars.map(fn(fv) {
            context.var_env.get(fv.to_string()).unwrap()
          }),
        ),
      }

      // 更新当前块的指令列表
      context.current_block.instructions.push(instruction)

      // 将闭包值绑定到name变量
      let updated_var_env = context.var_env.add(name.to_string(), closure_value)
      let intermediate_context = Context::{
        current_block: context.current_block,
        blocks: context.blocks,
        block_map: context.block_map,
        var_env: updated_var_env, // 包含新绑定的变量环境
        func_env: context.func_env,
      }
      let result = convert_expr(intermediate_context, e)
      ExprResult::{ value: result.value, context: result.context }
    }
    CallClosure(n, xs) => {
      // 闭包调用
      // 先转换闭包引用
      let closure_result = convert_expr(context, @closure.Expr::Var(n))
      let mut current_context = closure_result.context

      // 转换所有参数，正确链式传递上下文
      let call_arg_values = []
      for x in xs {
        let arg_result = convert_expr(current_context, @closure.Expr::Var(x))
        current_context = arg_result.context
        match arg_result.value {
          Some(val) => call_arg_values.push(val)
          None => () // 参数可能为Unit类型
        }
      }

      // 获取闭包值
      let closure_value = closure_result.value.unwrap()

      // 闭包调用时，需要先传递捕获的变量（自由变量），然后传递调用时的参数
      // 但在当前的CallClosure实现中，我们只需要传递调用参数
      // 因为捕获的变量已经在闭包创建时绑定了
      let result_value = Value::{ id: new_value_id(), ty: Type::Int }
      let instruction = Instruction::{
        result: result_value,
        opcode: Opcode::CallClosure(closure_value, call_arg_values),
      }

      // 更新当前块的指令列表
      context.current_block.instructions.push(instruction)
      ExprResult::{ value: Some(result_value), context }
    }
  }
}

///|
/// 转换类型
fn convert_type(ty : @closure.LowType) -> Type {
  match ty {
    Unit => Type::Unit
    Bool => Type::Bool
    Int => Type::Int
    Double => Type::Float
    DirectFn(args, ret) =>
      Type::Function(args.map(convert_type), convert_type(ret))
    ClosureFn(args, ret) =>
      Type::Function(args.map(convert_type), convert_type(ret))
    Tuple(elements) => Type::Tuple(elements.map(convert_type))
    Array(element) => Type::Array(convert_type(element))
    Ptr => Type::Pointer(Type::Int)
  }
}

///|
/// 从 @types.Type 转换到 SSA Type
fn convert_type_from_types(ty : @types.Type) -> Type {
  match ty {
    @types.Type::Unit => Type::Unit
    @types.Type::Bool => Type::Bool
    @types.Type::Int => Type::Int
    @types.Type::Double => Type::Float
    @types.Type::Fun(args, ret) =>
      Type::Function(
        args.map(convert_type_from_types),
        convert_type_from_types(ret),
      )
    @types.Type::Tuple(elements) =>
      Type::Tuple(elements.map(convert_type_from_types))
    @types.Type::Array(element) => Type::Array(convert_type_from_types(element))
    @types.Type::Ptr => Type::Pointer(Type::Int)
    @types.Type::Var(_) => Type::Int // 类型变量，默认为Int
    @types.Type::UserDefineType(_, _) => Type::Int // 用户自定义类型，默认为Int
    @types.Type::Struct(_, _) => Type::Int // 结构体，默认为Int
    @types.Type::Enum(_, _) => Type::Int // 枚举，默认为Int
    @types.Type::ArrayData(_) => Type::Array(Type::Int) // 静态数组数据，默认Int数组
  }
}


///|
/// 全局值ID计数器
let global_value_counter : Ref[Int] = Ref::new(0)

///|
/// 生成新的值ID
fn new_value_id() -> Int {
  global_value_counter.val = global_value_counter.val + 1
  global_value_counter.val
}

///|
/// 全局块ID计数器
let global_block_counter : Ref[Int] = Ref::new(0)

///|
/// 生成新的块ID
fn new_block_id() -> Block {
  global_block_counter.val = global_block_counter.val + 1
  Block::{ id: global_block_counter.val }
}

///| 批量生成值ID以提高性能
fn new_value_ids(count : Int) -> Array[Int] {
  let start_id = global_value_counter.val + 1
  global_value_counter.val = start_id + count - 1
  let ids = []
  for i = 0; i < count; i = i + 1 {
    ids.push(start_id + i)
  }
  ids
}

///| 简单的LRU类型缓存，避免重复类型推断
let type_cache : Ref[@immut/hashmap.HashMap[String, Type]] = Ref::new(@immut/hashmap.new())

///| 带缓存的类型推断
fn cached_infer_type(expr : @closure.Expr, context : Context) -> Type {
  let expr_key = expr.to_string()
  match type_cache.val.get(expr_key) {
    Some(cached_type) => cached_type
    None => {
      let inferred_type = infer_expression_type(expr, context)
      type_cache.val = type_cache.val.add(expr_key, inferred_type)
      inferred_type
    }
  }
}

///| 优化的块参数创建
fn create_block_params_with_types(var_names : Array[String], var_env : @immut/hashmap.HashMap[String, Value]) -> Array[Value] {
  let ids = new_value_ids(var_names.length())
  let params = []
  for i, var_name in var_names {
    let var_type = match var_env.get(var_name) {
      Some(value) => value.ty
      None => Type::Int // 默认类型
    }
    params.push(Value::{ id: ids[i], ty: var_type })
  }
  params
}